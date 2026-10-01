import 'package:opengym/data/health/health_bridge.dart';

/// Apple Health in memory. Writes get uuids `w1`, `k2`… and land in the same store reads use.
class FakeHealthBridge implements HealthBridge {
  bool supported = true;
  int authorizations = 0;
  final List<HealthReading> weights = [];
  final Map<String, ({DateTime start, DateTime end, int? kcal, String? title})> workouts = {};
  List<HealthReading> restingHeartRate = [];
  List<HealthReading> heartRateVariability = [];
  List<SleepSegment> sleep = [];
  final List<String> calls = [];

  /// Thrown by every read and write while set.
  HealthUnavailableException? failure;
  int _next = 0;

  void _check(String call) {
    calls.add(call);
    if (failure != null) throw failure!;
  }

  @override
  bool get isSupported => supported;

  @override
  Future<void> requestAuthorization() async {
    _check('authorize');
    authorizations++;
  }

  @override
  Future<List<HealthReading>> readWeights(DateTime from, DateTime to) async {
    _check('readWeights');
    return [
      for (final w in weights)
        if (!w.start.isBefore(from) && !w.start.isAfter(to)) w,
    ];
  }

  @override
  Future<String> writeWeight({required double kg, required DateTime at}) async {
    _check('writeWeight');
    final uuid = 'w${++_next}';
    weights.add(HealthReading(uuid: uuid, start: at, end: at, value: kg));
    return uuid;
  }

  @override
  Future<String> writeStrengthWorkout({
    required DateTime start,
    required DateTime end,
    int? kcal,
    String? title,
  }) async {
    _check('writeWorkout');
    final uuid = 'k${++_next}';
    workouts[uuid] = (start: start, end: end, kcal: kcal, title: title);
    return uuid;
  }

  @override
  Future<void> deleteWeight(String uuid) async {
    _check('deleteWeight');
    weights.removeWhere((w) => w.uuid == uuid);
  }

  @override
  Future<void> deleteWorkout(String uuid) async {
    _check('deleteWorkout');
    workouts.remove(uuid);
  }

  @override
  Future<List<HealthReading>> readRestingHeartRate(DateTime from, DateTime to) async {
    _check('readRhr');
    return restingHeartRate;
  }

  @override
  Future<List<HealthReading>> readHeartRateVariability(DateTime from, DateTime to) async {
    _check('readHrv');
    return heartRateVariability;
  }

  @override
  Future<List<SleepSegment>> readSleep(DateTime from, DateTime to) async {
    _check('readSleep');
    return sleep;
  }
}
