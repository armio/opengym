import 'models/models.dart';

/// The five synced documents (contract §2).
enum DocKey {
  settings('settings', 'los ajustes'),
  plan('plan', 'el plan'),
  schedule('schedule', 'el calendario'),
  athlete('athlete', 'tu perfil de atleta'),
  coach('coach', 'el historial del Coach');

  const DocKey(this.wire, this.labelEs);

  /// The key on the wire and in D1.
  final String wire;

  /// Spanish name used in messages ("… el plan cambió en otro dispositivo.").
  final String labelEs;

  static DocKey? fromWire(String? key) {
    for (final k in values) {
      if (k.wire == key) return k;
    }
    return null;
  }

  /// Parses this doc's data into its model.
  JsonModel parse(Object? json) => switch (this) {
    DocKey.settings => Settings.fromJson(json),
    DocKey.plan => PlanDoc.fromJson(json),
    DocKey.schedule => ScheduleDoc.fromJson(json),
    DocKey.athlete => AthleteProfile.fromJson(json),
    DocKey.coach => CoachDoc.fromJson(json),
  };

  /// The default doc (contract §2.1).
  JsonModel defaults() => switch (this) {
    DocKey.settings => Settings(),
    DocKey.plan => PlanDoc(),
    DocKey.schedule => ScheduleDoc(),
    DocKey.athlete => AthleteProfile(),
    DocKey.coach => CoachDoc(),
  };
}

/// Kinds of synced items, as reported in `conflicts` / `rejected`.
enum ItemKind {
  doc,
  workout,
  bodyweight,
  exWeight;

  static ItemKind? fromWire(String? kind) => switch (kind) {
    'doc' || 'docs' => ItemKind.doc,
    'workout' || 'workouts' => ItemKind.workout,
    'bodyweight' || 'bodyWeight' || 'body_weight' => ItemKind.bodyweight,
    'exWeight' || 'exWeights' || 'ex_weight' || 'ex_weights' => ItemKind.exWeight,
    _ => null,
  };
}

/// A doc as the server returns it.
class ServerDoc {
  ServerDoc({required this.key, required this.data, required this.updatedAt, required this.seq});

  factory ServerDoc.fromJson(Object? json) {
    final m = asMap(json);
    return ServerDoc(
      key: asString(m['key']) ?? '',
      data: asMap(m['data']),
      updatedAt: asInt(m['updatedAt']) ?? 0,
      seq: asInt(m['seq']) ?? 0,
    );
  }

  final String key;
  final JsonMap data;
  final int updatedAt;
  final int seq;
}

/// A workout row as the server returns it; [data] is null for a tombstone.
class ServerWorkout {
  ServerWorkout({
    required this.id,
    required this.data,
    required this.deleted,
    required this.updatedAt,
    required this.seq,
  });

  factory ServerWorkout.fromJson(Object? json) {
    final m = asMap(json);
    final deleted = asBool(m['deleted']) ?? false;
    return ServerWorkout(
      id: asString(m['id']) ?? '',
      data: deleted ? null : asMapOrNull(m['data']),
      deleted: deleted || m['data'] == null,
      updatedAt: asInt(m['updatedAt']) ?? 0,
      seq: asInt(m['seq']) ?? 0,
    );
  }

  final String id;
  final JsonMap? data;
  final bool deleted;
  final int updatedAt;
  final int seq;
}

/// A body-weight row as the server returns it.
class ServerBodyWeight {
  ServerBodyWeight({
    required this.d,
    this.w,
    this.t,
    required this.deleted,
    required this.updatedAt,
    required this.seq,
  });

  factory ServerBodyWeight.fromJson(Object? json) {
    final m = asMap(json);
    final w = asNum(m['w']);
    return ServerBodyWeight(
      d: asString(m['d']) ?? '',
      w: w,
      t: asInt(m['t']),
      deleted: (asBool(m['deleted']) ?? false) || w == null,
      updatedAt: asInt(m['updatedAt']) ?? 0,
      seq: asInt(m['seq']) ?? 0,
    );
  }

