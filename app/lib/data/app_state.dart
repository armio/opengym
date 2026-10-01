import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'clock.dart';
import 'library.dart';
import 'local_data.dart';
import 'local_store.dart';
import 'models/models.dart';
import 'session_store.dart';
import 'sync.dart';
import 'sync_protocol.dart';

/// Connection state shown by the sync indicator.
enum SyncStatus {
  /// Up to date, or waiting for the next trigger.
  idle,

  /// A request is in flight.
  syncing,

  /// The last attempt could not reach the server; retrying with backoff.
  offline,

  /// The server answered with an error; retrying with backoff.
  error,
}

/// Creates the API client for a server (injectable for tests).
typedef ApiClientFactory = ApiClient Function(String baseUrl, String? token);

/// Thrown by [AppState.resolveProposal] when accepting a proposal written for another unit.
class ProposalUnitMismatch implements Exception {
  const ProposalUnitMismatch(this.proposalUnit);

  final String proposalUnit;

  String get message => 'La propuesta usa $proposalUnit; cambia la unidad o pide una nueva.';

  @override
  String toString() => message;
}

/// Deep copies of the `plan` and `coach` docs to build a proposal resolution or revert on
/// (contract §4.3 "draft → commit"). Mutate [plan] / [coach] synchronously, then pass the draft
/// to [AppState.resolveProposal] or [AppState.revertProposal]. The base seqs are captured when
/// the draft is taken, so a sync in between cannot make the draft overwrite newer data.
class ProposalDraft {
  ProposalDraft._(DocRecord plan, DocRecord coach)
    : plan = (plan.data as PlanDoc).copy(),
      coach = (coach.data as CoachDoc).copy(),
      planBaseSeq = plan.baseSeq,
      coachBaseSeq = coach.baseSeq,
      _updatedAt = {DocKey.plan: plan.updatedAt, DocKey.coach: coach.updatedAt},
      _planBefore = plan.data.toJson(),
      _coachBefore = coach.data.toJson();

  final PlanDoc plan;
  final CoachDoc coach;
  final int planBaseSeq;
  final int coachBaseSeq;

  /// The local `updatedAt` of each doc when the draft was taken: a doc whose stamp moved by the
  /// time the server answers was edited while the request was in flight.
  final Map<DocKey, int> _updatedAt;
  final JsonMap _planBefore;
  final JsonMap _coachBefore;

  bool get planChanged => !_jsonEquals(plan.toJson(), _planBefore);
  bool get coachChanged => !_jsonEquals(coach.toJson(), _coachBefore);
}

/// A multi-document edit in progress, handed to [AppState.edit]. Every doc or row taken from it
/// is a deep copy; changes are committed together, stamped with one `updatedAt`, only if the
/// edit function returns without throwing.
class AppDraft {
  AppDraft._(this._app);

  final AppState _app;
  final Map<DocKey, JsonModel> _docs = {};
  final Map<String, Workout?> _workouts = {};
  final Map<String, BodyWeight?> _bodyWeights = {};
  final Map<String, ExWeight?> _exWeights = {};

  T _doc<T extends JsonModel>(DocKey key) =>
      _docs.putIfAbsent(key, () => key.parse(_app._data.docs[key]!.data.toJson())) as T;

  Settings get settings => _doc(DocKey.settings);
  PlanDoc get plan => _doc(DocKey.plan);
  ScheduleDoc get schedule => _doc(DocKey.schedule);
  AthleteProfile get athlete => _doc(DocKey.athlete);

  /// The committed workouts, sorted by `(d, start)` — read-only; edit one through [workout].
  List<Workout> get workouts => _app.workouts;

  /// An editable copy of workout [id], or null.
  Workout? workout(String id) {
    if (_workouts.containsKey(id)) return _workouts[id];
    final rec = _app._data.workouts[id];
    if (rec == null || rec.deleted) return null;
    return _workouts[id] = rec.data.copy();
  }

  void putWorkout(Workout workout) => _workouts[workout.id] = workout;
  void deleteWorkout(String id) => _workouts[id] = null;

  /// An editable copy of the weigh-in of [d], or null.
  BodyWeight? bodyWeight(String d) {
    if (_bodyWeights.containsKey(d)) return _bodyWeights[d];
    final rec = _app._data.bodyWeight[d];
    if (rec == null || rec.deleted) return null;
    return _bodyWeights[d] = rec.data.copy();
  }

