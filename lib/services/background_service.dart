// lib/services/background_service.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import '../main.dart'; // Make sure this path is correct if main.dart is needed here for flutterLocalNotificationsPlugin

// --- Entry point for initializing the background service ---
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'VJ Bus Driver Service', // More descriptive
      initialNotificationContent: 'Service is running in background.', // More descriptive
      foregroundServiceNotificationId: 888,
      // 'ongoing: true' is handled within AndroidNotificationDetails for persistence
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      autoStart: true,
    ),
  );
  logToApp("BackgroundService: Initializing service...");
  await service.startService();
  logToApp("BackgroundService: Service started.");
}

// --- Global variables to be managed by the single onStart instance ---
IO.Socket? currentSocket;
Timer? trackingTimer;
Timer? socketHealthTimer; // New timer for socket health checks
Timer? midnightResetTimer; // Timer to reset sendAsUpdate at midnight
String? activeRouteId; // The route ID the currentSocket is connected with
bool isTracking = false; // Indicates if location updates are actively being sent
bool isSocketConnected = false; // Indicates if the single socket is connected
bool sendAsUpdate = false; // Controls if 'location_update' or 'check_location' is sent
late SharedPreferences prefs;

// --- Helper Functions (defined globally for accessibility) ---

// Function to schedule reset of sendAsUpdate at midnight
void _scheduleMidnightReset() {
  // Cancel any existing timer
  midnightResetTimer?.cancel();
  
  // Get the current time
  final now = DateTime.now();
  
  // Calculate the next midnight
  final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
  
  // Calculate the duration until midnight
  final durationUntilMidnight = nextMidnight.difference(now);
  
  // Schedule the timer to reset sendAsUpdate at midnight
  midnightResetTimer = Timer(durationUntilMidnight, () {
    sendAsUpdate = false;
    logToApp("BackgroundService: sendAsUpdate reset to false at midnight");
    
    // Schedule the next reset
    _scheduleMidnightReset();
  });
  
  logToApp("BackgroundService: Scheduled sendAsUpdate reset in ${durationUntilMidnight.inSeconds} seconds");
}

IO.Socket _createSocket(String url, String role, String routeId) {
  try {
    logToApp("SOCKET: Initializing new socket => role=$role, route_id=$routeId");
    _updateNotification(title: "Creating Socket", content: "${routeId}.");


    final manager = IO.io(
      url,
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setQuery({'role': role, 'route_id': routeId})
        .setReconnectionAttempts(999) // High number for persistent reconnection
        .setReconnectionDelay(2000)   // Start retrying after 2 seconds
        .setReconnectionDelayMax(10000) 
        .build(),
    );

    final socket = manager.connect();

    logToApp("SOCKET: Socket created. Waiting to connect...");

    return socket;
  } catch (e, st) {
    logToApp("SOCKET: Failed to create socket => $e\n$st");
    rethrow;
  }
}


// IO.Socket _createSocket(String url, String role, String routeId) {
//   _updateNotification(title: "Creating Socket", content: "${routeId}.");

//   logToApp("BackgroundService: Inside _createSocket. Building socket for URL: $url, Role: $role, **USING RouteID: $routeId**");
//   logToApp("BackgroundService: Socket query parameters - role: $role, route_id: $routeId");
//   logToApp("BackgroundService: Creating socket with URL: $url, role: $role, routeId: $routeId");
//   final socket = IO.io(
//     url,
//     IO.OptionBuilder()
//         .setTransports(['websocket'])
//         .setQuery({'role': role, 'route_id': routeId}) // Ensure routeId is correctly passed here
//         .enableReconnection()         // Enable automatic reconnection
//         .setReconnectionAttempts(999) // High number for persistent reconnection
//         .setReconnectionDelay(2000)   // Start retrying after 2 seconds
//         .setReconnectionDelayMax(10000) // Max delay of 10 seconds
//         .build(),
//   );
//   logToApp("BackgroundService: Socket created successfully");
//   return socket;
// }