  final String d;
  final num? w;
  final int? t;
  final bool deleted;
  final int updatedAt;
  final int seq;
}

/// A working-weight row as the server returns it.
class ServerExWeight {
  ServerExWeight({required this.id, this.w, this.d, required this.deleted, required this.updatedAt, required this.seq});

  factory ServerExWeight.fromJson(Object? json) {
    final m = asMap(json);
    final w = asNum(m['w']);
    return ServerExWeight(
      id: asString(m['id']) ?? '',
      w: w,
      d: asString(m['d']),
      deleted: (asBool(m['deleted']) ?? false) || w == null,
      updatedAt: asInt(m['updatedAt']) ?? 0,
      seq: asInt(m['seq']) ?? 0,
    );
  }

  final String id;
  final num? w;
  final String? d;
  final bool deleted;
  final int updatedAt;
  final int seq;
}

/// An item the server refused (`rejected[]`) or a doc whose compare-and-swap lost (`conflicts[]`).
class ItemRef {
  const ItemRef(this.kind, this.key, [this.error]);

  factory ItemRef.fromJson(Object? json) {
    final m = asMap(json);
    return ItemRef(ItemKind.fromWire(asString(m['kind'])), asString(m['key']) ?? '', asString(m['error']));
  }

  /// Null when the server sent a kind this client does not know.
  final ItemKind? kind;
  final String key;
  final String? error;

  @override
  String toString() => '${kind?.name}:$key${error == null ? '' : ' ($error)'}';
}

/// Response of `GET /api/sync` and `POST /api/sync` (contract §3.2).
class SyncResponse {
  SyncResponse({
    required this.seq,
    required this.epoch,
    required this.serverTime,
    this.hasMore = false,
    this.docs = const [],
    this.workouts = const [],
    this.bodyweight = const [],
    this.exWeights = const [],
    this.proposals = const [],
    this.conflicts = const [],
    this.rejected = const [],
  });

  factory SyncResponse.fromJson(Object? json) {
    final m = asMap(json);
    return SyncResponse(
      seq: asInt(m['seq']) ?? 0,
      epoch: asInt(m['epoch']) ?? 0,
      serverTime: asInt(m['serverTime']) ?? 0,
      hasMore: asBool(m['hasMore']) ?? false,
      docs: [for (final d in asList(m['docs'])) ServerDoc.fromJson(d)],
      workouts: [for (final w in asList(m['workouts'])) ServerWorkout.fromJson(w)],
      bodyweight: [for (final b in asList(m['bodyweight'])) ServerBodyWeight.fromJson(b)],
      exWeights: [for (final x in asList(m['exWeights'])) ServerExWeight.fromJson(x)],
      proposals: [
        for (final p in asList(m['proposals']))
          if (p is Map) Proposal.fromJson(p),
      ],
      conflicts: [for (final c in asList(m['conflicts'])) ItemRef.fromJson(c)],
      rejected: [for (final r in asList(m['rejected'])) ItemRef.fromJson(r)],
    );
  }

  final int seq;
  final int epoch;
  final int serverTime;
  final bool hasMore;
  final List<ServerDoc> docs;
  final List<ServerWorkout> workouts;
  final List<ServerBodyWeight> bodyweight;
  final List<ServerExWeight> exWeights;
  final List<Proposal> proposals;
  final List<ItemRef> conflicts;
  final List<ItemRef> rejected;
}

/// The two sync calls, abstracted so the protocol can be tested without HTTP.
abstract interface class SyncApi {
  /// `GET /api/sync?since=` — read-only.
  Future<SyncResponse> pull(int since);

  /// `POST /api/sync` with [body] (`since` + item arrays).
  Future<SyncResponse> push(JsonMap body);
}
