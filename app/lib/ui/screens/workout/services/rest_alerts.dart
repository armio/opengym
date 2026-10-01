import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The local "Descanso terminado" notification at the rest timer's `endsAt` (contract §6,
/// specs/ui.md §1.10): scheduled when a rest starts, rescheduled on ±15 s, cancelled on skip,
/// finish, discard and cold start.
abstract interface class RestAlerts {
  /// Schedules (or moves) the alert to [endsAt].
  Future<void> schedule(DateTime endsAt);

  /// Cancels the pending alert, if any.
  Future<void> cancel();
}

/// [RestAlerts] that does nothing (tests, unsupported platforms).
class NoRestAlerts implements RestAlerts {
  const NoRestAlerts();

  @override
  Future<void> schedule(DateTime endsAt) async {}

  @override
  Future<void> cancel() async {}
}

/// [RestAlerts] with `flutter_local_notifications` on Android and iOS; a no-op elsewhere (web).
///
/// Call [init] once at startup: it also cancels an alert left behind by a session the system
/// killed (critic-G10). Permission is asked the first time a rest is scheduled, and refusing
/// it only means no notification. Calls run one after another, so a cancel never overtakes the
/// schedule before it.
class LocalRestAlerts implements RestAlerts {
  LocalRestAlerts._();

  static final instance = LocalRestAlerts._();

  static const _id = 7301;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rest_timer',
      'Descanso',
      channelDescription: 'Aviso cuando termina el descanso entre series',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> _queue = Future.value();
  bool _ready = false;
  bool _askedPermission = false;

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Initialises the plugin (without prompting) and drops any orphan alert.
  Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
      await _plugin.cancel(id: _id);
    } catch (e) {
      debugPrint('rest alerts unavailable: $e');
    }
  }

  @override
  Future<void> schedule(DateTime endsAt) => _run(() async {
    if (!endsAt.isAfter(DateTime.now())) return;
    await _askPermissionOnce();
    await _plugin.zonedSchedule(
      id: _id,
      title: 'Descanso terminado',
      body: 'Es hora de la siguiente serie.',
      scheduledDate: tz.TZDateTime.from(endsAt, tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: await _canScheduleExact()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  });

  @override
  Future<void> cancel() => _run(() => _plugin.cancel(id: _id));

  Future<void> _run(Future<void> Function() op) {
    if (!_ready) return Future.value();
    return _queue = _queue.then((_) async {
      try {
        await op();
      } catch (e) {
        debugPrint('rest alert failed: $e');
      }
    });
  }

  Future<void> _askPermissionOnce() async {
    if (_askedPermission) return;
    _askedPermission = true;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
      alert: true,
      sound: true,
    );
  }

  /// Exact alarms need a permission Android 14 no longer grants by default; without it the
  /// alert may come a little late rather than not at all.
  Future<bool> _canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? false;
  }
}
