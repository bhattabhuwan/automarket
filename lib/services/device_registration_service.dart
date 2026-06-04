import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Simplified notification permission states used by the app UI.
enum NotificationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unsupported,
}

// Handles notification permission requests and device token registration.
class DeviceRegistrationService {
  DeviceRegistrationService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? FirebaseMessaging.instance;

  static const String _deviceDocIdKey = 'device_registration_doc_id';
  static const String _allUsersTopic = 'allUsers';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _notificationsEnabled = false;
  NotificationPermissionState _permissionState =
      NotificationPermissionState.denied;

  bool get notificationsEnabled => _notificationsEnabled;
  NotificationPermissionState get permissionState => _permissionState;

  // Initializes messaging, requests permission, and subscribes shared topics.
  Future<void> start() async {
    try {
      await _messaging.setAutoInitEnabled(true);
      _permissionState = await _requestNotificationPermission();
      _notificationsEnabled =
          _permissionState == NotificationPermissionState.granted;
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (_notificationsEnabled) {
        await _messaging.subscribeToTopic(_allUsersTopic);
      }
    } catch (error) {
      debugPrint('Notification permission setup failed: $error');
    }

    await registerCurrentDevice(_auth.currentUser);

    _authSubscription ??= _auth.authStateChanges().listen((user) {
      unawaited(registerCurrentDevice(user));
    });
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
      unawaited(registerCurrentDevice(_auth.currentUser, token: token));
    });
  }

  // Stores the current device token in Firestore for backend push delivery.
  Future<void> registerCurrentDevice(User? user, {String? token}) async {
    if (user == null) {
      await _disableCurrentDevice();
      await _unsubscribeFromAllUsersTopic();
      return;
    }
    if (!_notificationsEnabled) {
      debugPrint(
        'Device registration skipped: notifications are not enabled '
        '(${_permissionState.name}).',
      );
      return;
    }

    final fcmToken = token ?? await _messaging.getToken();
    final apnsToken = defaultTargetPlatform == TargetPlatform.iOS
        ? await _messaging.getAPNSToken()
        : null;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        (apnsToken == null || apnsToken.isEmpty)) {
      debugPrint('Device registration skipped: APNs token is not ready yet.');
      return;
    }
    if (fcmToken == null || fcmToken.isEmpty) {
      debugPrint('Device registration skipped: FCM token is empty.');
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    var deviceDocId = preferences.getString(_deviceDocIdKey);
    final devices = _firestore.collection('devices');
    if (deviceDocId == null || deviceDocId.isEmpty) {
      deviceDocId = devices.doc().id;
      await preferences.setString(_deviceDocIdKey, deviceDocId);
    }
    final docRef = devices.doc(deviceDocId);
    await preferences.setString(_deviceDocIdKey, docRef.id);

    final data = <String, Object?>{
      'token': fcmToken,
      'apnsToken': apnsToken,
      'userId': user.uid,
      'userName': _userNameFor(user),
      'platform': _platformLabel(),
      'enabled': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await docRef.set(data, SetOptions(merge: true));
      debugPrint('Registered FCM device token in devices/${docRef.id}');
    } on FirebaseException catch (error) {
      debugPrint(
        'Device registration Firestore error: '
        '${error.code} ${error.message}',
      );
      rethrow;
    }
  }

  Future<void> _disableCurrentDevice() async {
    final preferences = await SharedPreferences.getInstance();
    final savedDocId = preferences.getString(_deviceDocIdKey);
    if (savedDocId == null || savedDocId.isEmpty) return;

    await _firestore.collection('devices').doc(savedDocId).set({
      'enabled': false,
    }, SetOptions(merge: true));
  }

  Future<void> _unsubscribeFromAllUsersTopic() async {
    try {
      await _messaging.unsubscribeFromTopic(_allUsersTopic);
    } catch (error) {
      debugPrint('Topic unsubscribe failed: $error');
    }
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
  }

  String _userNameFor(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email;

    return 'AutoMarket user';
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  Future<NotificationPermissionState> refreshPermissionStatus() async {
    _permissionState = await _currentPermissionState();
    _notificationsEnabled =
        _permissionState == NotificationPermissionState.granted;
    return _permissionState;
  }

  Future<bool> ensureNotificationsEnabled() async {
    final permissionState = await _requestNotificationPermission();
    _permissionState = permissionState;
    _notificationsEnabled =
        permissionState == NotificationPermissionState.granted;

    if (_notificationsEnabled) {
      await _messaging.subscribeToTopic(_allUsersTopic);
      await registerCurrentDevice(_auth.currentUser);
      return true;
    }

    return false;
  }

  Future<bool> openNotificationSettings() async {
    return openAppSettings();
  }

  Future<NotificationPermissionState> _requestNotificationPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final firebaseState = _mapAuthorizationStatus(
      settings.authorizationStatus,
    );
    if (firebaseState == NotificationPermissionState.granted) {
      return firebaseState;
    }

    return _currentPermissionState();
  }

  Future<NotificationPermissionState> _currentPermissionState() async {
    if (kIsWeb) {
      return _notificationsEnabled
          ? NotificationPermissionState.granted
          : NotificationPermissionState.unsupported;
    }

    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return NotificationPermissionState.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return NotificationPermissionState.permanentlyDenied;
    }
    return NotificationPermissionState.denied;
  }

  NotificationPermissionState _mapAuthorizationStatus(
    AuthorizationStatus status,
  ) {
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      return NotificationPermissionState.granted;
    }
    if (status == AuthorizationStatus.denied) {
      return NotificationPermissionState.denied;
    }
    return NotificationPermissionState.unsupported;
  }
}
