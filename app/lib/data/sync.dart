import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'clock.dart';
import 'local_data.dart';
import 'models/models.dart';
import 'sync_protocol.dart';

/// Something the owner should be told after a sync (shown as a toast).
sealed class SyncNotice {
  const SyncNotice();

  /// Spanish text for the toast.
  String get message;
}

/// A local doc edit lost its compare-and-swap and was replaced by the server version.
class DocConflictNotice extends SyncNotice {
  const DocConflictNotice(this.key);

  final DocKey key;

  @override
  String get message => 'Se descartó un cambio sin sincronizar: ${key.labelEs} cambió en otro dispositivo.';
}

/// A local edit to [key] made while a proposal resolution or revert was in flight was replaced by
/// the version the server committed.
class DraftOverwrittenNotice extends SyncNotice {
  const DraftOverwrittenNotice(this.key);

  final DocKey key;

  @override
  String get message => 'Se descartó un cambio en ${key.labelEs} hecho mientras se aplicaba la propuesta de Claude.';
}

/// The server refused some pushed items; they stay only on this device.
class RejectedNotice extends SyncNotice {
  const RejectedNotice(this.items);

  final List<ItemRef> items;

  @override
  String get message =>
      items.length == 1 ? '1 elemento no se pudo sincronizar' : '${items.length} elementos no se pudieron sincronizar';
}

/// What one [SyncService.sync] / [SyncService.initialSync] call did.
class SyncReport {
  /// Docs whose local edit lost to another device.
  final List<DocKey> conflicts = [];

  /// Items the server refused.
  final List<ItemRef> rejected = [];

  /// Requests made.
  int requests = 0;

  List<SyncNotice> get notices => [
    for (final k in conflicts) DocConflictNotice(k),
    if (rejected.isNotEmpty) RejectedNotice(List.unmodifiable(rejected)),
  ];
}

/// Rows that exist only on this device after the first pull (asked about before uploading).
class LocalOnlyData {
  const LocalOnlyData({required this.workouts, required this.bodyWeights, required this.exWeights});

  final int workouts;
  final int bodyWeights;
  final int exWeights;

  bool get isEmpty => workouts == 0 && bodyWeights == 0 && exWeights == 0;
}

/// Asks the owner whether rows that exist only on this device should be uploaded
/// ("¿Subir los entrenos de este dispositivo?"). Returning false discards them locally.
typedef ConfirmUpload = Future<bool> Function(LocalOnlyData localOnly);

/// Progress of the first (pull-only) sync.
class SyncProgress {
  const SyncProgress({required this.pages, required this.items});

  /// Pages pulled so far.
  final int pages;

  /// Docs + rows received so far.
  final int items;
}

/// Retry delay after [failures] consecutive failed syncs: 2 s, 4 s, 8 s … capped at 5 min.
Duration syncBackoff(int failures) {
  final ms = 2000 * math.pow(2, math.max(0, failures - 1));
  return Duration(milliseconds: math.min(ms, 5 * 60 * 1000).toInt());
}

/// The client half of the sync protocol (contract §3.3).
///
/// Operates on [data] in place; calls [onChanged] after every applied response so the owner
/// can persist and notify. Calls are serialised: [sync] while a sync runs schedules one more
/// pass of the running call instead of starting a second request. API errors propagate
/// unchanged (dirty sets are kept); retries are the caller's job (see [syncBackoff]).
class SyncService {
  SyncService({required this.data, required this.api, this.clock = const Clock(), this.onChanged});

  final LocalData data;
  final SyncApi api;
  final Clock clock;
  final VoidCallback? onChanged;

  /// Per-request caps (contract §3.2).
  static const maxDocs = 10;
  static const maxWorkouts = 100;
  static const maxBodyWeights = 500;
  static const maxExWeights = 500;

  /// Push body budget, under the Worker's 1 MiB limit.
  static const maxBodyBytes = 900 * 1024;

