import 'package:automarket/firebase_options.dart';
import 'package:automarket/screens/auth_screen.dart';
import 'package:automarket/screens/home_screen.dart';
import 'package:automarket/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const String newMarketplaceDevicesTopic = 'marketplace-new-devices';
const String legacyMarketplaceDealsTopic = 'marketplace-deals';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _setupMessaging() async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );
  await messaging.subscribeToTopic(newMarketplaceDevicesTopic);
  await messaging.subscribeToTopic(legacyMarketplaceDealsTopic);

  if (kDebugMode) {
    final token = await messaging.getToken();
    debugPrint('FCM token: ${token ?? 'not available'}');
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      debugPrint('FCM token refreshed: $token');
    });
  }

  FirebaseMessaging.onMessage.listen((message) {
    _showMarketplaceNotification(message);
  });

  FirebaseMessaging.onMessageOpenedApp.listen(_showMarketplaceNotification);

  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMarketplaceNotification(initialMessage);
    });
  }
}

void _showMarketplaceNotification(RemoteMessage message) {
  final notification = message.notification;
  final title = notification?.title ?? 'New device uploaded';
  final body =
      notification?.body ?? 'A new device was added to the marketplace.';

  scaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('$title\n$body'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _setupMessaging();
  runApp(const MyApp());
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
            return const HomeScreen();
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }
}