void _updateNotification({required String title, required String content}) {
  flutterLocalNotificationsPlugin.show(
    888,
    title,
    content,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        'VJ Bus Driver Service',
        importance: Importance.high,
        priority: Priority.high, // High priority
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public, // Shows content on lock screen
        ticker: 'ticker',
        ongoing: true, // Make notification unswipeable (Correctly placed here)
        enableLights: true,
        fullScreenIntent: false, // Set to false unless you want to launch an activity when screen is off
      ),
    ),
  );
  logToApp("BackgroundService: Notification updated - Title: $title, Content: $content");
}

Future<void> _sendFinalBroadcast(IO.Socket socket, String routeId) async {
  logToApp("BackgroundService: Sending final broadcast for route: $routeId");
  try {
    Position? position = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));
    logToApp("BackgroundService: Calling emit() for final broadcast with event type: location_update, socket ID: ${socket.id}");
    socket.emit("location_update", {
      "route_id": routeId, "latitude": position?.latitude, "longitude": position?.longitude, "socket_id": socket.id,
      "role": "Driver", "heading": position?.heading, "status": "stopped", "timestamp": DateTime.now().millisecondsSinceEpoch,
    });
    await Future.delayed(const Duration(milliseconds: 500));
    logToApp("BackgroundService: Final broadcast sent successfully for route: $routeId.");
  } catch (e) { logToApp("BackgroundService: Error sending final broadcast for route $routeId: $e"); }
}

// Function to periodically check socket health and reconnect if needed
Future<void> _startSocketHealthCheck(ServiceInstance serviceRef) async {
  // Cancel any existing socket health timer
  socketHealthTimer?.cancel();
  
  // Start a new timer that checks socket health every 30 seconds
  socketHealthTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
    logToApp("BackgroundService: Performing socket health check. Current state - connected: ${currentSocket?.connected ?? false}, isSocketConnected: $isSocketConnected, activeRouteId: $activeRouteId");
    
    // Check if we have a route selected
    final String? storedRouteId = prefs.getString('selectedRoute');
    logToApp("BackgroundService: Route from SharedPreferences in health check: $storedRouteId");
    
    // Only attempt to reconnect if a route is selected
    if (storedRouteId != null) {
      // Always ensure we have a route to use
      final String routeToUse = storedRouteId;
      
      // If socket is not connected or connection state is inconsistent, reconnect
      if (currentSocket == null || !currentSocket!.connected || !isSocketConnected) {
        logToApp("BackgroundService: Socket health check detected disconnection. Attempting to reconnect for route: $routeToUse");
        await _connectPersistentSocket(serviceRef, routeToUse);
        logToApp("BackgroundService: Socket reconnection attempt completed for route: $routeToUse");
      }
    } else {
      logToApp("BackgroundService: No route selected. Skipping socket health check reconnection.");
    }
  });
  
  logToApp("BackgroundService: Started socket health check timer.");
}

// Function to create and manage a persistent socket connection
Future<void> _connectPersistentSocket(ServiceInstance serviceRef, String routeIdToConnect) async {
  try {
    if (currentSocket != null) {
      logToApp("SOCKET: Cleaning up old socket");

      currentSocket?.clearListeners(); // Remove all custom listeners
      currentSocket?.offAny();         // Extra safe remove
      currentSocket?.disconnect();
      currentSocket?.close();
      currentSocket?.destroy();
      currentSocket = null;

      await Future.delayed(Duration(milliseconds: 100));
      logToApp("SOCKET: Old socket cleanup completed");
    }

    logToApp("SOCKET: Creating new socket for route_id=$routeIdToConnect");

    currentSocket = _createSocket(websocketUrl, "Driver", routeIdToConnect);

    currentSocket!.onConnect((_) {
      logToApp("SOCKET: Connected with id: ${currentSocket!.id}");
    });

    currentSocket!.on("location_response", (data) {
      logToApp("SOCKET: location_response => $data");
    });

    currentSocket!.onDisconnect((_) {
      logToApp("SOCKET: Disconnected.");
    });

    currentSocket!.onError((err) {
      logToApp("SOCKET: Error => $err");
    });

    currentSocket!.onReconnect((_) {
      logToApp("SOCKET: Reconnected.");
    });

  } catch (e, st) {
    logToApp("SOCKET: Error in _connectPersistentSocket => $e\n$st");
  }
}

