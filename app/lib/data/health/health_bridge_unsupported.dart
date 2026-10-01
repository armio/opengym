import 'health_bridge.dart';

/// Web: no health store.
HealthBridge createPlatformHealthBridge() => const UnsupportedHealthBridge();

/// A bridge for platforms without Apple Health; nothing is ever called on it.
class UnsupportedHealthBridge implements HealthBridge {
  const UnsupportedHealthBridge();

  static const _unavailable = HealthUnavailableException('Apple Health no está disponible en este dispositivo.');

  @override
  bool get isSupported => false;

  @override
  Future<void> requestAuthorization() => Future.error(_unavailable);

  @override
  Future<List<HealthReading>> readWeights(DateTime from, DateTime to) => Future.error(_unavailable);

  @override
  Future<String> writeWeight({required double kg, required DateTime at}) => Future.error(_unavailable);

  @override
  Future<String> writeStrengthWorkout({required DateTime start, required DateTime end, int? kcal, String? title}) =>
      Future.error(_unavailable);

  @override
  Future<void> deleteWeight(String uuid) => Future.error(_unavailable);

  @override
  Future<void> deleteWorkout(String uuid) => Future.error(_unavailable);

  @override
  Future<List<HealthReading>> readRestingHeartRate(DateTime from, DateTime to) => Future.error(_unavailable);

  @override
  Future<List<HealthReading>> readHeartRateVariability(DateTime from, DateTime to) => Future.error(_unavailable);

  @override
  Future<List<SleepSegment>> readSleep(DateTime from, DateTime to) => Future.error(_unavailable);
}
