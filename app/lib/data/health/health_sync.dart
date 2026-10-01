import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../api_client.dart';
import '../app_state.dart';
import '../clock.dart';
import '../dates.dart';
import '../models/models.dart';
import 'health_bridge.dart';
import 'health_math.dart';
import 'health_prefs.dart';

/// Apple Health sync (contract §8), device-only:
///
/// 1. **Workouts → Health:** every finished workout becomes a strength-training workout (with
///    an estimated calorie count); editing its times or deleting it updates or removes that copy.
/// 2. **Body weight both ways:** readings from other sources (a smart scale) become the day's
///    weigh-in unless openGym already has a newer one; weigh-ins entered in openGym are saved in
///    Health, and replaced or removed there when they change.
/// 3. **Recovery → server:** daily resting heart rate, HRV and sleep go to `POST /api/recovery`
///    for Claude's `get_recovery`.
///
/// Runs on start and on resume (everything), and a few seconds after workouts or weigh-ins
/// change (exports only). Never throws from [sync]: failures land in [lastError].
class HealthSync extends ChangeNotifier {
  HealthSync({
    required this.app,
    required this.bridge,
    HealthPrefsStore? store,
    Clock? clock,
    this.observeLifecycle = true,
    this.exportDelay = const Duration(seconds: 3),
  }) : _store = store ?? const SharedPrefsHealthStore(),
       clock = clock ?? app.clock;

  final AppState app;
  final HealthBridge bridge;
  final Clock clock;
  final HealthPrefsStore _store;

  /// Re-reads Apple Health when the app returns to the foreground (off in unit tests).
  final bool observeLifecycle;

  /// How long after a change to workouts or weigh-ins the exports run.
  final Duration exportDelay;

  /// Recovery is uploaded at most this often unless forced.
  static const recoveryInterval = Duration(hours: 1);

  /// Workouts finished up to a week before connecting are saved too.
  static const workoutLookback = Duration(days: 7);

  /// openGym weigh-ins up to a month before connecting are saved too.
  static const weightLookback = Duration(days: 30);

  /// Days read from Health the first time (weights) and uploaded the first time (recovery).
  static const firstBackfillDays = 90;

  /// Later runs re-read from a few days before the previous run, and never less than two weeks.
  static const overlapDays = 3;
  static const minWindowDays = 14;
  static const maxLookbackDays = 365;

  /// Bookkeeping older than this is forgotten.
  static const ledgerDays = 400;

  HealthPrefs _prefs = HealthPrefs();
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  bool _wanted = false;
  bool _wantRead = false;
  bool _wantForce = false;
  Timer? _exportTimer;
  AppLifecycleListener? _lifecycle;
  Object? _seenWorkouts;
  Object? _seenWeights;

  /// True on an iPhone; the settings section is hidden elsewhere.
  bool get isSupported => bridge.isSupported;
  bool get isLoaded => _loaded;
  bool get isConnected => _prefs.connected;
  bool get writeWorkouts => _prefs.writeWorkouts;
  bool get syncWeight => _prefs.syncWeight;
  bool get shareRecovery => _prefs.shareRecovery;
  bool get isSyncing => _inFlight != null;
  DateTime? get lastSyncAt =>
      _prefs.lastSyncAt == null ? null : DateTime.fromMillisecondsSinceEpoch(_prefs.lastSyncAt!);
  String? get lastError => _prefs.lastError;

  /// Loads the settings and starts watching the app. Does nothing without Apple Health.
  Future<void> start() async {
    if (!isSupported || _loaded) return;
    _prefs = await _store.load();
    _loaded = true;
    if (_disposed) return;
    _seenWorkouts = app.workouts;
    _seenWeights = app.bodyWeights;
    app.addListener(_onAppChanged);
    if (observeLifecycle) _lifecycle = AppLifecycleListener(onResume: () => unawaited(sync(readHealth: true)));
    notifyListeners();
    await sync(readHealth: true);
  }