// Function to start location tracking (starts timer)
Future<void> _startTrackingLogic(ServiceInstance serviceRef) async {
  logToApp("BackgroundService: _startTrackingLogic called. Current state - isTracking: $isTracking, trackingTimer active: ${trackingTimer?.isActive ?? false}");
  logToApp("BackgroundService: Current activeRouteId: $activeRouteId");
  
  // If already tracking, just return
  if (isTracking && trackingTimer != null && trackingTimer!.isActive) {
    logToApp("BackgroundService: Tracking already active. Skipping start tracking logic.");
    return;
  }
  
  // Check if socket is connected
  if (currentSocket == null || !currentSocket!.connected) {
    logToApp("BackgroundService: Cannot start tracking: Socket not connected.");
    serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Socket Disconnected', 'isAdminConnected': false});
    _updateNotification(title: "Tracking Failed", content: "Socket not connected.");
    return;
  }

  isTracking = true;
  // Note: sendAsUpdate should remain false initially, only start_now should set it to true
  WakelockPlus.enable();
  _updateNotification(title: "Tracking Active", content: "Live on Route: ${activeRouteId ?? 'N/A'}");
  serviceRef.invoke('updateUI', {'isTracking': true, 'status': 'Connected', 'isAdminConnected': true, 'socketId': currentSocket?.id});
  logToApp("BackgroundService: Starting tracking timer.");

  // Ensure old timer is cancelled before starting a new one
  trackingTimer?.cancel();

  trackingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
    if (currentSocket == null || !currentSocket!.connected || !isTracking) {
      logToApp("BackgroundService: Tracking timer stopped: socket disconnected or not tracking.");
      timer.cancel();
      return;
    }
    try {
      Position position = await Geolocator.getCurrentPosition(forceAndroidLocationManager: true, timeLimit: const Duration(seconds: 10));
      logToApp("BackgroundService: Emitting location. Route: ${activeRouteId ?? 'N/A'}. Lat=${position.latitude}, Lng=${position.longitude}, Status=${sendAsUpdate ? "tracking_active" : "checking"}");
      final String eventType = sendAsUpdate ? "location_update" : "check_location";
      logToApp("BackgroundService: Emitting $eventType for route: ${activeRouteId ?? 'default'}");
      logToApp("BackgroundService: Calling emit() with event type: $eventType, socket ID: ${currentSocket!.id}");
      currentSocket!.emit(eventType, {
        "route_id": activeRouteId ?? "default", // Always use current route
        "latitude": position.latitude,
        "longitude": position.longitude,
        "socket_id": currentSocket!.id,
        "role": "Driver",
        "heading": position.heading,
        "status": sendAsUpdate ? "tracking_active" : "checking",
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      logToApp("BackgroundService: Error getting or sending location: $e");
      // Consider more aggressive handling here, e.g., stopping tracking if errors persist
    }
  });
}

// Function to stop location tracking (stops timer, keeps socket connected)
Future<void> _stopTrackingLogic(ServiceInstance serviceRef) async {
  logToApp("BackgroundService: _stopTrackingLogic called. Current state - isTracking: $isTracking, trackingTimer active: ${trackingTimer?.isActive ?? false}");
  logToApp("BackgroundService: Current activeRouteId: $activeRouteId");
  
  // If not tracking, just return
  if (!isTracking && (trackingTimer == null || !trackingTimer!.isActive)) {
    logToApp("BackgroundService: Tracking is already inactive. Skipping stop tracking logic.");
    return;
  }

  isTracking = false;
  sendAsUpdate = false; // Set to false when not tracking
  WakelockPlus.disable();
  trackingTimer?.cancel();
  trackingTimer = null;
  logToApp("BackgroundService: Tracking timer cancelled and wakelock disabled.");

  // Send a final "stopped" broadcast if the socket is still connected
  if (currentSocket != null && currentSocket!.connected && activeRouteId != null) {
    await _sendFinalBroadcast(currentSocket!, activeRouteId!);
  }

  _updateNotification(title: "Tracking Stopped", content: "Service connected, but tracking is paused.");
  serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
  logToApp("BackgroundService: Tracking stopped, UI updated.");
}