  /// Safety stop for one sync call (a well-behaved server needs far fewer).
  static const maxRequests = 200;

  Future<SyncReport>? _running;
  bool _again = false;

  /// Docs marked dirty only because the server database changed; their conflicts are adopted
  /// silently (the owner did not edit them).
  final Set<DocKey> _silentConflicts = {};

  bool get isRunning => _running != null;

  /// Pushes every dirty item and pulls everything new, repeating while the server has more or
  /// dirty items remain.
  Future<SyncReport> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _start(_pushPull);
  }

  /// The first sync after login: pull everything from `since=0` without pushing, then decide
  /// about rows only this device has ([confirmUpload]; uploads when null), then a normal sync.
  Future<SyncReport> initialSync({ConfirmUpload? confirmUpload, void Function(SyncProgress)? onProgress}) async {
    while (_running != null) {
      try {
        await _running;
      } catch (_) {
        // The earlier call's failure belongs to its caller.
      }
    }
    return _start((report) => _initial(report, confirmUpload, onProgress));
  }

  Future<SyncReport> _start(Future<void> Function(SyncReport) first) {
    final report = SyncReport();
    final future = () async {
      try {
        await first(report);
        while (_again) {
          _again = false;
          await _pushPull(report);
        }
        return report;
      } finally {
        _again = false;
        _running = null;
      }
    }();
    _running = future;
    return future;
  }

  // ---------------------------------------------------------------------------------------
  // Normal sync.

  Future<void> _pushPull(SyncReport report) async {
    var stalls = 0;
    while (true) {
      if (report.requests >= maxRequests) {
        debugPrint('sync: stopped after ${report.requests} requests');
        return;
      }
      final batch = _PushBatch.collect(data);
      final dirtyBefore = data.dirtyCount;
      final since = data.lastSeq;
      final res = batch.isEmpty ? await api.pull(since) : await api.push(batch.body(since));
      final receivedAt = clock.nowMs();
      report.requests++;

      if (_isNewDatabase(res, since)) {
        _resetForNewDatabase(res);
        _changed();
        continue;
      }
      data.epoch = res.epoch;
      _applyResponse(res, batch, report);
      data.lastSeq = res.seq;
      _updateClockOffset(res.serverTime, receivedAt);
      _changed();

      if (res.hasMore) continue;
      if (!data.hasDirty || batch.isEmpty) return;
      // Pushing made no progress three times in a row (edited on every round, or a server
      // that does not echo pushed items): stop and let the next trigger retry.
      stalls = data.dirtyCount >= dirtyBefore ? stalls + 1 : 0;
      if (stalls >= 3) return;
    }
  }

  bool _isNewDatabase(SyncResponse res, int since) =>
      (data.epoch != null && res.epoch != data.epoch) || res.seq < since;

  /// Epoch changed or the counter went backwards: the database was restored or recreated.
  /// Everything local is pushed again (docs from `baseSeq: 0`) and pulled from 0.
  void _resetForNewDatabase(SyncResponse res) {
    debugPrint('sync: server database changed (epoch ${data.epoch} → ${res.epoch}); resending everything');
    final wasDirty = {...data.dirtyDocs};
    data.epoch = res.epoch;
    data.lastSeq = 0;
    data.markAllDirty();
    // Proposals live only on the server: the new database re-sends the ones it has, and stale
    // ones would otherwise sit "pending" here and answer 404 when acted on.
    data.proposals.clear();
    for (final k in DocKey.values) {
      // Untouched defaults have nothing to say to the new database.
      if (data.docs[k]!.updatedAt == 0) data.dirtyDocs.remove(k);
      if (!wasDirty.contains(k)) _silentConflicts.add(k);
    }
  }

  void _applyResponse(SyncResponse res, _PushBatch batch, SyncReport report) {
    final conflicts = {
      for (final c in res.conflicts)
        if (c.kind == ItemKind.doc) c.key,
    };
    final rejected = <ItemKind, Set<String>>{};
    for (final r in res.rejected) {
      final kind = r.kind;
      if (kind == null) continue;
      rejected.putIfAbsent(kind, () => {}).add(r.key);
      report.rejected.add(r);
      debugPrint('sync: server rejected $r');
    }
    _clearRejected(rejected, batch);

    for (final sd in res.docs) {
      final key = DocKey.fromWire(sd.key);
      if (key == null) continue;
      final local = data.docs[key]!;
      final sentAt = batch.sentDocs[key];
      if (sentAt == null) {
        // Never step back: a slow pull answered before a resolve/revert committed a newer version
        // must not roll the doc back to an older seq.
        if (!data.dirtyDocs.contains(key) && sd.seq >= local.baseSeq) _adoptDoc(key, sd);
        continue;
      }
      if (rejected[ItemKind.doc]?.contains(sd.key) ?? false) continue;
      final conflict = conflicts.contains(sd.key);
      if (local.updatedAt == sentAt) {
        _adoptDoc(key, sd);
        data.dirtyDocs.remove(key);
        if (conflict && !_silentConflicts.contains(key)) report.conflicts.add(key);
      } else if (!conflict) {
        // Edited again while the push was in flight: keep the newer local data (still dirty),
        // but it now derives from the version this device just wrote.
        local.baseSeq = sd.seq;
      }
      _silentConflicts.remove(key);
    }

    _applyRows<Workout, ServerWorkout>(
      rows: res.workouts,
      local: data.workouts,
      dirty: data.dirtyWorkouts,
      sent: batch.sentWorkouts,
      rejected: rejected[ItemKind.workout] ?? const {},
      keyOf: (r) => r.id,
      deletedOf: (r) => r.deleted || r.data == null,
      adopt: (r) => RowRecord(data: Workout.fromJson(r.data), updatedAt: r.updatedAt),
    );
    _applyRows<BodyWeight, ServerBodyWeight>(
      rows: res.bodyweight,
      local: data.bodyWeight,
      dirty: data.dirtyBodyWeight,
      sent: batch.sentBodyWeight,
      rejected: rejected[ItemKind.bodyweight] ?? const {},
      keyOf: (r) => r.d,
      deletedOf: (r) => r.deleted,
      adopt: (r) => RowRecord(
        data: BodyWeight(d: r.d, w: r.w!, t: r.t ?? r.updatedAt),
        updatedAt: r.updatedAt,
      ),
    );
    _applyRows<ExWeight, ServerExWeight>(
      rows: res.exWeights,
      local: data.exWeights,
      dirty: data.dirtyExWeights,
      sent: batch.sentExWeights,
      rejected: rejected[ItemKind.exWeight] ?? const {},
      keyOf: (r) => r.id,
      deletedOf: (r) => r.deleted,
      adopt: (r) => RowRecord(
        data: ExWeight(w: r.w!, d: r.d ?? ''),
        updatedAt: r.updatedAt,
      ),
    );

    for (final p in res.proposals) {
      data.proposals[p.id] = p;
    }
  }

  /// A refused item stops being dirty (unless edited again meanwhile) but keeps its local data:
  /// nothing the owner entered is thrown away silently.
  void _clearRejected(Map<ItemKind, Set<String>> rejected, _PushBatch batch) {
    for (final key in rejected[ItemKind.doc] ?? const <String>{}) {
      final k = DocKey.fromWire(key);
      if (k != null && batch.sentDocs[k] == data.docs[k]!.updatedAt) data.dirtyDocs.remove(k);
    }
    void clear<T extends JsonModel>(
      Set<String>? keys,
      Map<String, int> sent,
      Map<String, RowRecord<T>> rows,
      Set<String> dirty,
    ) {
      for (final key in keys ?? const <String>{}) {
        if (sent[key] != null && sent[key] == rows[key]?.updatedAt) dirty.remove(key);
      }
    }

    clear(rejected[ItemKind.workout], batch.sentWorkouts, data.workouts, data.dirtyWorkouts);
    clear(rejected[ItemKind.bodyweight], batch.sentBodyWeight, data.bodyWeight, data.dirtyBodyWeight);
    clear(rejected[ItemKind.exWeight], batch.sentExWeights, data.exWeights, data.dirtyExWeights);
  }

  void _applyRows<T extends JsonModel, R>({
    required List<R> rows,
    required Map<String, RowRecord<T>> local,
    required Set<String> dirty,
    required Map<String, int> sent,
    required Set<String> rejected,
    required String Function(R) keyOf,
    required bool Function(R) deletedOf,
    required RowRecord<T> Function(R) adopt,
  }) {
    for (final row in rows) {
      final key = keyOf(row);
      if (key.isEmpty) continue;
      final sentAt = sent[key];
      if (sentAt != null) {
        if (rejected.contains(key)) continue;
        // Changed again while in flight → keep the local copy (still dirty).
        if (local[key]?.updatedAt != sentAt) continue;
        dirty.remove(key);
      } else if (dirty.contains(key)) {
        continue;
      }
      if (deletedOf(row)) {
        local.remove(key);
      } else {
        local[key] = adopt(row);
      }
    }
  }

  void _adoptDoc(DocKey key, ServerDoc sd) {
    data.docs[key] = DocRecord(data: key.parse(sd.data), baseSeq: sd.seq, updatedAt: sd.updatedAt);
  }

  /// `clockOffset = serverTime − localTimeAtResponse`, exponentially smoothed.
  void _updateClockOffset(int serverTime, int receivedAt) {
    if (serverTime <= 0) return;
    final sample = serverTime - receivedAt;
    data.clockOffset = data.hasClockOffset ? (data.clockOffset * 0.7 + sample * 0.3).round() : sample;
    data.hasClockOffset = true;
  }

  void _changed() => onChanged?.call();

  // ---------------------------------------------------------------------------------------
  // First sync after login (pull-only).

  Future<void> _initial(
    SyncReport report,
    ConfirmUpload? confirmUpload,
    void Function(SyncProgress)? onProgress,
  ) async {
    final seenDocs = <DocKey>{};
    final seenWorkouts = <String>{}, seenBodyWeight = <String>{}, seenExWeights = <String>{};
    var serverHasRows = false;
    var since = 0, pages = 0, items = 0;
    var first = true;

    while (true) {
      final res = await api.pull(since);
      final receivedAt = clock.nowMs();
      report.requests++;
      if (first) {
        first = false;
        if (data.epoch != null && data.epoch != res.epoch) {
          // Unpushed doc edits were based on another database's versions.
          for (final k in data.dirtyDocs) {
            data.docs[k]!.baseSeq = 0;
          }
        }
      }
      data.epoch = res.epoch;

      for (final sd in res.docs) {
        final key = DocKey.fromWire(sd.key);
        if (key == null) continue;
        seenDocs.add(key);
        if (!data.dirtyDocs.contains(key) && sd.seq >= data.docs[key]!.baseSeq) _adoptDoc(key, sd);
      }
      _applyRows<Workout, ServerWorkout>(
        rows: res.workouts,
        local: data.workouts,
        dirty: data.dirtyWorkouts,
        sent: const {},
        rejected: const {},
        keyOf: (r) => r.id,
        deletedOf: (r) => r.deleted || r.data == null,
        adopt: (r) => RowRecord(data: Workout.fromJson(r.data), updatedAt: r.updatedAt),
      );
      _applyRows<BodyWeight, ServerBodyWeight>(
        rows: res.bodyweight,
        local: data.bodyWeight,
        dirty: data.dirtyBodyWeight,
        sent: const {},
        rejected: const {},
        keyOf: (r) => r.d,
        deletedOf: (r) => r.deleted,
        adopt: (r) => RowRecord(
          data: BodyWeight(d: r.d, w: r.w!, t: r.t ?? r.updatedAt),
          updatedAt: r.updatedAt,
        ),
      );
      _applyRows<ExWeight, ServerExWeight>(
        rows: res.exWeights,
        local: data.exWeights,
        dirty: data.dirtyExWeights,
        sent: const {},
        rejected: const {},
        keyOf: (r) => r.id,
        deletedOf: (r) => r.deleted,
        adopt: (r) => RowRecord(
          data: ExWeight(w: r.w!, d: r.d ?? ''),
          updatedAt: r.updatedAt,
        ),
      );
      seenWorkouts.addAll(res.workouts.map((r) => r.id));
      seenBodyWeight.addAll(res.bodyweight.map((r) => r.d));
      seenExWeights.addAll(res.exWeights.map((r) => r.id));
      serverHasRows = serverHasRows || res.workouts.any((r) => !r.deleted) || res.bodyweight.any((r) => !r.deleted);
      for (final p in res.proposals) {
        data.proposals[p.id] = p;
      }

      pages++;
      items += res.docs.length + res.workouts.length + res.bodyweight.length + res.exWeights.length;
      onProgress?.call(SyncProgress(pages: pages, items: items));
      since = res.seq;
      data.lastSeq = res.seq;
      _updateClockOffset(res.serverTime, receivedAt);
      _changed();
      if (!res.hasMore) break;
    }

    // Docs the server has never stored but this device edited: send them (nothing to overwrite).
    for (final k in DocKey.values) {
      final doc = data.docs[k]!;
      if (!seenDocs.contains(k) && doc.updatedAt > 0 && !data.dirtyDocs.contains(k)) {
        doc.baseSeq = 0;
        data.dirtyDocs.add(k);
      }
    }

    // Rows only this device has (e.g. after changing server): ask before uploading them.
    List<String> localOnly<T extends JsonModel>(Map<String, RowRecord<T>> rows, Set<String> dirty, Set<String> seen) =>
        [
          for (final e in rows.entries)
            if (!e.value.deleted && !dirty.contains(e.key) && !seen.contains(e.key)) e.key,
        ];
    final onlyWorkouts = localOnly(data.workouts, data.dirtyWorkouts, seenWorkouts);
    final onlyBodyWeight = localOnly(data.bodyWeight, data.dirtyBodyWeight, seenBodyWeight);
    final onlyExWeights = localOnly(data.exWeights, data.dirtyExWeights, seenExWeights);
    final summary = LocalOnlyData(
      workouts: onlyWorkouts.length,
      bodyWeights: onlyBodyWeight.length,
      exWeights: onlyExWeights.length,
    );
    if (!summary.isEmpty) {
      final upload = !serverHasRows || confirmUpload == null || await confirmUpload(summary);
      if (upload) {
        data.dirtyWorkouts.addAll(onlyWorkouts);
        data.dirtyBodyWeight.addAll(onlyBodyWeight);
        data.dirtyExWeights.addAll(onlyExWeights);
      } else {
        onlyWorkouts.forEach(data.workouts.remove);
        onlyBodyWeight.forEach(data.bodyWeight.remove);
        onlyExWeights.forEach(data.exWeights.remove);
      }
    }

    data.needsInitialSync = false;
    _changed();
    await _pushPull(report);
  }
}

