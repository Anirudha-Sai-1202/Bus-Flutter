// lib/main.dart

import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/home_screen.dart';
import 'services/background_service.dart';

const notificationChannelId = 'vj_bus_driver_channel';

// --- NEW: Configured for minimal user intrusion ---
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  notificationChannelId,
  'VJ Bus Driver Service',
  description: 'Background location tracking service.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  try {
    await initializeService();
  } catch (e, stacktrace) {
    dev.log("Error during service initialization", error: e, stackTrace: stacktrace);
  }
  runApp(const DriverLocationApp());
}

class DriverLocationApp extends StatelessWidget {
  const DriverLocationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VJ Bus Driver',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
