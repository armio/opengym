import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'health_bridge.dart';

/// iPhone: HealthKit through the `health` plugin. Other native platforms get a bridge whose
/// [HealthBridge.isSupported] is false (Health Connect on Android is not wired up).
HealthBridge createPlatformHealthBridge() => PluginHealthBridge();

class PluginHealthBridge implements HealthBridge {
  PluginHealthBridge();

  late final Health _health = Health();
  Future<void>? _configured;

  static const _sleepStages = {
    HealthDataType.SLEEP_IN_BED: SleepStage.inBed,
    HealthDataType.SLEEP_ASLEEP: SleepStage.asleep,
    HealthDataType.SLEEP_LIGHT: SleepStage.asleep, // "Core" in Apple Health
    HealthDataType.SLEEP_DEEP: SleepStage.asleep,
    HealthDataType.SLEEP_REM: SleepStage.asleep,
    HealthDataType.SLEEP_AWAKE: SleepStage.awake,
  };

  /// Everything the app asks for, and how.
  static final Map<HealthDataType, HealthDataAccess> _access = {
    HealthDataType.WEIGHT: HealthDataAccess.READ_WRITE,
    HealthDataType.WORKOUT: HealthDataAccess.WRITE,
    HealthDataType.RESTING_HEART_RATE: HealthDataAccess.READ,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN: HealthDataAccess.READ,
    for (final type in _sleepStages.keys) type: HealthDataAccess.READ,
  };

  @override
  bool get isSupported => !kIsWeb && Platform.isIOS;

  Future<T> _call<T>(Future<T> Function() fn) async {
    if (!isSupported) throw const HealthUnavailableException('Apple Health no está disponible en este dispositivo.');
    try {
      await (_configured ??= _health.configure());
      return await fn();
    } on HealthUnavailableException {
      rethrow;
    } catch (e) {
      debugPrint('health: $e');
      throw const HealthUnavailableException('No se pudo acceder a Apple Health.');
    }
  }

  @override
  Future<void> requestAuthorization() => _call(() async {
    await _health.requestAuthorization(_access.keys.toList(), permissions: _access.values.toList());
  });

  Future<List<HealthReading>> _numeric(HealthDataType type, DateTime from, DateTime to) => _call(() async {
    final points = await _health.getHealthDataFromTypes(types: [type], startTime: from, endTime: to);
    return [
      for (final p in points)
        if (p.value case NumericHealthValue(:final numericValue))
          HealthReading(uuid: p.uuid, start: p.dateFrom, end: p.dateTo, value: numericValue.toDouble()),
    ];
  });

  @override
  Future<List<HealthReading>> readWeights(DateTime from, DateTime to) => _numeric(HealthDataType.WEIGHT, from, to);

  @override
  Future<List<HealthReading>> readRestingHeartRate(DateTime from, DateTime to) =>
      _numeric(HealthDataType.RESTING_HEART_RATE, from, to);

  @override
  Future<List<HealthReading>> readHeartRateVariability(DateTime from, DateTime to) =>
      _numeric(HealthDataType.HEART_RATE_VARIABILITY_SDNN, from, to);

  @override
  Future<List<SleepSegment>> readSleep(DateTime from, DateTime to) => _call(() async {
    final points = await _health.getHealthDataFromTypes(
      types: _sleepStages.keys.toList(),
      startTime: from,
      endTime: to,
    );
    return [
      for (final p in points)
        if (_sleepStages[p.type] case final stage?) SleepSegment(start: p.dateFrom, end: p.dateTo, stage: stage),
    ];
  });

  /// The uuid of a saved sample; HealthKit answers "" when it refused the save.
  static String _saved(String? uuid, String what) {
    if (uuid == null || uuid.isEmpty) {
      throw HealthUnavailableException('Apple Health no aceptó $what. Revisa los permisos de openGym en Salud.');
    }
    return uuid;
  }

  @override
  Future<String> writeWeight({required double kg, required DateTime at}) => _call(() async {
    final uuid = await _health.writeHealthDataUUID(
      value: kg,
      unit: HealthDataUnit.KILOGRAM,
      type: HealthDataType.WEIGHT,
      startTime: at,
      endTime: at,
      recordingMethod: RecordingMethod.manual,
    );
    return _saved(uuid, 'el pesaje');
  });

  @override
  Future<String> writeStrengthWorkout({required DateTime start, required DateTime end, int? kcal, String? title}) =>
      _call(() async {
        final uuid = await _health.writeWorkoutDataUUID(
          activityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
          start: start,
          end: end,
          totalEnergyBurned: kcal,
          title: title,
          recordingMethod: RecordingMethod.manual,
        );
        return _saved(uuid, 'el entreno');
      });

  @override
  Future<void> deleteWeight(String uuid) => _call(() => _health.deleteByUUID(uuid: uuid, type: HealthDataType.WEIGHT));

  @override
  Future<void> deleteWorkout(String uuid) =>
      _call(() => _health.deleteByUUID(uuid: uuid, type: HealthDataType.WORKOUT));
}