  // ---------------------------------------------------------------------------------------
  // Settings (called from Ajustes → Apple Health).

  /// Shows the permission sheet, then turns the sync on and runs it. Throws a
  /// [HealthUnavailableException] when Apple Health refuses.
  Future<void> connect() async {
    await bridge.requestAuthorization();
    _prefs
      ..connected = true
      ..connectedAt ??= clock.nowMs()
      ..lastError = null;
    await _changed();
    await sync(readHealth: true, force: true);
  }

  /// Stops the sync. With recovery sharing on, the server's recovery days are deleted first
  /// (throws an [ApiException] when that fails, and nothing changes). Data already saved in
  /// Apple Health stays there.
  Future<void> disconnect() async {
    if (_prefs.shareRecovery) await app.clearRecovery();
    _prefs
      ..connected = false
      ..lastRecoveryUploadAt = null
      ..lastError = null;
    await _changed();
  }

  Future<void> setWriteWorkouts(bool on) async {
    _prefs.writeWorkouts = on;
    await _changed();
    if (on) await sync();
  }

  Future<void> setSyncWeight(bool on) async {
    _prefs.syncWeight = on;
    await _changed();
    if (on) await sync(readHealth: true);
  }

  /// Turning sharing off deletes the recovery days on the server first (throws an
  /// [ApiException] when that fails, and sharing stays on).
  Future<void> setShareRecovery(bool on) async {
    if (!on) await app.clearRecovery();
    _prefs
      ..shareRecovery = on
      ..lastRecoveryUploadAt = null;
    await _changed();
    if (on) await sync(readHealth: true, force: true);
  }

  // ---------------------------------------------------------------------------------------
  // Running.

  bool get _canRun => isSupported && _loaded && !_disposed && _prefs.connected && app.isSignedIn;

