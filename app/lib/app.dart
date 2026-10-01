import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/app_state.dart';
import 'data/health/health_bridge.dart';
import 'data/health/health_sync.dart';
import 'data/library.dart';
import 'ui/screens/login/login_screen.dart';
import 'ui/screens/workout/workout_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets/widgets.dart';
import 'ui/workout_launcher.dart';

/// The root navigator (sheets, dialogs, full-screen routes such as the workout).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Loads local data and the session, then shows the login screen or the shell.
///
/// Tests pass a ready [appState]; the app itself loads one with [loader] (default:
/// [AppState.load] with the bundled exercise library). Once loaded, one [WorkoutController]
/// (timers, rest alerts, wake lock) lives as long as the app.
class OpenGymApp extends StatefulWidget {
  const OpenGymApp({
    super.key,
    this.appState,
    this.loader,
    this.workoutLauncher = const DefaultWorkoutLauncher(),
    this.restAlerts,
    this.wakeLock = const PlatformWakeLock(),
    this.healthBridge,
  });

  final AppState? appState;
  final Future<AppState> Function()? loader;

  /// How workouts start (the centre "Entrenar" button, Home, the start chooser).
  final WorkoutLauncher workoutLauncher;

  /// The "Descanso terminado" notification (default: [LocalRestAlerts.instance]).
  final RestAlerts? restAlerts;

  /// Keeps the screen on during a workout.
  final ScreenWakeLock wakeLock;

  /// Apple Health (default: HealthKit on iPhone, unsupported elsewhere).
  final HealthBridge? healthBridge;

  @override
  State<OpenGymApp> createState() => _OpenGymAppState();
}

class _OpenGymAppState extends State<OpenGymApp> {
  late final Future<AppState> _state = widget.appState != null
      ? Future.value(widget.appState)
      : (widget.loader ?? () async => AppState.load(library: await ExerciseLibrary.load()))();
  WorkoutController? _workout;
  HealthSync? _health;

  WorkoutController _workoutFor(AppState app) => _workout ??= WorkoutController(
    app: app,
    alerts: widget.restAlerts ?? LocalRestAlerts.instance,
    wakeLock: widget.wakeLock,
  );

  HealthSync _healthFor(AppState app) {
    final existing = _health;
    if (existing != null) return existing;
    final health = _health = HealthSync(app: app, bridge: widget.healthBridge ?? HealthBridge.platform());
    unawaited(health.start());
    return health;
  }

  @override
  void dispose() {
    _workout?.dispose();
    _health?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _state,
      builder: (context, snapshot) {
        final app = snapshot.data;
        if (app == null) {
          return _themedApp(
            theme: AppTheme.build(brightness: Brightness.dark),
            home: snapshot.hasError ? _BootError(error: snapshot.error!) : const _Splash(),
          );
        }
        final workout = _workoutFor(app);
        final health = _healthFor(app);
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            Provider<WorkoutLauncher>.value(value: widget.workoutLauncher),
            Provider<WorkoutController>.value(value: workout),
            ChangeNotifierProvider<WorkoutTimers>.value(value: workout.timers),
            ChangeNotifierProvider<HealthSync>.value(value: health),
          ],
          child: const _AppView(),
        );
      },
    );
  }
}

/// Rebuilds the MaterialApp only when the theme or accent changes.
class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    final (theme, accent) = context.select<AppState, (String, String)>((s) => (s.settings.theme, s.settings.accent));
    return _themedApp(
      theme: AppTheme.fromSettings(theme: theme, accent: accent),
      navigatorKey: rootNavigatorKey,
      home: const _AuthGate(),
    );
  }
}

/// The login screen or the shell. Signing in or out also drops any pushed full-screen routes.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool? _signedIn;

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AppState, bool>((s) => s.isSignedIn);
    if (_signedIn != null && _signedIn != signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.of(context).popUntil((r) => r.isFirst));
    }
    _signedIn = signedIn;
    return signedIn ? const Shell(key: ValueKey('shell')) : const LoginScreen(key: ValueKey('login'));
  }
}

Widget _themedApp({required ThemeData theme, required Widget home, GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      title: 'openGym',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: theme,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );

/// While local data loads: a dumbbell at 44 % of the height (specs/ui.md §1.1).
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Align(
      alignment: const Alignment(0, -.12),
      child: AppIcon('dumbbell', size: 34, color: context.palette.label3),
    ),
  );
}

class _BootError extends StatelessWidget {
  const _BootError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: EmptyState(icon: 'info', message: 'No se pudieron cargar los datos de este dispositivo.\n$error'),
  );
}
