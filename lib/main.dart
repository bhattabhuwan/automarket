import 'dart:async';

import 'package:automarket/firebase_options.dart';
import 'package:automarket/screens/auth_screen.dart';
import 'package:automarket/screens/home_screen.dart';
import 'package:automarket/services/auth_service.dart';
import 'package:automarket/services/device_registration_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Shared notification channel used for Android system notifications.
const AndroidNotificationChannel marketplaceNotificationChannel =
    AndroidNotificationChannel(
      'marketplace_listing_alerts',
      'Marketplace listing alerts',
      description: 'Notifications for new AutoMarket listings.',
      importance: Importance.high,
      playSound: true,
    );

// Local notifications are used to mirror push messages while the app is active.
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Global messenger lets notification messages appear above any screen.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
// Central service for FCM permission, token, and device registration.
final DeviceRegistrationService deviceRegistrationService =
    DeviceRegistrationService();

// Handles push delivery when Firebase wakes the app in the background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _showSystemNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register background handling before the widget tree starts.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _configureOsNotifications();
  _listenForPushMessages();

  runApp(const MyApp());

  // Start token registration without blocking app startup.
  unawaited(
    deviceRegistrationService.start().catchError((error, stackTrace) {
      debugPrint('Device registration failed: $error');
    }),
  );
}

// Configures local notification behavior for Android and iOS.
Future<void> _configureOsNotifications() async {
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    ),
  );
  await localNotificationsPlugin.initialize(settings: initializationSettings);

  await localNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(marketplaceNotificationChannel);

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
}

// Wires all push entry points: foreground, resumed, and cold start.
void _listenForPushMessages() {
  FirebaseMessaging.onMessage.listen((message) {
    unawaited(_handleIncomingMessage(message, showSnackBar: false));
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    unawaited(_handleIncomingMessage(message));
  });

  unawaited(
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        return _handleIncomingMessage(message);
      }
    }),
  );
}

// Shows a system notification and optionally an in-app message.
Future<void> _handleIncomingMessage(
  RemoteMessage message, {
  bool showSnackBar = true,
}) async {
  await _showSystemNotification(message);
  if (showSnackBar) {
    _showPushMessage(message);
  }
}

Future<void> _showSystemNotification(RemoteMessage message) async {
  final notification = message.notification;
  final title = notification?.title ??
      message.data['title'] ??
      'New listing added';
  final body = notification?.body ??
      message.data['body'] ??
      'A new item was added to the marketplace.';

  const androidDetails = AndroidNotificationDetails(
    'marketplace_listing_alerts',
    'Marketplace listing alerts',
    channelDescription: 'Notifications for new AutoMarket listings.',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    channelShowBadge: true,
    sound: RawResourceAndroidNotificationSound('notification'),
  );
  const notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    ),
  );

  await localNotificationsPlugin.show(
    id: message.messageId.hashCode,
    title: title,
    body: body,
    notificationDetails: notificationDetails,
    payload: message.data['listingId']?.toString(),
  );
}

void _showPushMessage(RemoteMessage message) {
  final notification = message.notification;
  final title = notification?.title ?? 'New listing added';
  final body = notification?.body ?? 'A new item was added to the marketplace.';

  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('$title\n$body'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AutoMarket',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5A4),
          brightness: Brightness.light,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: AuthService().authStateChanges,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            final user = snapshot.data;
            if (user == null) {
              return const AuthScreen();
            }
            return AuthenticatedAppShell(user: user, child: const HomeScreen());
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}

class AuthenticatedAppShell extends StatefulWidget {
  const AuthenticatedAppShell({
    super.key,
    required this.user,
    required this.child,
  });

  final User user;
  final Widget child;

  @override
  State<AuthenticatedAppShell> createState() => _AuthenticatedAppShellState();
}

class _AuthenticatedAppShellState extends State<AuthenticatedAppShell> {
  bool _notificationPromptShown = false;

  @override
  void initState() {
    super.initState();
    _registerDevice();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showNotificationPermissionPromptIfNeeded());
    });
  }

  @override
  void didUpdateWidget(covariant AuthenticatedAppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _registerDevice();
    }
  }

  void _registerDevice() {
    unawaited(
      deviceRegistrationService.registerCurrentDevice(widget.user).catchError((
        error,
        stackTrace,
      ) {
        debugPrint('Device registration failed: $error');
      }),
    );
  }

  Future<void> _showNotificationPermissionPromptIfNeeded() async {
    final permissionState =
        await deviceRegistrationService.refreshPermissionStatus();
    if (!mounted || _notificationPromptShown) return;
    if (permissionState == NotificationPermissionState.granted ||
        permissionState == NotificationPermissionState.unsupported) {
      return;
    }

    _notificationPromptShown = true;
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable notifications'),
          content: const Text(
            'Notifications are turned off, so messages may not appear when the app is closed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await deviceRegistrationService.openNotificationSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListingNotificationWatcher(child: widget.child);
  }
}

class ListingNotificationWatcher extends StatefulWidget {
  const ListingNotificationWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<ListingNotificationWatcher> createState() =>
      _ListingNotificationWatcherState();
}

class _ListingNotificationWatcherState
    extends State<ListingNotificationWatcher> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final Set<String> _knownListingIds = <String>{};
  bool _hasLoadedInitialListings = false;

  @override
  void initState() {
    super.initState();
    _subscription = FirebaseFirestore.instance
        .collection('listings')
        .snapshots()
        .listen(_handleListingsSnapshot);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleListingsSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!_hasLoadedInitialListings) {
      _knownListingIds.addAll(snapshot.docs.map((doc) => doc.id));
      _hasLoadedInitialListings = true;
      return;
    }

    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      if (!_knownListingIds.add(change.doc.id)) continue;

      final listing = change.doc.data() ?? <String, dynamic>{};
      if (listing['isActive'] == false) continue;

      _showListingNotification(listing);
    }
  }

  void _showListingNotification(Map<String, dynamic> listing) {
    final title = _readText(listing['title'], 'New listing added');
    final price = _readText(listing['priceLabel'], '');
    final location = _readText(listing['location'], '');
    final bodyParts = [price, location].where((value) => value.isNotEmpty);
    final body = bodyParts.isEmpty
        ? 'A new item was added to the marketplace.'
        : bodyParts.join(' - ');

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  String _readText(Object? value, String fallback) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
