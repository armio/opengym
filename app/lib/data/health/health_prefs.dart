import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/json.dart';

/// A workout this device saved in Apple Health.
class ExportedWorkout {
  const ExportedWorkout({required this.uuid, required this.start, required this.end});

  factory ExportedWorkout.fromJson(Object? json) {
    final m = asMap(json);
    return ExportedWorkout(uuid: asString(m['uuid']) ?? '', start: asInt(m['start']) ?? 0, end: asInt(m['end']) ?? 0);
  }

  final String uuid;
  final int start;
  final int end;

  JsonMap toJson() => {'uuid': uuid, 'start': start, 'end': end};
}

/// A weigh-in this device saved in Apple Health (`w` in the owner's unit, as in openGym).
class ExportedWeight {
  const ExportedWeight({required this.uuid, required this.w, required this.t});

  factory ExportedWeight.fromJson(Object? json) {
    final m = asMap(json);
    return ExportedWeight(uuid: asString(m['uuid']) ?? '', w: asNum(m['w']) ?? 0, t: asInt(m['t']) ?? 0);
  }

  final String uuid;
  final num w;
  final int t;

  JsonMap toJson() => {'uuid': uuid, 'w': w, 't': t};
}

/// Apple Health settings and bookkeeping of this device (contract §8). Device-only, never synced:
/// Apple Health is per phone.
class HealthPrefs {
  HealthPrefs({
    this.connected = false,
    this.writeWorkouts = true,
    this.syncWeight = true,
    this.shareRecovery = true,
    this.connectedAt,
    this.lastSyncAt,
    this.lastWeightImportAt,
    this.lastRecoveryUploadAt,
    this.lastError,
    Map<String, ExportedWorkout>? workouts,
    Map<String, ExportedWeight>? weights,
    Map<String, int>? importedWeights,
  }) : workouts = workouts ?? {},
       weights = weights ?? {},
       importedWeights = importedWeights ?? {};

  factory HealthPrefs.fromJson(Object? json) {
    final m = asMap(json);
    return HealthPrefs(
      connected: asBool(m['connected']) ?? false,
      writeWorkouts: asBool(m['writeWorkouts']) ?? true,
      syncWeight: asBool(m['syncWeight']) ?? true,
      shareRecovery: asBool(m['shareRecovery']) ?? true,
      connectedAt: asInt(m['connectedAt']),
      lastSyncAt: asInt(m['lastSyncAt']),
      lastWeightImportAt: asInt(m['lastWeightImportAt']),
      lastRecoveryUploadAt: asInt(m['lastRecoveryUploadAt']),
      lastError: asString(m['lastError']),
      workouts: {for (final e in asMap(m['workouts']).entries) e.key: ExportedWorkout.fromJson(e.value)},
      weights: {for (final e in asMap(m['weights']).entries) e.key: ExportedWeight.fromJson(e.value)},
      importedWeights: {for (final e in asMap(m['importedWeights']).entries) e.key: ?asInt(e.value)},
    );
  }

  /// The owner connected Apple Health (and has not disconnected it).
  bool connected;

  /// Save finished workouts in Apple Health.
  bool writeWorkouts;

  /// Body weight both ways: smart-scale readings into openGym, openGym weigh-ins into Health.
  bool syncWeight;

  /// Upload resting heart rate, HRV and sleep to the server for Claude.
  bool shareRecovery;

  /// When Apple Health was first connected (epoch ms); exports start a little before it.
  int? connectedAt;
  int? lastSyncAt;
  int? lastWeightImportAt;
  int? lastRecoveryUploadAt;

  /// Spanish message of the last failed step, cleared by a clean run.
  String? lastError;

  /// openGym workout id → the copy saved in Apple Health.
  final Map<String, ExportedWorkout> workouts;

  /// Date → the openGym weigh-in saved in Apple Health.
  final Map<String, ExportedWeight> weights;

  /// Date → time (`t`) of the Apple Health reading imported as that day's weigh-in, so it is not
  /// written back.
  final Map<String, int> importedWeights;

  JsonMap toJson() => {
    'connected': connected,
    'writeWorkouts': writeWorkouts,
    'syncWeight': syncWeight,
    'shareRecovery': shareRecovery,
    'connectedAt': connectedAt,
    'lastSyncAt': lastSyncAt,
    'lastWeightImportAt': lastWeightImportAt,
    'lastRecoveryUploadAt': lastRecoveryUploadAt,
    'lastError': lastError,
    'workouts': {for (final e in workouts.entries) e.key: e.value.toJson()},
    'weights': {for (final e in weights.entries) e.key: e.value.toJson()},
    'importedWeights': {...importedWeights},
  };
}

/// Where [HealthPrefs] live.
abstract interface class HealthPrefsStore {
  Future<HealthPrefs> load();
  Future<void> save(HealthPrefs prefs);
}

/// `shared_preferences`, one JSON value.
class SharedPrefsHealthStore implements HealthPrefsStore {
  const SharedPrefsHealthStore();

  static const _key = 'opengym.health.v1';

  @override
  Future<HealthPrefs> load() async {
    final text = (await SharedPreferences.getInstance()).getString(_key);
    if (text == null) return HealthPrefs();
    try {
      return HealthPrefs.fromJson(jsonDecode(text));
    } on FormatException {
      return HealthPrefs();
    }
  }

  @override
  Future<void> save(HealthPrefs prefs) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(prefs.toJson()));
}

/// In memory, for tests.
class MemoryHealthPrefsStore implements HealthPrefsStore {
  MemoryHealthPrefsStore([this.saved]);

  JsonMap? saved;

  @override
  Future<HealthPrefs> load() async => HealthPrefs.fromJson(saved ?? const {});

  @override
  Future<void> save(HealthPrefs prefs) async => saved = jsonDecode(jsonEncode(prefs.toJson())) as JsonMap;
}