/// The dirty items one request carries, and the `updatedAt` each was sent with.
class _PushBatch {
  _PushBatch();

  /// Collects dirty items, docs first, within the per-request caps and byte budget.
  factory _PushBatch.collect(LocalData data) {
    // Dirty ids without a record cannot be pushed; forget them.
    data.dirtyWorkouts.removeWhere((id) => !data.workouts.containsKey(id));
    data.dirtyBodyWeight.removeWhere((d) => !data.bodyWeight.containsKey(d));
    data.dirtyExWeights.removeWhere((id) => !data.exWeights.containsKey(id));

    final batch = _PushBatch();
    var bytes = 0;
    bool fits(JsonMap item) {
      final size = utf8.encode(jsonEncode(item)).length;
      if (!batch.isEmpty && bytes + size > SyncService.maxBodyBytes) return false;
      bytes += size;
      return true;
    }

    for (final key in DocKey.values) {
      if (!data.dirtyDocs.contains(key) || batch.docs.length >= SyncService.maxDocs) continue;
      final doc = data.docs[key]!;
      if (key == DocKey.athlete && (doc.data as AthleteProfile).savedAt == null) {
        // Never pushed until the owner (or Claude) explicitly saved it.
        data.dirtyDocs.remove(key);
        continue;
      }
      final item = {'key': key.wire, 'data': doc.data.toJson(), 'baseSeq': doc.baseSeq, 'updatedAt': doc.updatedAt};
      if (!fits(item)) return batch;
      batch.docs.add(item);
      batch.sentDocs[key] = doc.updatedAt;
    }

    final workoutIds = data.dirtyWorkouts.where(data.workouts.containsKey).toList()
      ..sort((a, b) => Workout.compare(data.workouts[a]!.data, data.workouts[b]!.data));
    for (final id in workoutIds.take(SyncService.maxWorkouts)) {
      final rec = data.workouts[id]!;
      final w = rec.data;
      final item = <String, dynamic>{
        'id': id,
        'd': w.d,
        'start': w.start,
        'routineId': w.routineId,
        'updatedAt': rec.updatedAt,
        'deleted': rec.deleted,
        if (!rec.deleted) 'data': w.toJson(),
      };
      if (!fits(item)) return batch;
      batch.workouts.add(item);
      batch.sentWorkouts[id] = rec.updatedAt;
    }

    for (final d in data.dirtyBodyWeight.where(data.bodyWeight.containsKey).take(SyncService.maxBodyWeights)) {
      final rec = data.bodyWeight[d]!;
      final item = rec.deleted
          ? <String, dynamic>{'d': d, 'deleted': true, 'updatedAt': rec.updatedAt}
          : <String, dynamic>{'d': d, 'w': rec.data.w, 't': rec.data.t, 'updatedAt': rec.updatedAt, 'deleted': false};
      if (!fits(item)) return batch;
      batch.bodyweight.add(item);
      batch.sentBodyWeight[d] = rec.updatedAt;
    }

    for (final id in data.dirtyExWeights.where(data.exWeights.containsKey).take(SyncService.maxExWeights)) {
      final rec = data.exWeights[id]!;
      final item = rec.deleted
          ? <String, dynamic>{'id': id, 'deleted': true, 'updatedAt': rec.updatedAt}
          : <String, dynamic>{'id': id, 'w': rec.data.w, 'd': rec.data.d, 'updatedAt': rec.updatedAt, 'deleted': false};
      if (!fits(item)) return batch;
      batch.exWeights.add(item);
      batch.sentExWeights[id] = rec.updatedAt;
    }
    return batch;
  }

  final List<JsonMap> docs = [];
  final List<JsonMap> workouts = [];
  final List<JsonMap> bodyweight = [];
  final List<JsonMap> exWeights = [];
  final Map<DocKey, int> sentDocs = {};
  final Map<String, int> sentWorkouts = {};
  final Map<String, int> sentBodyWeight = {};
  final Map<String, int> sentExWeights = {};

  bool get isEmpty => docs.isEmpty && workouts.isEmpty && bodyweight.isEmpty && exWeights.isEmpty;

  JsonMap body(int since) => {
    'since': since,
    if (docs.isNotEmpty) 'docs': docs,
    if (workouts.isNotEmpty) 'workouts': workouts,
    if (bodyweight.isNotEmpty) 'bodyweight': bodyweight,
    if (exWeights.isNotEmpty) 'exWeights': exWeights,
  };
}
