import 'json.dart';
import 'plan.dart';

/// The owner's decision on a proposal (`resolution` of a ProposalDTO, contract §4.5).
class ProposalResolution implements JsonModel {
  ProposalResolution({
    required this.outcome,
    List<String>? accepted,
    List<String>? rejected,
    List<String>? stale,
    this.schedule,
    JsonMap? extra,
  }) : accepted = accepted ?? [],
       rejected = rejected ?? [],
       stale = stale ?? [],
       extra = extra ?? {};

  factory ProposalResolution.fromJson(Object? json) {
    final m = asMap(json);
    return ProposalResolution(
      outcome: asString(m['outcome']) ?? '',
      accepted: asStringList(m['accepted']),
      rejected: asStringList(m['rejected']),
      stale: asStringList(m['stale']),
      schedule: asBool(m['schedule']),
      extra: extraOf(m, const {'outcome', 'accepted', 'rejected', 'stale', 'schedule'}),
    );
  }

  /// `'applied'` or `'dismissed'`.
  String outcome;
  List<String> accepted;
  List<String> rejected;
  List<String> stale;

  /// Plan proposals: whether the weekly schedule was replaced.
  bool? schedule;
  JsonMap extra;

  @override
  JsonMap toJson() {
    final out = <String, dynamic>{
      ...deepCopyMap(extra),
      'outcome': outcome,
      'accepted': [...accepted],
      'rejected': [...rejected],
      'stale': [...stale],
    };
    putIfNotNull(out, 'schedule', schedule);
    return out;
  }
}

/// Where a change applies: `{routineId?, exId?, weekday?}`.
class ChangeTarget {
  const ChangeTarget({this.routineId, this.exId, this.weekday});

  factory ChangeTarget.fromJson(Object? json) {
    final m = asMap(json);
    return ChangeTarget(routineId: asString(m['routineId']), exId: asString(m['exId']), weekday: asInt(m['weekday']));
  }

  final String? routineId;
  final String? exId;
  final int? weekday;
}

/// A typed read-only view of one change of a `changes` proposal (specs/coach.md §4.4 normalised
/// form). [raw] is the underlying JSON (a copy), handy for the map-based apply functions.
class ProposalChange {
  ProposalChange(this.raw);

  final JsonMap raw;

  String get id => asString(raw['id']) ?? '';

  /// One of the 17 change types (`add-exercise`, `sets`, `week`, …).
  String get type => asString(raw['type']) ?? '';
  ChangeTarget get target => ChangeTarget.fromJson(raw['target']);

  /// The value when Claude proposed it (server-computed), or null.
  dynamic get before => raw['before'];
  dynamic get after => raw['after'];
  String get why => asString(raw['why']) ?? '';

  /// Client-side status (`'proposed' | 'stale'`) when present.
  String? get status => asString(raw['status']);
}

/// A typed read-only view of a `plan` proposal's bundle (specs/coach.md §4.2 + contract §5.3).
/// Routine and exercise `why` texts stay in each model's `extra` (see [routineWhy], [exerciseWhy]).
class PlanBundle {
  PlanBundle(this.raw);

  final JsonMap raw;

  String get name => asString(raw['name']) ?? '';
  String get summary => asString(raw['summary']) ?? '';
  String get basedOn => asString(raw['basedOn']) ?? '';

  /// Weekday (`'0'`–`'6'`) → routine id within this bundle.
  Map<String, String> get week => asStringMap(raw['week']);
  List<Routine> get routines => [
    for (final r in asList(raw['routines']))
      if (r is Map) Routine.fromJson(r),
  ];

  /// Custom exercises the plan introduces, as sent (`{id, n, bp, desc?}`).
  List<JsonMap> get customEx => [
    for (final c in asList(raw['customEx']))
      if (c is Map) deepCopyMap(c),
  ];

  static String routineWhy(Routine r) => asString(r.extra['why']) ?? '';
  static String exerciseWhy(RoutineExercise e) => asString(e.extra['why']) ?? '';
}

