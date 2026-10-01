import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on (specs/ui.md §1.8). Failures (unsupported browser, iOS Low Power Mode)
/// are swallowed; the owner of the intent asks again when the app comes back to the
/// foreground.
abstract interface class ScreenWakeLock {
  Future<void> acquire();
  Future<void> release();
}

/// [ScreenWakeLock] through `wakelock_plus`.
class PlatformWakeLock implements ScreenWakeLock {
  const PlatformWakeLock();

  @override
  Future<void> acquire() => _toggle(true);

  @override
  Future<void> release() => _toggle(false);

  static Future<void> _toggle(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } catch (e) {
      debugPrint('wake lock ${enable ? 'acquire' : 'release'} failed: $e');
    }
  }
}