// Updated _cleanupResources for full service shutdown (e.g., app killed)
// This will be called when the service itself is being completely shut down.
Future<void> _cleanupResources(ServiceInstance serviceRef, {bool sendFinalBroadcast = false}) async {
  logToApp("BackgroundService: Cleaning up ALL resources for full shutdown. sendFinalBroadcast=$sendFinalBroadcast.");
  // Ensure tracking is stopped before disconnecting socket
  await _stopTrackingLogic(serviceRef);

  // Cancel the socket health timer
  socketHealthTimer?.cancel();
  socketHealthTimer = null;
  logToApp("BackgroundService: Socket health timer cancelled during cleanup.");

  if (currentSocket != null) {
    logToApp("BackgroundService: Attempting to fully destroy main socket during cleanup.");
    try {
      currentSocket!.offAny();
      currentSocket!.disconnect();
      currentSocket!.close();
      currentSocket!.destroy(); // Explicitly destroy the socket on full service shutdown
      currentSocket = null;
      logToApp("BackgroundService: Main socket completely destroyed during cleanup.");
    } catch (e) {
      logToApp("BackgroundService: Error destroying socket during cleanup: $e");
    }
  }

  isSocketConnected = false;
  serviceRef.invoke('updateUI', {'isTracking': false, 'status': 'Stopped', 'isAdminConnected': false, 'socketId': null});
  logToApp("BackgroundService: Invoked updateUI: isTracking=false, status=Stopped for full shutdown cleanup.");
}


