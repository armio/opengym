import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../data/clock.dart';
import 'rest_alerts.dart';
import 'workout_feedback.dart';

/// A countdown on the wall clock: what is left, out of what, and when it ends.
@immutable
class Countdown {
  const Countdown({required this.left, required this.total, required this.endsAt, this.label});

  /// Whole seconds left.
  final int left;

  /// Seconds the bar measures against (±15 s moves it too).
  final int total;

  /// Epoch ms of the end — the single source of truth, so the countdown survives the app being
  /// in the background.
  final int endsAt;

  /// The exercise a hold belongs to (work timer only).
  final String? label;

  /// What is left of the bar, 1 → 0.
  double get fraction => total <= 0 ? 0 : (left / total).clamp(0, 1).toDouble();

  Countdown copyWith({int? left, int? total, int? endsAt}) =>
      Countdown(left: left ?? this.left, total: total ?? this.total, endsAt: endsAt ?? this.endsAt, label: label);
}

/// Where a hold is logged: the workout, entry and set it was started for. A hold that ends
/// after its workout was finished, discarded or replaced finds no match and logs nothing
/// (critic-G1).
@immutable
class HoldTarget {
  const HoldTarget({required this.activeId, required this.entry, required this.set});

  final String activeId;
  final int entry;
  final int set;
}

/// The two timers of the guided workout (specs/ui.md §5.7, §5.8): the rest between sets and the
/// countdown of a timed set. At most one runs: starting a hold stops the rest.
///
/// Both run on the wall clock (`endsAt`): a tick every second and [tick] on resume recompute
/// what is left. The rest also schedules the "Descanso terminado" notification at its end. When
/// a rest runs out while the app is in the background the notification is left to fire; in the
/// foreground it is cancelled and the app beeps and buzzes instead.
class WorkoutTimers extends ChangeNotifier {
  WorkoutTimers({required this.clock, required this.alerts, required this.feedback, bool Function()? isForeground})
    : _isForeground = isForeground ?? _appInForeground;

  final Clock clock;
  final RestAlerts alerts;
  final WorkoutFeedback feedback;
  final bool Function() _isForeground;

  /// Called when a rest runs out in the foreground ("¡Descanso terminado — siguiente serie!").
  VoidCallback? onRestOver;

  /// Called with the seconds actually held when a hold reaches zero or is ended early.
  void Function(HoldTarget target, int elapsed)? onHoldDone;

  Countdown? _rest;
  Countdown? _hold;
  HoldTarget? _holdTarget;
  Timer? _ticker;
  bool _disposed = false;

  Countdown? get rest => _rest;
  Countdown? get hold => _hold;
  HoldTarget? get holdTarget => _holdTarget;
  bool get isRunning => _rest != null || _hold != null;

  static bool _appInForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  // ---------------------------------------------------------------------------------------
  // Rest.

  /// Starts a fresh rest of [seconds] (restarting a running one from full).
  void startRest(int seconds) {
    _rest = null;
    final endsAt = clock.nowMs() + seconds * 1000;
    _rest = Countdown(left: seconds, total: seconds, endsAt: endsAt);
    unawaited(alerts.schedule(DateTime.fromMillisecondsSinceEpoch(endsAt)));
    _changed();
  }

  /// ±15 s. Taking off more than is left is the same as skipping.
  void addRest(int seconds) {
    final r = _rest;
    if (r == null) return;
    final left = r.left + seconds;
    if (left <= 0) {
      stopRest();
      return;
    }
    _rest = r.copyWith(left: left, total: r.total + seconds, endsAt: r.endsAt + seconds * 1000);
    unawaited(alerts.schedule(DateTime.fromMillisecondsSinceEpoch(_rest!.endsAt)));
    _changed();
  }

  /// Skip, or anything that makes the rest pointless.
  void stopRest() {
    if (_rest == null) return;
    _rest = null;
    unawaited(alerts.cancel());
    _changed();
  }

  // ---------------------------------------------------------------------------------------
  // Hold (work timer).

  /// Starts the countdown of a timed set of [seconds] for [target]; stops any rest.
  void startHold(num seconds, {required String label, required HoldTarget target}) {
    _clearHold();
    stopRest();
    final total = math.max(1, seconds.isFinite ? seconds.round() : 1);
    _hold = Countdown(left: total, total: total, endsAt: clock.nowMs() + total * 1000, label: label);
    _holdTarget = target;
    _changed();
  }

  /// "Listo": logs what was actually held (at least 1 s).
  void endHoldEarly() {
    final h = _hold, target = _holdTarget;
    if (h == null || target == null) return;
    feedback.holdEndedEarly();
    _clearHold();
    _changed();
    onHoldDone?.call(target, math.max(1, h.total - h.left));
  }

  /// "Cancelar" (and finish / discard / a new workout): nothing is logged.
  void cancelHold() {
    if (_hold == null) return;
    _clearHold();
    _changed();
  }

  void _clearHold() {
    _hold = null;
    _holdTarget = null;
  }

  // ---------------------------------------------------------------------------------------
  // Ticking.

  /// Recomputes both countdowns from the clock (every second, and when the app resumes).
  void tick() {
    final now = clock.nowMs();
    var changed = false;
    final r = _rest;
    if (r != null) {
      final left = _leftAt(r, now);
      if (left != r.left) {
        changed = true;
        if (left <= 0) {
          _restOver(lateMs: now - r.endsAt);
        } else {
          if (left <= 3 && _isForeground()) feedback.countdown();
          _rest = r.copyWith(left: left);
        }
      }
    }
    final h = _hold, target = _holdTarget;
    if (h != null && target != null) {
      final left = _leftAt(h, now);
      if (left != h.left) {
        changed = true;
        if (left <= 0) {
          feedback.timerOver();
          _clearHold();
          _changed();
          onHoldDone?.call(target, h.total);
          return;
        }
        if (left <= 3) feedback.countdown();
        _hold = h.copyWith(left: left);
      }
    }
    if (changed) _changed();
  }

  static int _leftAt(Countdown c, int now) => math.max(0, ((c.endsAt - now) / 1000).round());

  /// How late a rest may end and still beep: later than this it ended while the app was
  /// suspended, the scheduled notification already told the owner, and a beep now would be stale.
  static const lateRestMs = 2000;

  void _restOver({int lateMs = 0}) {
    _rest = null;
    // In the background the scheduled notification is what tells the owner; keep it.
    if (!_isForeground()) return;
    unawaited(alerts.cancel());
    if (lateMs > lateRestMs) return;
    feedback.timerOver();
    onRestOver?.call();
  }

  void _changed() {
    if (_disposed) return;
    if (isRunning) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => tick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}
