import 'health_bridge_plugin.dart' if (dart.library.js_interop) 'health_bridge_unsupported.dart' as platform;

/// One numeric reading (resting heart rate in bpm, HRV in ms, body weight in kg).
class HealthReading {
  const HealthReading({required this.uuid, required this.start, required this.end, required this.value});

  final String uuid;
  final DateTime start;
  final DateTime end;
  final double value;
}

/// Apple Health's sleep stages, as far as recovery needs them.
enum SleepStage { inBed, asleep, awake }

/// One sleep-analysis sample.
class SleepSegment {
  const SleepSegment({required this.start, required this.end, required this.stage});

  final DateTime start;
  final DateTime end;
  final SleepStage stage;
}

/// The device's health store (Apple Health through HealthKit), behind an interface so the sync
/// logic can be tested with a fake. Every method may throw a [HealthUnavailableException].
abstract interface class HealthBridge {
  /// HealthKit on iPhone; a bridge whose [isSupported] is false elsewhere.
  factory HealthBridge.platform() => platform.createPlatformHealthBridge();

  /// True on devices with Apple Health (iPhone). Every other call is pointless when false.
  bool get isSupported;

  /// Shows the system permission sheet for everything the app reads and writes. iOS never says
  /// whether reading was allowed: denied types simply read as empty.
  Future<void> requestAuthorization();

  /// Body-weight readings (kg) whose time falls in `[from, to]`.
  Future<List<HealthReading>> readWeights(DateTime from, DateTime to);

  /// Saves a body-weight reading and returns its uuid. Throws when the store refuses it (writing
  /// was not allowed).
  Future<String> writeWeight({required double kg, required DateTime at});

  /// Saves a strength-training workout and returns its uuid. Throws when the store refuses it.
  Future<String> writeStrengthWorkout({required DateTime start, required DateTime end, int? kcal, String? title});

  /// Deletes a body-weight reading or a workout this app saved, by uuid.
  Future<void> deleteWeight(String uuid);
  Future<void> deleteWorkout(String uuid);

  Future<List<HealthReading>> readRestingHeartRate(DateTime from, DateTime to);
  Future<List<HealthReading>> readHeartRateVariability(DateTime from, DateTime to);
  Future<List<SleepSegment>> readSleep(DateTime from, DateTime to);
}

/// The health store refused or failed a call. [message] is Spanish and user-presentable.
class HealthUnavailableException implements Exception {
  const HealthUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'HealthUnavailableException: $message';
}
