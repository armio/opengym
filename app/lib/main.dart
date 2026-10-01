import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'ui/screens/workout/workout_screen.dart' show LocalRestAlerts;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'es';
  await initializeDateFormatting('es');
  // Also drops a rest alert left over from a session the system killed.
  await LocalRestAlerts.instance.init();
  runApp(const OpenGymApp());
}