  /// Runs the enabled steps. [readHealth] also imports weights and uploads recovery (when due,
  /// or always with [force]). Joins a run in flight, which then makes one more pass.
  Future<void> sync({bool readHealth = false, bool force = false}) {
    if (!_canRun) return Future.value();
    _wanted = true;
    _wantRead |= readHealth;
    _wantForce |= force;
    final running = _inFlight;
    if (running != null) return running;
    notifyListeners();
    return _inFlight = _loop().whenComplete(() {
      _inFlight = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _loop() async {
    while (_wanted && _canRun) {
      final read = _wantRead;
      final force = _wantForce;
      _wanted = _wantRead = _wantForce = false;
      await _runOnce(readHealth: read, force: force);
    }
  }

  Future<void> _runOnce({required bool readHealth, required bool force}) async {
    final now = clock.now();
    String? error;
    Future<void> step(Future<void> Function() fn) async {
      try {
        await fn();
      } on HealthUnavailableException catch (e) {
        error ??= e.message;
      } on ApiException catch (e) {
        error ??= e.message;
      } catch (e, stack) {
        debugPrint('health sync: $e\n$stack');
        error ??= 'Error inesperado al sincronizar con Apple Health.';
      }
    }

    if (_prefs.writeWorkouts) await step(() => _exportWorkouts(now));
    if (_prefs.syncWeight) {
      if (readHealth) await step(() => _importWeights(now));
      await step(() => _exportWeights(now));
    }
    if (_prefs.shareRecovery && readHealth && (force || _recoveryDue(now))) await step(() => _uploadRecovery(now));
    _prefs
      ..lastSyncAt = now.millisecondsSinceEpoch
      ..lastError = error;
    _prune(now);
    await _save();
  }

  void _onAppChanged() {
    if (!_canRun) return;
    final workouts = app.workouts;
    final weights = app.bodyWeights;
    if (identical(workouts, _seenWorkouts) && identical(weights, _seenWeights)) return;
    _seenWorkouts = workouts;
    _seenWeights = weights;
    if (!_prefs.writeWorkouts && !_prefs.syncWeight) return;
    _exportTimer?.cancel();
    _exportTimer = Timer(exportDelay, () => unawaited(sync()));
  }

  bool _recoveryDue(DateTime now) {
    final last = _prefs.lastRecoveryUploadAt;
    return last == null || now.millisecondsSinceEpoch - last >= recoveryInterval.inMilliseconds;
  }

  /// First date of a read window: [firstBackfillDays] the first time, else from a few days
  /// before [last] (and at least [minWindowDays]).
  String _windowStart(int? last, String today) {
    final start = last == null
        ? addIsoDays(today, -(firstBackfillDays - 1))
        : _minIso(
            addIsoDays(isoDate(DateTime.fromMillisecondsSinceEpoch(last)), -overlapDays),
            addIsoDays(today, -(minWindowDays - 1)),
          );
    return _maxIso(start, addIsoDays(today, -maxLookbackDays));
  }

  // ---------------------------------------------------------------------------------------
  // 1. Workouts → Health.

  Future<void> _exportWorkouts(DateTime now) async {
    final since = (_prefs.connectedAt ?? now.millisecondsSinceEpoch) - workoutLookback.inMilliseconds;
    final live = <String>{};
    for (final w in app.workouts) {
      live.add(w.id);
      // Imported sessions have no duration (end == start): nothing to save.
      if (w.end <= w.start || w.end < since || w.end > now.millisecondsSinceEpoch) continue;
      final saved = _prefs.workouts[w.id];
      if (saved != null && saved.start == w.start && saved.end == w.end) continue;
      if (saved != null) {
        await bridge.deleteWorkout(saved.uuid);
        _prefs.workouts.remove(w.id);
        await _save();
      }
      final uuid = await bridge.writeStrengthWorkout(
        start: DateTime.fromMillisecondsSinceEpoch(w.start),
        end: DateTime.fromMillisecondsSinceEpoch(w.end),
        kcal: estimateActiveKcal(durationMs: w.end - w.start, bodyKg: _bodyKgFor(w)),
        title: w.name.isEmpty ? 'openGym' : w.name,
      );
      _prefs.workouts[w.id] = ExportedWorkout(uuid: uuid, start: w.start, end: w.end);
      await _save();
    }
    for (final id in [..._prefs.workouts.keys]) {
      // Only a tombstone means "deleted": after signing out the list is just empty.
      if (live.contains(id) || !app.isWorkoutDeleted(id)) continue;
      await bridge.deleteWorkout(_prefs.workouts[id]!.uuid);
      _prefs.workouts.remove(id);
      await _save();
    }
  }

  /// The body weight (kg) for a workout's calorie estimate: its check-in, else the last
  /// weigh-in on or before its date, else the latest one.
  double? _bodyKgFor(Workout w) {
    var weight = w.bw;
    if (weight == null) {
      BodyWeight? before;
      for (final b in app.bodyWeights) {
        if (b.d.compareTo(w.d) > 0) break;
        before = b;
      }
      weight = (before ?? app.lastBodyWeight)?.w;
    }
    return weight == null ? null : toKg(weight, app.settings.unit);
  }

  // ---------------------------------------------------------------------------------------
  // 2. Body weight both ways.

  Future<void> _importWeights(DateTime now) async {
    final from = _windowStart(_prefs.lastWeightImportAt, isoDate(now));
    final readings = await bridge.readWeights(startOfIsoDate(from), now);
    final own = {for (final e in _prefs.weights.values) e.uuid};
    final latestByDay = <String, HealthReading>{};
    for (final r in readings) {
      if (own.contains(r.uuid) || r.value <= 0) continue;
      final d = isoDate(r.start);
      final current = latestByDay[d];
      if (current == null || r.start.isAfter(current.start)) latestByDay[d] = r;
    }
    final unit = app.settings.unit;
    final existing = {for (final b in app.bodyWeights) b.d: b};
    final updates = <BodyWeight>[];
    for (final MapEntry(key: d, value: r) in latestByDay.entries) {
      final t = r.start.millisecondsSinceEpoch;
      final mine = existing[d];
      // openGym keeps a weigh-in at least as recent; a deletion made after the reading stands.
      if (mine != null && mine.t >= t - 1000) continue;
      final deletedAt = app.bodyWeightDeletedAt(d);
      if (mine == null && deletedAt != null && deletedAt >= t) continue;
      final w = fromKg(r.value, unit);
      if (w > 0) updates.add(BodyWeight(d: d, w: w, t: t));
    }
    if (updates.isNotEmpty) {
      for (final b in updates) {
        _prefs.importedWeights[b.d] = b.t;
      }
      app.edit((draft) {
        for (final b in updates) {
          draft.putBodyWeight(b);
        }
      });
    }
    _prefs.lastWeightImportAt = now.millisecondsSinceEpoch;
  }

  Future<void> _exportWeights(DateTime now) async {
    final since = (_prefs.connectedAt ?? now.millisecondsSinceEpoch) - weightLookback.inMilliseconds;
    final unit = app.settings.unit;
    final live = <String>{};
    for (final b in app.bodyWeights) {
      live.add(b.d);
      if (b.t < since || b.t > now.millisecondsSinceEpoch + 60000) continue;
      if (_prefs.importedWeights[b.d] == b.t) continue; // it came from Apple Health
      final saved = _prefs.weights[b.d];
      if (saved != null && saved.t == b.t && saved.w == b.w) continue;
      if (saved != null) {
        await bridge.deleteWeight(saved.uuid);
        _prefs.weights.remove(b.d);
        await _save();
      }
      final uuid = await bridge.writeWeight(kg: toKg(b.w, unit), at: DateTime.fromMillisecondsSinceEpoch(b.t));
      _prefs.weights[b.d] = ExportedWeight(uuid: uuid, w: b.w, t: b.t);
      await _save();
    }
    for (final d in [..._prefs.weights.keys]) {
      if (live.contains(d) || app.bodyWeightDeletedAt(d) == null) continue;
      await bridge.deleteWeight(_prefs.weights[d]!.uuid);
      _prefs.weights.remove(d);
      await _save();
    }
  }

  // ---------------------------------------------------------------------------------------
  // 3. Recovery → server.

  Future<void> _uploadRecovery(DateTime now) async {
    final today = isoDate(now);
    final from = _windowStart(_prefs.lastRecoveryUploadAt, today);
    final start = startOfIsoDate(from);
    // The first sleep day starts at 18:00 the evening before.
    final eve = parseIsoDate(addIsoDays(from, -1))!;
    final days = buildRecoveryDays(
      from: from,
      to: today,
      restingHeartRate: await bridge.readRestingHeartRate(start, now),
      heartRateVariability: await bridge.readHeartRateVariability(start, now),
      sleep: await bridge.readSleep(DateTime(eve.year, eve.month, eve.day, 18), now),
    );
    await app.uploadRecovery([for (final d in days) d.toJson()]);
    _prefs.lastRecoveryUploadAt = now.millisecondsSinceEpoch;
  }

  // ---------------------------------------------------------------------------------------
  // Bookkeeping.

  void _prune(DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - const Duration(days: ledgerDays).inMilliseconds;
    _prefs.workouts.removeWhere((_, w) => w.end < cutoff);
    _prefs.weights.removeWhere((_, w) => w.t < cutoff);
    _prefs.importedWeights.removeWhere((_, t) => t < cutoff);
  }

  Future<void> _save() => _store.save(_prefs);

  Future<void> _changed() async {
    await _save();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _exportTimer?.cancel();
    _lifecycle?.dispose();
    if (_loaded) app.removeListener(_onAppChanged);
    super.dispose();
  }
}

String _minIso(String a, String b) => a.compareTo(b) <= 0 ? a : b;
String _maxIso(String a, String b) => a.compareTo(b) >= 0 ? a : b;