/// A proposal from Claude (ProposalDTO, contract §4.5). Server-owned: the app only reads it and
/// resolves or reverts it through the API. Kind-specific bodies are kept as raw JSON with typed
/// accessors on top.
class Proposal implements JsonModel {
  Proposal({
    required this.id,
    required this.kind,
    required this.status,
    this.createdAt = 0,
    this.expiresAt = 0,
    this.planHash,
    this.unit = 'kg',
    this.iteration = 1,
    this.summary = '',
    this.resolution,
    this.resolvedAt,
    this.revertedAt,
    this.seq = 0,
    JsonMap? extra,
  }) : extra = extra ?? {};

  factory Proposal.fromJson(Object? json) {
    final m = asMap(json);
    return Proposal(
      id: asString(m['id']) ?? '',
      kind: asString(m['kind']) ?? '',
      status: asString(m['status']) ?? '',
      createdAt: asInt(m['createdAt']) ?? 0,
      expiresAt: asInt(m['expiresAt']) ?? 0,
      planHash: asString(m['planHash']),
      unit: asString(m['unit']) ?? 'kg',
      iteration: asInt(m['iteration']) ?? 1,
      summary: asString(m['summary']) ?? '',
      resolution: m['resolution'] is Map ? ProposalResolution.fromJson(m['resolution']) : null,
      resolvedAt: asInt(m['resolvedAt']),
      revertedAt: asInt(m['revertedAt']),
      seq: asInt(m['seq']) ?? 0,
      extra: extraOf(m, _known),
    );
  }

  static const _known = {
    'id', 'kind', 'status', 'createdAt', 'expiresAt', 'planHash', 'unit', 'iteration', 'summary', //
    'resolution', 'resolvedAt', 'revertedAt', 'seq',
  };

  static const kindPlan = 'plan';
  static const kindChanges = 'changes';
  static const kindNoChange = 'nochange';

  String id;

  /// [kindPlan], [kindChanges] or [kindNoChange].
  String kind;

  /// `'pending'|'applied'|'dismissed'|'superseded'|'expired'`.
  String status;
  int createdAt;
  int expiresAt;
  String? planHash;

  /// `settings.unit` when the proposal was created; the app refuses to accept a mismatch.
  String unit;
  int iteration;
  String summary;
  ProposalResolution? resolution;
  int? resolvedAt;
  int? revertedAt;
  int seq;

  /// Kind-specific body (`bundle`, `evidence`, `changes`, `notes`, `reading`) and unknown keys.
  JsonMap extra;

  bool get isPending => status == 'pending';
  bool get isApplied => status == 'applied';
  bool get isReverted => revertedAt != null;

  /// `plan` proposals: the validated bundle as raw JSON, or null.
  JsonMap? get bundleJson => asMapOrNull(extra['bundle']);

  /// `plan` proposals: a typed view of the bundle, or null.
  PlanBundle? get bundle => bundleJson == null ? null : PlanBundle(bundleJson!);

  /// `changes` proposals: `{from, to, sessions}` or null.
  JsonMap? get evidence => asMapOrNull(extra['evidence']);

  /// `changes` proposals: the changes as raw JSON maps (copies), in proposal order.
  List<JsonMap> get changesJson => [
    for (final c in asList(extra['changes']))
      if (c is Map) deepCopyMap(c),
  ];

  /// `changes` proposals: typed views of [changesJson].
  List<ProposalChange> get changes => [for (final c in changesJson) ProposalChange(c)];

  /// `changes` proposals: advice with no plan change attached.
  List<String> get notes => asStringList(extra['notes']);

  /// `nochange` proposals: Claude's reading of the training.
  String get reading => asString(extra['reading']) ?? '';

  Proposal copy() => Proposal.fromJson(toJson());

  @override
  JsonMap toJson() => {
    ...deepCopyMap(extra),
    'id': id,
    'kind': kind,
    'status': status,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'planHash': planHash,
    'unit': unit,
    'iteration': iteration,
    'summary': summary,
    'resolution': resolution?.toJson(),
    'resolvedAt': resolvedAt,
    'revertedAt': revertedAt,
    'seq': seq,
  };
}
