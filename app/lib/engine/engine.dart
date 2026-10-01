/// The training engine (contract §2.3): pure functions over the typed models — modes,
/// progression, e1RM, effort, muscles, finishing a workout, stats and the Coach — identical in
/// behaviour to the Worker's TypeScript engine and pinned by the shared fixtures in
/// `docs/flutter-cloudflare/fixtures`.
///
/// Clock-dependent functions take `now` (and a [LocalCalendar], the device zone by default);
/// order-dependent ones expect workouts in `(d, start)` order, as `AppState.workouts` gives them.
/// `catalog_bridge.dart` adapts the app's catalogue and state (the only Flutter-dependent file).
library;

export 'calendar.dart';
export 'catalog.dart';
export 'catalog_bridge.dart';
export 'coach/coach.dart';
export 'effort.dart';
export 'finish.dart';
export 'format.dart';
export 'history.dart';
export 'js.dart';
export 'muscles.dart';
export 'onerm.dart';
export 'progression.dart';
export 'session.dart';
export 'starter.dart';
export 'stats.dart';
export 'training_state.dart';
export 'why.dart';