  void putBodyWeight(BodyWeight entry) => _bodyWeights[entry.d] = entry;
  void deleteBodyWeight(String d) => _bodyWeights[d] = null;

  /// An editable copy of the working weight of [exId], or null.
  ExWeight? exWeight(String exId) {
    if (_exWeights.containsKey(exId)) return _exWeights[exId];
    final rec = _app._data.exWeights[exId];
    if (rec == null || rec.deleted) return null;
    return _exWeights[exId] = rec.data.copy();
  }

  void putExWeight(String exId, ExWeight weight) => _exWeights[exId] = weight;
  void deleteExWeight(String exId) => _exWeights[exId] = null;
}

/// The app's single source of truth (contract §6): every synced doc and row, proposals, the
/// active workout, sync status and the session. Provided at the root with `provider`.
///
/// Reads return live objects — treat them as read-only. Every change goes through a mutator,
/// which works on a deep copy (like the original `update(fn)`), stamps `updatedAt`, marks the
/// items dirty, persists `state.json` (debounced 300 ms) and schedules a sync (2 s).
class AppState extends ChangeNotifier {
  AppState({
    required this.library,
    required this._store,
    required this._sessions,
    LocalData? data,
    this._active,
    this._session = const SessionInfo(),
    this.clock = const Clock(),
    ApiClientFactory? apiFactory,
  }) : _data = data ?? LocalData(),
       _apiFactory = apiFactory ?? ((url, token) => ApiClient(baseUrl: url, token: token)) {
    if (_session.isSignedIn) _bindApi(_apiFactory(_session.serverUrl!, _session.token));
  }

  /// Reads `state.json`, `active.json` and the session from device storage.
  static Future<AppState> load({
    required ExerciseLibrary library,
    LocalStore? store,
    SessionStore? sessions,
    Clock clock = const Clock(),
    ApiClientFactory? apiFactory,
  }) async {
    final localStore = store ?? LocalStore.platform();
    final sessionStore = sessions ?? SessionStore.platform();
    final stateJson = await localStore.readState();
    final data = stateJson == null ? LocalData() : LocalData.fromJson(stateJson);
    var activeJson = await localStore.readActive();
    if (activeJson != null) {
      final id = activeJson['id'];
      // Finishing writes state.json before deleting active.json: a leftover whose workout
      // already exists was finished — drop it.
      if (data.workouts[id]?.deleted == false) {
        await localStore.deleteActive();
        activeJson = null;
      }
    }
    return AppState(
      library: library,
      store: localStore,
      sessions: sessionStore,
      data: data,
      active: activeJson == null ? null : ActiveWorkout.fromJson(activeJson),
      session: await sessionStore.load(),
      clock: clock,
      apiFactory: apiFactory,
    );
  }

  final ExerciseLibrary library;
  final Clock clock;
  final LocalStore _store;
  final SessionStore _sessions;
  final ApiClientFactory _apiFactory;

  LocalData _data;
  ActiveWorkout? _active;
  SessionInfo _session;
  ApiClient? _api;
  SyncService? _syncService;
  bool _loggingIn = false;

  SyncStatus _syncStatus = SyncStatus.idle;
  String? _lastSyncError;
  DateTime? _lastSyncedAt;
  int _failures = 0;

  Timer? _persistTimer;
  Timer? _syncTimer;
  Timer? _retryTimer;
  final _notices = StreamController<SyncNotice>.broadcast();
  bool _disposed = false;

  /// Asked during the first sync when this device holds rows the server lacks and the server
  /// already has data. Set by the UI (login screen / shell); null uploads without asking.
  ConfirmUpload? confirmUploadLocalData;

  static const persistDelay = Duration(milliseconds: 300);
  static const syncDelay = Duration(seconds: 2);

  // ---------------------------------------------------------------------------------------
  // Session.

  /// True when a device token is stored (and no login is still running).
  bool get isSignedIn => _session.isSignedIn && !_loggingIn;

  /// Normalised server origin (also kept after sign-out, to prefill the login form).
  String? get serverUrl => _session.serverUrl;
  String? get deviceName => _session.deviceName;
  String? get deviceId => _session.deviceId;

