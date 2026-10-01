import 'dart:async';

import 'package:flutter/services.dart';

/// Sounds and haptics of the guided workout (specs/ui.md §1.9). The original synthesises sine
/// beeps; the port uses the platform's click and alert sounds, gated by `settings.sound`, and
/// haptics, which — like the original's `vibrate` — ignore that setting.
class WorkoutFeedback {
  const WorkoutFeedback({required this.soundOn});

  /// Reads `settings.sound` at the moment of each event.
  final bool Function() soundOn;

  /// A set was checked off: short beep + 30 ms buzz.
  void setChecked() {
    _sound(SystemSoundType.click);
    unawaited(HapticFeedback.lightImpact());
  }

  /// Each of the last three seconds of a rest or a hold.
  void countdown() => _sound(SystemSoundType.click);

  /// A rest or a hold reached zero: the triple beep and the `[200, 100, 200]` buzz.
  void timerOver() {
    _sound(SystemSoundType.alert);
    unawaited(HapticFeedback.vibrate());
    Timer(const Duration(milliseconds: 300), () => unawaited(HapticFeedback.vibrate()));
  }

  /// "Listo" on a hold before the countdown ended.
  void holdEndedEarly() => unawaited(HapticFeedback.lightImpact());

  /// The workout was finished.
  void workoutFinished() => _sound(SystemSoundType.alert);

  void _sound(SystemSoundType type) {
    if (soundOn()) unawaited(SystemSound.play(type));
  }
}