// --- onStart function (main entry point for background service) ---
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    logToApp("BackgroundService: Service set to foreground mode immediately onStart.");
  }

  prefs = await SharedPreferences.getInstance();
  logToApp("BackgroundService: SharedPreferences initialized in onStart.");

  Future.microtask(() async {
    // Add a small delay to ensure SharedPreferences are properly initialized
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Initialize the midnight reset timer for sendAsUpdate
    _scheduleMidnightReset();
    
    // Always re-fetch the latest selectedRoute from preferences at the start of onStart logic
    final String? storedRouteId = prefs.getString('selectedRoute');
    logToApp("BackgroundService: Route from SharedPreferences on start: $storedRouteId");
    logToApp("BackgroundService: Current time: ${DateTime.now()}");
    final DateTime now = DateTime.now();
    final DateTime sixThirtyAM = DateTime(now.year, now.month, now.day, 6, 30);
    final DateTime elevenAM = DateTime(now.year, now.month, now.day, 11, 0);
    logToApp("BackgroundService: Time range for auto-start: $sixThirtyAM - $elevenAM");

    // Only connect socket if a route is selected
    if (storedRouteId != null) {
      logToApp("BackgroundService: Route selected. Connecting socket for route: $storedRouteId");
      await _connectPersistentSocket(service, storedRouteId);
      
      // Now, check if tracking should be active based on time
      if (now.isAfter(sixThirtyAM) && now.isBefore(elevenAM)) {
        logToApp("BackgroundService: Auto-start time conditions met. Initiating tracking logic for route: $storedRouteId.");
        await _startTrackingLogic(service);
      } else {
        logToApp("BackgroundService: Auto-start time conditions NOT met. Socket connected, but tracking is paused for route: $storedRouteId.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
        _updateNotification(title: "Service Connected", content: "Ready to start tracking on Route: $storedRouteId");
      }
    } else {
      logToApp("BackgroundService: No route selected on startup. Not connecting socket.");
      service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
      _updateNotification(title: "No Route Selected", content: "Select a route to start tracking.");
      // Initialize socket as null
      currentSocket = null;
      isSocketConnected = false;
    }

    // Start socket health check
    _startSocketHealthCheck(service);
    
    // Listener for when a route is selected
    service.on('routeSelected').listen((event) async {
      final routeIdFromUI = event?['route_id'] as String?;
      logToApp("BackgroundService: Received 'routeSelected' command from UI for route: $routeIdFromUI.");
      
      if (routeIdFromUI == null) {
        logToApp("BackgroundService: Cannot select route: No route provided.");
        return;
      }
      
      // Update SharedPreferences
      await prefs.setString('selectedRoute', routeIdFromUI);
      logToApp("BackgroundService: Updated SharedPreferences with route: $routeIdFromUI");
      
      // Connect socket with the new route
      logToApp("BackgroundService: Connecting socket for newly selected route: $routeIdFromUI");
      await _connectPersistentSocket(service, routeIdFromUI);
      
      // Update UI
      service.invoke('updateUI', {'isTracking': isTracking, 'status': 'Connected (Paused)', 'isAdminConnected': isSocketConnected, 'socketId': currentSocket?.id});
      _updateNotification(title: "Service Connected", content: "Ready to start tracking on Route: $routeIdFromUI");
      logToApp("BackgroundService: Completed route selection for route: $routeIdFromUI");
    });
    
    // Listeners for UI commands
    service.on('startTracking').listen((event) async {
      final routeIdFromUI = event?['route_id'] as String?;
      logToApp("BackgroundService: Received 'startTracking' command from UI for route: $routeIdFromUI.");
      
      // Get the route from the event if provided, otherwise from SharedPreferences
      final String? currentSelectedRouteId = prefs.getString('selectedRoute');
      final String? routeToUse = routeIdFromUI ?? currentSelectedRouteId;
      
      // Check if a route is selected
      if (routeToUse == null) {
        logToApp("BackgroundService: Cannot start tracking: No route selected.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
        _updateNotification(title: "No Route Selected", content: "Select a route to start tracking.");
        return;
      }
      
      // Update active route if provided
      if (routeIdFromUI != null) {
        activeRouteId = routeIdFromUI;
        logToApp("BackgroundService: Updated activeRouteId to: $activeRouteId");
      } else {
        // If no route was provided in the event, use the one from SharedPreferences
        activeRouteId = routeToUse;
        logToApp("BackgroundService: Using route from SharedPreferences: $activeRouteId");
      }

      // Simply start tracking without creating new sockets
      // Note: sendAsUpdate should remain false initially, only start_now should set it to true
      logToApp("BackgroundService: UI startTracking: Starting tracking logic.");
      await _startTrackingLogic(service);
      logToApp("BackgroundService: UI startTracking: Tracking logic initiated.");
      
      // Update SharedPreferences
      await prefs.setBool('location_started', true);
      if (routeIdFromUI != null) {
        await prefs.setString('selectedRoute', routeIdFromUI);
      }
    });

    service.on('stopTracking').listen((event) async {
      logToApp("BackgroundService: Received 'stopTracking' command from UI.");
      
      // Simply stop tracking without disconnecting socket
      sendAsUpdate = false;
      logToApp("BackgroundService: UI stopTracking: Stopping tracking logic.");
      await _stopTrackingLogic(service);
      logToApp("BackgroundService: UI stopTracking: Tracking logic stopped.");
      
      // Update SharedPreferences
      await prefs.setBool('location_started', false);
    });

    // Listener for manual socket reconnection from UI
    service.on('reconnectSocket').listen((event) async {
      logToApp("RECONNECT: Received 'reconnectSocket' command from UI.");
      
      // Get the route from the event if provided, otherwise from SharedPreferences
      final String? routeFromEvent = event?['route_id'] as String?;
      final String? currentSelectedRouteId = prefs.getString('selectedRoute');
      final String? routeToUse = routeFromEvent ?? currentSelectedRouteId;
      
      // Only reconnect if a route is selected
      if (routeToUse != null) {
        logToApp("RECONNECT: Route to use: $routeToUse (from event: $routeFromEvent, from prefs: $currentSelectedRouteId)");
        
        // Reconnect the persistent socket
        await _connectPersistentSocket(service, routeToUse);
        logToApp("RECONNECT: Manual socket reconnection attempt completed for route: $routeToUse.");
      } else {
        logToApp("RECONNECT: No route selected. Cannot reconnect socket.");
        service.invoke('updateUI', {'isTracking': false, 'status': 'No Route Selected', 'isAdminConnected': false, 'socketId': null});
        _updateNotification(title: "No Route Selected", content: "Select a route to connect.");
      }
    });
  });
}