  /// The Claude connector URL: `${server}/mcp`.
  String? get connectorUrl => serverUrl == null ? null : '$serverUrl/mcp';

  // ---------------------------------------------------------------------------------------
  // Reads.

  Settings get settings => _data.doc(DocKey.settings);
  PlanDoc get plan => _data.doc(DocKey.plan);
  ScheduleDoc get schedule => _data.doc(DocKey.schedule);
  AthleteProfile get athlete => _data.doc(DocKey.athlete);
  CoachDoc get coach => _data.doc(DocKey.coach);

  List<Workout>? _workoutsCache;

  /// Finished workouts sorted by `(d, start)` ascending (engine-Q6). Unmodifiable.
  List<Workout> get workouts => _workoutsCache ??= List.unmodifiable(
    <Workout>[
      for (final r in _data.workouts.values)
        if (!r.deleted) r.data,
    ]..sort(Workout.compare),
  );

  Workout? workoutById(String id) {
    final rec = _data.workouts[id];
    return rec == null || rec.deleted ? null : rec.data;
  }

  List<BodyWeight>? _bodyWeightCache;

  /// Weigh-ins sorted by date ascending. Unmodifiable.
  List<BodyWeight> get bodyWeights => _bodyWeightCache ??= List.unmodifiable(
    <BodyWeight>[
      for (final r in _data.bodyWeight.values)
        if (!r.deleted) r.data,
    ]..sort((a, b) => a.d.compareTo(b.d)),
  );

  /// The most recent weigh-in (`lastBW`), or null.
  BodyWeight? get lastBodyWeight => bodyWeights.isEmpty ? null : bodyWeights.last;

  Map<String, ExWeight>? _exWeightsCache;

  /// Working weights by exercise id (`exWeights`). Unmodifiable.
  Map<String, ExWeight> get exWeights => _exWeightsCache ??= Map.unmodifiable({
    for (final e in _data.exWeights.entries)
      if (!e.value.deleted) e.key: e.value.data,
  });

