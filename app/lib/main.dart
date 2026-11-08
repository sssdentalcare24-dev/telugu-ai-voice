import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final controller = AppController(prefs: prefs);
  runApp(TeluguVoiceApp(controller: controller));
  // Ask the server what it can do; screens update when the answer arrives.
  controller.refreshServer();
}
