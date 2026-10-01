import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opengym/data/api_client.dart';
import 'package:opengym/data/app_state.dart';
import 'package:opengym/data/clock.dart';
import 'package:opengym/data/local_store.dart';
import 'package:opengym/data/session_store.dart';
import 'package:opengym/data/models/models.dart';
import 'package:opengym/ui/screens/workout/workout_screen.dart';
import 'package:opengym/ui/theme.dart';
import 'package:opengym/ui/workout_launcher.dart';
import 'package:provider/provider.dart';

import '../../data/fake_server.dart';

/// [WorkoutFeedback] that records events instead of beeping.
class RecordingFeedback extends WorkoutFeedback {
  RecordingFeedback() : super(soundOn: () => true);

  final events = <String>[];

  @override
  void setChecked() => events.add('check');
  @override
  void countdown() => events.add('countdown');
  @override
  void timerOver() => events.add('over');
  @override
  void holdEndedEarly() => events.add('early');
  @override
  void workoutFinished() => events.add('finished');
}

/// [RestAlerts] that records what was scheduled and cancelled.
class RecordingAlerts implements RestAlerts {
  final log = <String>[];

  /// The pending alert, or null.
  DateTime? pending;

  @override
  Future<void> schedule(DateTime endsAt) async {
    pending = endsAt;
    log.add('schedule ${endsAt.millisecondsSinceEpoch}');
  }

  @override
  Future<void> cancel() async {
    pending = null;
    log.add('cancel');
  }
}

class FakeWakeLock implements ScreenWakeLock {
  bool held = false;
  final log = <String>[];

  @override
  Future<void> acquire() async {
    held = true;
    log.add('acquire');
  }

  @override
  Future<void> release() async {
    held = false;
    log.add('release');
  }
}

/// Exercise ids of the test catalogue.
abstract final class Ex {
  static const bench = '0025'; // barbell bench press (chest)
  static const incline = '0047'; // barbell incline bench press (chest)
  static const squat = '0043'; // barbell full squat (upper legs)
  static const row = '0027'; // barbell bent over row (back)
  static const plank = '0464'; // front plank with twist (waist), logged as a hold
  static const run = '0685'; // run (cardio)
}

/// An [AppState] (signed in to a fake server, clock fixed at Wed 2026-09-30 18:00) with the
/// workout services on recording fakes.
class WorkoutHarness {
  WorkoutHarness({DateTime? now, FakeSyncServer? server})
    : clock = FakeClock(now ?? DateTime(2026, 9, 30, 18)),
      server = server ?? FakeSyncServer() {
    app = AppState(
      library: loadTestLibrary(),
      store: store,
      sessions: MemorySessionStore(),
      session: const SessionInfo(
        serverUrl: 'https://gym.example.com',
        deviceName: 'Test',
        deviceId: 'd1',
        token: 'tok',
      ),
      clock: clock,
      apiFactory: (url, token) => ApiClient(
        baseUrl: url,
        token: token,
        timeZone: () async => 'Europe/Madrid',
        httpClient: this.server.httpClient(),
      ),
    );
    controller = WorkoutController(
      app: app,
      alerts: alerts,
      feedback: feedback,
      wakeLock: wakeLock,
      isForeground: () => foreground,
    );
  }

  final FakeClock clock;
  final FakeSyncServer server;
  final store = MemoryLocalStore();
  late final AppState app;
  late final WorkoutController controller;
  final alerts = RecordingAlerts();
  final feedback = RecordingFeedback();
  final wakeLock = FakeWakeLock();
  bool foreground = true;

  WorkoutTimers get timers => controller.timers;

  /// Advances the clock by [seconds] and lets the timers tick.
  void advance(int seconds) {
    clock.advance(Duration(seconds: seconds));
    timers.tick();
  }

  /// Adds [routine] to the plan (and schedules it on today's weekday with [today]).
  void addRoutine(Routine routine, {bool today = false}) => app.updatePlan((p) {
    p.routines.add(routine);
    if (today) p.week['3'] = routine.id; // 2026-09-30 is a Wednesday
  });

  /// Starts [routine] (or freestyle) through the controller, as the check-in would.
  Future<void> start(Routine? routine, {num? bodyWeight}) => controller.begin(routine, bodyWeight: bodyWeight);

  ActiveWorkout get active => app.active!;

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: app),
      Provider<WorkoutLauncher>.value(value: const DefaultWorkoutLauncher()),
      Provider<WorkoutController>.value(value: controller),
      ChangeNotifierProvider<WorkoutTimers>.value(value: controller.timers),
    ],
    child: MaterialApp(
      theme: AppTheme.build(brightness: Brightness.dark),
      home: child,
    ),
  );

  /// Pumps [child] on a tall phone-width view.
  Future<void> pump(WidgetTester tester, Widget child, {double width = 390, double height = 3000}) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mockPathProvider(tester);
    await tester.pumpWidget(wrap(child));
    await tester.pump();
  }

  /// Stops the timers, lets debounced persistence/sync, toasts and the image cache's cleanup
  /// timer run out, and disposes.
  Future<void> dispose(WidgetTester tester) async {
    timers
      ..stopRest()
      ..cancelHold();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    app.dispose();
  }

  /// For tests without widgets.
  void disposeNow() {
    controller.dispose();
    app.dispose();
  }
}

/// Lets `cached_network_image` find a cache directory.
void mockPathProvider(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp/opengym-test-cache',
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    ),
  );
}

/// A routine exercise in reps mode.
RoutineExercise repsEx(String id, {int sets = 3, num reps = 8, num weight = 0, String? sg, String? prog}) =>
    RoutineExercise(id: id, sets: sets, reps: reps, weight: weight, mode: 'reps', sg: sg, prog: prog);

/// A finished workout of [entries] on [d].
Workout pastWorkout(String id, String d, List<WorkoutEntry> entries, {String? routineId}) {
  final start = DateTime.parse('${d}T18:00:00').millisecondsSinceEpoch;
  return Workout(
    id: id,
    d: d,
    start: start,
    end: start + 3600000,
    routineId: routineId,
    name: 'Empuje',
    entries: entries,
  );
}

/// Done reps sets `[[w, r], …]` with the stored target.
WorkoutEntry repsEntry(String id, List<List<num>> sets, {JsonMap? target}) => WorkoutEntry(
  id: id,
  sets: [for (final s in sets) SetRecord(w: s[0], r: s[1], done: true)],
  target: target,
);