  /// Every known proposal, newest first.
  List<Proposal> get proposals => _data.proposals.values.sorted((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Pending proposals that have not expired yet, newest first.
  List<Proposal> get pendingProposals {
    final now = clock.nowMs();
    return [
      for (final p in proposals)
        if (p.isPending && (p.expiresAt == 0 || p.expiresAt > now)) p,
    ];
  }

  Proposal? proposalById(String id) => _data.proposals[id];

  /// The workout in progress (device-only), or null.
  ActiveWorkout? get active => _active;

  ExerciseCatalog? _catalog;
  PlanDoc? _catalogPlan;

  /// The exercise library plus this owner's custom exercises (customs first).
  ExerciseCatalog get catalog {
    final p = plan;
    if (_catalog == null || !identical(_catalogPlan, p)) {
      _catalog = ExerciseCatalog(library, p.customEx);
      _catalogPlan = p;
    }
    return _catalog!;
  }

  /// How often each exercise id appears across routine entries and workout entries
  /// (the picker's "Elegidos" order).
  Map<String, int> exerciseUsage() {
    final usage = <String, int>{};
    for (final r in plan.routines) {
      for (final e in r.ex) {
        usage[e.id] = (usage[e.id] ?? 0) + 1;
      }
    }
    for (final w in workouts) {
      for (final e in w.entries) {
        usage[e.id] = (usage[e.id] ?? 0) + 1;
      }
    }
    return usage;
  }

  SyncStatus get syncStatus => _syncStatus;

  /// Spanish message of the last failed sync, cleared on success.
  String? get lastSyncError => _lastSyncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// True while local edits are waiting to be pushed.
  bool get hasUnsyncedChanges => _data.hasDirty;
  int get unsyncedCount => _data.dirtyCount;

  /// Conflicts and rejected items to show as toasts.
  Stream<SyncNotice> get notices => _notices.stream;

  // ---------------------------------------------------------------------------------------
  // Mutations.

  /// Runs [fn] on an [AppDraft] and commits every doc and row it changed with one `updatedAt`
  /// (contract §3.3.1). If [fn] throws, nothing is committed and the error propagates.
  void edit(void Function(AppDraft draft) fn) {
    final draft = AppDraft._(this);
    fn(draft);
    _commit(draft);
  }

  void updateSettings(void Function(Settings settings) fn) => edit((d) => fn(d.settings));

  void updatePlan(void Function(PlanDoc plan) fn) => edit((d) => fn(d.plan));

  void updateSchedule(void Function(ScheduleDoc schedule) fn) => edit((d) => fn(d.schedule));

  /// Edits the athlete profile. An explicit save (the intake's "Guardar") also stamps
  /// `savedAt = now` and `updatedBy = 'app'` — the doc is pushed only once `savedAt` is set.
  void updateAthlete(void Function(AthleteProfile athlete) fn, {bool explicitSave = true}) => edit((d) {
    fn(d.athlete);
    if (explicitSave) {
      d.athlete
        ..savedAt = clock.nowMs()
        ..updatedBy = 'app';
    }
  });

  /// Adds or replaces a finished workout.
  void saveWorkout(Workout workout) => edit((d) => d.putWorkout(workout.copy()));

  /// Deletes a workout. Working weights and other workouts' `prs` are not recomputed (data-B10).
  void deleteWorkout(String id) => edit((d) => d.deleteWorkout(id));

  /// Upserts the weigh-in of [date] (default today) with weight [w] and entry time [t]
  /// (default now). Callers round [w] to 0.1 and ensure it is > 0.
  void setBodyWeight(num w, {String? date, int? t}) => edit((d) {
    final day = date ?? clock.todayIso();
    d.putBodyWeight(BodyWeight(d: day, w: w, t: t ?? clock.nowMs()));
  });

  /// Deletes the weigh-in of [date].
  void deleteBodyWeight(String date) => edit((d) => d.deleteBodyWeight(date));

  /// Sets the working weight of [exId] (`exWeights[exId] = {w, d}`), [date] defaulting to today.
  void setExWeight(String exId, num w, {String? date}) =>
      edit((d) => d.putExWeight(exId, ExWeight(w: w, d: date ?? clock.todayIso())));

  void deleteExWeight(String exId) => edit((d) => d.deleteExWeight(exId));

  /// Deletes a routine, every weekday assigned to it and every reschedule to it — `plan` and
  /// `schedule` in one stamped edit. Workouts keep their `routineId`.
  void deleteRoutine(String routineId) => edit((d) {
    d.plan.routines.removeWhere((r) => r.id == routineId);
    d.plan.week.removeWhere((_, id) => id == routineId);
    d.schedule.dayPlan.removeWhere((_, id) => id == routineId);
  });

  /// Deletes a custom exercise: removes it from `customEx` and every routine (cleaning up
  /// orphaned supersets), stamps its name into history entries (`e.n`), and deletes its
  /// working weight — all in one stamped edit. Returns false (and changes nothing) while the
  /// active workout contains it ("Termina tu entreno actual primero").
  bool deleteCustomExercise(String exId) {
    if (_active?.entries.any((e) => e.id == exId) ?? false) return false;
    final custom = plan.customById(exId);
    edit((d) {
      d.plan.customEx.removeWhere((c) => c.id == exId);
      for (final r in d.plan.routines) {
        r.ex.removeWhere((e) => e.id == exId);
        Routine.cleanupSupersets(r.ex);
      }
      for (final w in workouts) {
        if (!w.entries.any((e) => e.id == exId)) continue;
        final copy = d.workout(w.id)!;
        for (final e in copy.entries) {
          if (e.id == exId) e.n = custom?.n ?? e.n;
        }
      }
      d.deleteExWeight(exId);
    });
    return true;
  }

  // ---------------------------------------------------------------------------------------
  // Active workout (device-only; contract §6 persistence ordering).

  /// Starts [workout] (replacing any active one). `state.json` is written first — it holds the
  /// check-in weigh-in — then `active.json`.
  Future<void> startActive(ActiveWorkout workout) async {
    await _writeStateNow();
    _active = workout.copy();
    notifyListeners();
    await _store.writeActive(_active!.toJson());
  }

  /// Edits the active workout on a copy and rewrites `active.json`. Does not sync.
  void updateActive(void Function(ActiveWorkout active) fn) {
    final current = _active;
    if (current == null) throw StateError('No hay ningún entreno en curso.');
    final next = current.copy();
    fn(next);
    _active = next;
    notifyListeners();
    unawaited(_store.writeActive(next.toJson()));
  }

  /// Finishes the active workout: [fn] adds the finished [Workout] and working weights through
  /// the draft (committed with one `updatedAt`), then `state.json` is written **before**
  /// `active.json` is deleted.
  Future<void> finishActive(void Function(AppDraft draft) fn) async {
    if (_active == null) throw StateError('No hay ningún entreno en curso.');
    edit(fn);
    _active = null;
    notifyListeners();
    await _writeStateNow();
    await _store.deleteActive();
  }

  /// Throws the active workout away (state.json first, then active.json is deleted).
  Future<void> discardActive() async {
    _active = null;
    notifyListeners();
    await _writeStateNow();
    await _store.deleteActive();
  }

  // ---------------------------------------------------------------------------------------
  // Online compound calls.

  /// Deep copies of `plan` + `coach` to build a resolution or revert on.
  ProposalDraft beginProposalDraft() => ProposalDraft._(_data.docs[DocKey.plan]!, _data.docs[DocKey.coach]!);

  /// Accepts or dismisses [proposal] atomically with its doc writes (contract §4.3).
  ///
  /// [draft] carries the result of `markStale` + `applyChangeSet` / `applyCreatedPlan` /
  /// `recordDismissal`; only the docs it changed are sent. Omit it for a `nochange`
  /// acknowledgement. On success the returned docs are committed; on a 409 or a network error
  /// nothing local changes, a pull is started and the error is rethrown ([ConflictException],
  /// [OfflineException], …). Accepting a proposal whose `unit` differs from `settings.unit`
  /// throws [ProposalUnitMismatch] without calling the server.
  Future<Proposal> resolveProposal(
    Proposal proposal, {
    required String outcome,
    List<String> accepted = const [],
    List<String> rejected = const [],
    List<String> stale = const [],
    bool? schedule,
    ProposalDraft? draft,
  }) async {
    if (outcome == 'applied' && proposal.kind != Proposal.kindNoChange && proposal.unit != settings.unit) {
      throw ProposalUnitMismatch(proposal.unit);
    }
    final body = <String, dynamic>{
      'outcome': outcome,
      'accepted': accepted,
      'rejected': rejected,
      'stale': stale,
      'schedule': ?schedule,
      'docs': draft == null ? const [] : _draftDocs(draft, onlyChanged: true),
    };
    return _proposalWrite(proposal, () => _requireApi().resolveProposal(proposal.id, body), draft: draft);
  }

  /// Reverts an applied proposal: [draft] holds the restored plan and the coach doc with the
  /// snapshot popped and the revert log entry appended (contract §4.3). Same error handling as
  /// [resolveProposal].
  Future<Proposal> revertProposal(Proposal proposal, ProposalDraft draft) => _proposalWrite(
    proposal,
    () => _requireApi().revertProposal(proposal.id, {'docs': _draftDocs(draft, onlyChanged: false)}),
    draft: draft,
  );

  List<JsonMap> _draftDocs(ProposalDraft draft, {required bool onlyChanged}) => [
    if (!onlyChanged || draft.planChanged)
      {'key': DocKey.plan.wire, 'data': draft.plan.toJson(), 'baseSeq': draft.planBaseSeq},
    if (!onlyChanged || draft.coachChanged)
      {'key': DocKey.coach.wire, 'data': draft.coach.toJson(), 'baseSeq': draft.coachBaseSeq},
  ];

  Future<Proposal> _proposalWrite(
    Proposal proposal,
    Future<ProposalWriteResult> Function() call, {
    ProposalDraft? draft,
  }) async {
    try {
      final result = await call();
      for (final sd in result.docs) {
        final key = DocKey.fromWire(sd.key);
        if (key == null) continue;
        // The server committed the draft; an edit made locally meanwhile (the tabs stay usable
        // while the request runs) was based on the old doc and is replaced — say so.
        final takenAt = draft?._updatedAt[key];
        if (takenAt != null && _data.docs[key]!.updatedAt != takenAt && !_notices.isClosed) {
          _notices.add(DraftOverwrittenNotice(key));
        }
        _data.docs[key] = DocRecord(data: key.parse(sd.data), baseSeq: sd.seq, updatedAt: sd.updatedAt);
        _data.dirtyDocs.remove(key);
      }
      _data.proposals[result.proposal.id] = result.proposal;
      _changed();
      return result.proposal;
    } on ConflictException catch (e) {
      final server = asMapOrNull(e.body['proposal']);
      if (server != null) {
        final p = Proposal.fromJson(server);
        _data.proposals[p.id] = p;
        _changed();
      }
      unawaited(sync());
      rethrow;
    } on UnauthorizedException {
      await _signOutLocal(clearData: false);
      rethrow;
    } on ApiException {
      unawaited(sync());
      rethrow;
    }
  }

  /// Imports an openGym JSON backup on the server (contract §4.4). `replace` then rebuilds
  /// local data from the server (the workout in progress is kept); `merge` just syncs.
  Future<ImportResult> importBackup(JsonMap state, {String mode = 'replace'}) async {
    final result = await _guarded(() => _requireApi().importBackup(state, mode: mode));
    if (mode == 'replace') {
      await _replaceLocalWithServer();
    } else {
      await sync();
    }
    return result;
  }

  /// "Borrar todo" (contract §4.6): erases all training data on the server, then deletes the
  /// local data (including the workout in progress) and pulls from 0.
  Future<void> resetAll() async {
    await _guarded(() => _requireApi().reset());
    _active = null;
    await _store.deleteActive();
    await _replaceLocalWithServer();
  }

  Future<List<DeviceInfo>> listDevices() => _guarded(() => _requireApi().devices());

  Future<void> revokeDevice(String deviceId) => _guarded(() => _requireApi().revokeDevice(deviceId));

  /// "Revocar acceso de Claude": revokes every OAuth grant of the MCP connector.
  Future<void> revokeClaudeAccess() => _guarded(() => _requireApi().revokeClaudeAccess());

  /// The openGym backup document `S` rebuilt from local data (contract §4.4 "export").
  JsonMap exportOpenGymState() {
    final a = athlete;
    final profile = a.savedAt == null
        ? null
        : (a.toJson()
            ..remove('savedAt')
            ..remove('updatedBy'));
    final c = coach;
    return {
      ...settings.toJson(),
      'routines': [for (final r in plan.routines) r.toJson()],
      'week': {...plan.week},
      'customEx': [for (final x in plan.customEx) x.toJson()],
      'dayPlan': {...schedule.dayPlan},
      'exWeights': {for (final e in exWeights.entries) e.key: e.value.toJson()},
      'workouts': [for (final w in workouts) w.toJson()],
      'bodyweight': [for (final b in bodyWeights) b.toJson()],
      'coach': {
        'consent': null,
        'profile': profile,
        'cadence': 'off',
        'lastReview': c.lastReview,
        'log': [for (final e in c.log) deepCopyMap(e)],
        'snapshots': [for (final s in c.snapshots) s.toJson()],
      },
      'active': null,
      '_ts': clock.nowMs(),
    };
  }

  Future<T> _guarded<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on UnauthorizedException {
      await _signOutLocal(clearData: false);
      rethrow;
    }
  }

  Future<void> _replaceLocalWithServer() async {
    final fresh = LocalData()
      ..epoch = _data.epoch
      ..clockOffset = _data.clockOffset
      ..hasClockOffset = _data.hasClockOffset;
    _replaceData(fresh);
    await _writeStateNow();
    await sync();
  }

  // ---------------------------------------------------------------------------------------
  // Login / logout.

  /// Signs this device in and runs the first, pull-only sync (contract §3.3.3), reporting
  /// [onProgress]. Throws [FormatException] for a bad [serverUrl] and [ApiException]s from the
  /// login call (401 = wrong password, 429 = rate limited, [OfflineException]). A failing first
  /// sync does not undo the login: it is retried by the next [sync].
  Future<void> login({
    required String serverUrl,
    required String password,
    required String deviceName,
    void Function(SyncProgress progress)? onProgress,
    ConfirmUpload? confirmUpload,
  }) async {
    final url = normalizeServerUrl(serverUrl);
    var name = deviceName.trim();
    if (name.isEmpty) name = 'Dispositivo';
    if (name.length > 60) name = name.substring(0, 60);
    final api = _apiFactory(url, null);
    final result = await api.login(password: password, deviceName: name);
    api.token = result.token;
    final session = SessionInfo(serverUrl: url, deviceName: name, deviceId: result.deviceId, token: result.token);
    await _sessions.save(session);

    _loggingIn = true;
    try {
      _session = session;
      _bindApi(api);
      _data.needsInitialSync = true;
      await _writeStateNow();
      await _runSync(confirmUpload: confirmUpload ?? confirmUploadLocalData, onProgress: onProgress);
    } finally {
      _loggingIn = false;
      notifyListeners();
    }
  }

  /// "Cerrar sesión" (contract §4.6): pushes dirty items first; if some remain unsynced, asks
  /// [confirmUnsynced] ("Hay cambios sin sincronizar — ¿salir igualmente?"). Then revokes the
  /// token on the server (best effort) and deletes local data and the token. Returns false if
  /// the owner chose to stay.
  Future<bool> logout({required Future<bool> Function() confirmUnsynced}) async {
    if (_data.hasDirty) {
      await _runSync();
      if (_data.hasDirty && !await confirmUnsynced()) return false;
    }
    try {
      await _api?.logout();
    } on ApiException catch (e) {
      debugPrint('logout: $e');
    }
    await _signOutLocal(clearData: true);
    return true;
  }

  Future<void> _signOutLocal({required bool clearData}) async {
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _persistTimer?.cancel();
    await _sessions.clearToken();
    _session = _session.withoutToken();
    _api?.close();
    _api = null;
    _syncService = null;
    if (clearData) {
      _active = null;
      _replaceData(LocalData());
      await _store.clear();
    } else {
      await _writeStateNow();
    }
    _syncStatus = SyncStatus.idle;
    _lastSyncError = null;
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------------------
  // Sync scheduling.

  /// Syncs now (app start, resume, pull-to-refresh). Never throws: failures set [syncStatus] /
  /// [lastSyncError] and schedule a retry with backoff; a 401 signs the device out, keeping
  /// local data and dirty sets for after the next login.
  Future<void> sync() => _runSync();

  /// Call when the app returns to the foreground.
  Future<void> onResumed() {
    DeviceTimeZone.refresh();
    return sync();
  }

  /// Call when the app goes to the background: writes pending local changes now.
  Future<void> onPaused() => _writeStateNow();

  Future<void> _runSync({ConfirmUpload? confirmUpload, void Function(SyncProgress)? onProgress}) async {
    final service = _syncService;
    if (service == null || _disposed) return;
    if (service.isRunning && !_data.needsInitialSync) {
      // Joins the run in flight (and asks it for one more pass); the caller that started it
      // reports notices and failures, so they are not toasted or counted twice.
      try {
        await service.sync();
      } catch (_) {}
      return;
    }
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _setStatus(SyncStatus.syncing, _lastSyncError);
    try {
      final report = _data.needsInitialSync
          ? await service.initialSync(confirmUpload: confirmUpload ?? confirmUploadLocalData, onProgress: onProgress)
          : await service.sync();
      _failures = 0;
      _lastSyncedAt = clock.now();
      _setStatus(SyncStatus.idle, null);
      for (final n in report.notices) {
        if (!_notices.isClosed) _notices.add(n);
      }
    } on UnauthorizedException {
      await _signOutLocal(clearData: false);
    } on OfflineException catch (e) {
      _failed(SyncStatus.offline, e.message);
    } on ApiException catch (e) {
      _failed(SyncStatus.error, e.message);
    } catch (e, stack) {
      debugPrint('sync failed: $e\n$stack');
      _failed(SyncStatus.error, 'Error inesperado al sincronizar.');
    }
  }

  void _failed(SyncStatus status, String message) {
    _failures++;
    _setStatus(status, message);
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(syncBackoff(_failures), () => unawaited(sync()));
  }

  void _setStatus(SyncStatus status, String? error) {
    if (_syncStatus == status && _lastSyncError == error) return;
    _syncStatus = status;
    _lastSyncError = error;
    if (!_disposed) notifyListeners();
  }

  void _scheduleSync() {
    if (_syncService == null || _disposed) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(syncDelay, () => unawaited(sync()));
  }

  void _bindApi(ApiClient api) {
    _api = api;
    _syncService = SyncService(data: _data, api: api, clock: clock, onChanged: _changed);
  }

  void _replaceData(LocalData data) {
    _data = data;
    final api = _api;
    if (api != null) _bindApi(api);
    _invalidateCaches();
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------------------
  // Commit and persistence.

  void _commit(AppDraft draft) {
    final docs = <DocKey, JsonModel>{
      for (final e in draft._docs.entries)
        if (!_jsonEquals(e.value.toJson(), _data.docs[e.key]!.data.toJson())) e.key: e.value,
    };
    final workouts = _changedRows(draft._workouts, _data.workouts);
    final bodyWeights = _changedRows(draft._bodyWeights, _data.bodyWeight);
    final exWeights = _changedRows(draft._exWeights, _data.exWeights);
    if (docs.isEmpty && workouts.isEmpty && bodyWeights.isEmpty && exWeights.isEmpty) return;

    // One stamp for everything the edit touched: later than now and than every previous stamp.
    var stamp = clock.nowMs() + _data.clockOffset;
    for (final k in docs.keys) {
      stamp = math.max(stamp, _data.docs[k]!.updatedAt + 1);
    }
    for (final id in workouts.keys) {
      stamp = math.max(stamp, (_data.workouts[id]?.updatedAt ?? 0) + 1);
    }
    for (final d in bodyWeights.keys) {
      stamp = math.max(stamp, (_data.bodyWeight[d]?.updatedAt ?? 0) + 1);
    }
    for (final id in exWeights.keys) {
      stamp = math.max(stamp, (_data.exWeights[id]?.updatedAt ?? 0) + 1);
    }

    for (final e in docs.entries) {
      final rec = _data.docs[e.key]!;
      rec
        ..data = e.value
        ..updatedAt = stamp;
      _data.dirtyDocs.add(e.key);
    }
    _applyRows(workouts, _data.workouts, _data.dirtyWorkouts, stamp);
    _applyRows(bodyWeights, _data.bodyWeight, _data.dirtyBodyWeight, stamp);
    _applyRows(exWeights, _data.exWeights, _data.dirtyExWeights, stamp);
    _changed();
    _scheduleSync();
  }

  /// The entries of [draft] that differ from [rows] (null = delete).
  static Map<String, T?> _changedRows<T extends JsonModel>(Map<String, T?> draft, Map<String, RowRecord<T>> rows) => {
    for (final e in draft.entries)
      if (_rowChanged(e.value, rows[e.key])) e.key: e.value,
  };

  static bool _rowChanged<T extends JsonModel>(T? next, RowRecord<T>? current) {
    final live = current != null && !current.deleted;
    if (next == null) return live;
    return !live || !_jsonEquals(next.toJson(), current.data.toJson());
  }

  static void _applyRows<T extends JsonModel>(
    Map<String, T?> changes,
    Map<String, RowRecord<T>> rows,
    Set<String> dirty,
    int stamp,
  ) {
    for (final e in changes.entries) {
      final next = e.value;
      if (next == null) {
        // Keep the last data as a tombstone so the push can carry d/start/routineId.
        rows[e.key]!
          ..deleted = true
          ..updatedAt = stamp;
      } else {
        rows[e.key] = RowRecord(data: next, updatedAt: stamp);
      }
      dirty.add(e.key);
    }
  }

  /// After any change to [_data]: drop derived caches, persist (debounced) and notify.
  void _changed() {
    _invalidateCaches();
    _schedulePersist();
    if (!_disposed) notifyListeners();
  }

  void _invalidateCaches() {
    _workoutsCache = null;
    _bodyWeightCache = null;
    _exWeightsCache = null;
  }

  void _schedulePersist() {
    if (_disposed) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDelay, () => unawaited(_writeStateNow()));
  }

  Future<void> _writeStateNow() {
    _persistTimer?.cancel();
    _persistTimer = null;
    return _store.writeState(_data.toJson());
  }

  /// Writes pending local changes to disk now.
  Future<void> flush() => _writeStateNow();

  ApiClient _requireApi() {
    final api = _api;
    if (api == null) throw const UnauthorizedException('No has iniciado sesión.');
    return api;
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    _notices.close();
    super.dispose();
  }
}

bool _jsonEquals(Object? a, Object? b) => const DeepCollectionEquality().equals(a, b);
