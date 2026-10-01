import 'models/models.dart';
import 'sync_protocol.dart';

/// A synced document with its sync metadata.
class DocRecord {
  DocRecord({required this.data, this.baseSeq = 0, this.updatedAt = 0});

  /// The typed doc ([Settings], [PlanDoc], …).
  JsonModel data;

  /// The server `seq` of the version [data] derives from (0 = never synced).
  int baseSeq;

  /// Epoch ms of the last edit (0 for untouched defaults).
  int updatedAt;
}

/// A synced row (workout, weigh-in, working weight) with its last-writer-wins clock.
///
/// A local deletion keeps the row as a tombstone ([deleted]) until the push is acknowledged,
/// so the tombstone can carry `d`/`start`/`routineId`.
class RowRecord<T extends JsonModel> {
  RowRecord({required this.data, required this.updatedAt, this.deleted = false});

  T data;
  int updatedAt;
  bool deleted;
}

/// Everything persisted in `state.json`: docs with base seqs, rows, proposals, dirty sets and
/// the sync cursor (contract §3.3, §6). [SyncService] mutates it; AppState owns it.
class LocalData {
  LocalData()
    : docs = {for (final k in DocKey.values) k: DocRecord(data: k.defaults())},
      workouts = {},
      bodyWeight = {},
      exWeights = {},
      proposals = {},
      dirtyDocs = {},
      dirtyWorkouts = {},
      dirtyBodyWeight = {},
      dirtyExWeights = {};

  factory LocalData.fromJson(Object? json) {
    final m = asMap(json);
    final data = LocalData();
    final docs = asMap(m['docs']);
    for (final k in DocKey.values) {
      final d = asMapOrNull(docs[k.wire]);
      if (d == null) continue;
      data.docs[k] = DocRecord(
        data: k.parse(d['data']),
        baseSeq: asInt(d['baseSeq']) ?? 0,
        updatedAt: asInt(d['updatedAt']) ?? 0,
      );
    }
    _readRows(m['workouts'], data.workouts, Workout.fromJson);
    _readRows(m['bodyweight'], data.bodyWeight, BodyWeight.fromJson);
    _readRows(m['exWeights'], data.exWeights, ExWeight.fromJson);
    for (final p in asList(m['proposals'])) {
      if (p is! Map) continue;
      final proposal = Proposal.fromJson(p);
      data.proposals[proposal.id] = proposal;
    }
    final dirty = asMap(m['dirty']);
    data.dirtyDocs.addAll([for (final k in asStringList(dirty['docs'])) ?DocKey.fromWire(k)]);
    data.dirtyWorkouts.addAll(asStringList(dirty['workouts']).where(data.workouts.containsKey));
    data.dirtyBodyWeight.addAll(asStringList(dirty['bodyweight']).where(data.bodyWeight.containsKey));
    data.dirtyExWeights.addAll(asStringList(dirty['exWeights']).where(data.exWeights.containsKey));
    data.lastSeq = asInt(m['lastSeq']) ?? 0;
    data.epoch = asInt(m['epoch']);
    data.clockOffset = asInt(m['clockOffset']) ?? 0;
    data.hasClockOffset = asBool(m['hasClockOffset']) ?? false;
    data.needsInitialSync = asBool(m['needsInitialSync']) ?? false;
    return data;
  }

  static void _readRows<T extends JsonModel>(Object? json, Map<String, RowRecord<T>> into, T Function(Object?) parse) {
    for (final e in asMap(json).entries) {
      final r = asMapOrNull(e.value);
      if (r == null) continue;
      into[e.key] = RowRecord(
        data: parse(r['data']),
        updatedAt: asInt(r['updatedAt']) ?? 0,
        deleted: asBool(r['deleted']) ?? false,
      );
    }
  }

  static const formatVersion = 1;

  final Map<DocKey, DocRecord> docs;

  /// By workout id.
  final Map<String, RowRecord<Workout>> workouts;

  /// By `'YYYY-MM-DD'`.
  final Map<String, RowRecord<BodyWeight>> bodyWeight;

  /// By exercise id.
  final Map<String, RowRecord<ExWeight>> exWeights;

  /// By proposal id (server-owned, replaced on every sync).
  final Map<String, Proposal> proposals;

  final Set<DocKey> dirtyDocs;
  final Set<String> dirtyWorkouts;
  final Set<String> dirtyBodyWeight;
  final Set<String> dirtyExWeights;

  /// Highest server `seq` this device has fully pulled.
  int lastSeq = 0;

  /// Server database epoch seen last; a change means the database was restored or recreated.
  int? epoch;

  /// Smoothed `serverTime − localTime` in ms, added to `now` when stamping `updatedAt`.
  int clockOffset = 0;
  bool hasClockOffset = false;

  /// Set at login; the next sync is the pull-only first sync (contract §3.3.3).
  bool needsInitialSync = false;

  T doc<T extends JsonModel>(DocKey key) => docs[key]!.data as T;

  bool get hasDirty =>
      dirtyDocs.isNotEmpty || dirtyWorkouts.isNotEmpty || dirtyBodyWeight.isNotEmpty || dirtyExWeights.isNotEmpty;

  int get dirtyCount => dirtyDocs.length + dirtyWorkouts.length + dirtyBodyWeight.length + dirtyExWeights.length;

  /// After an epoch change: everything local is pushed again, docs from `baseSeq: 0`.
  void markAllDirty() {
    for (final k in DocKey.values) {
      docs[k]!.baseSeq = 0;
      dirtyDocs.add(k);
    }
    dirtyWorkouts.addAll(workouts.keys);
    dirtyBodyWeight.addAll(bodyWeight.keys);
    dirtyExWeights.addAll(exWeights.keys);
  }

  JsonMap toJson() => {
    'version': formatVersion,
    'docs': {
      for (final e in docs.entries)
        e.key.wire: {'data': e.value.data.toJson(), 'baseSeq': e.value.baseSeq, 'updatedAt': e.value.updatedAt},
    },
    'workouts': _rowsJson(workouts),
    'bodyweight': _rowsJson(bodyWeight),
    'exWeights': _rowsJson(exWeights),
    'proposals': [for (final p in proposals.values) p.toJson()],
    'dirty': {
      'docs': [for (final k in dirtyDocs) k.wire],
      'workouts': [...dirtyWorkouts],
      'bodyweight': [...dirtyBodyWeight],
      'exWeights': [...dirtyExWeights],
    },
    'lastSeq': lastSeq,
    'epoch': epoch,
    'clockOffset': clockOffset,
    'hasClockOffset': hasClockOffset,
    'needsInitialSync': needsInitialSync,
  };

  static JsonMap _rowsJson<T extends JsonModel>(Map<String, RowRecord<T>> rows) => {
    for (final e in rows.entries)
      e.key: {'data': e.value.data.toJson(), 'updatedAt': e.value.updatedAt, if (e.value.deleted) 'deleted': true},
  };
}
