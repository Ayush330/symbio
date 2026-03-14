import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../data/repositories/auth_repository.dart';

class NotificationService {
  final AuthRepository authRepository;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  NotificationService({required this.authRepository});

  Future<void> initialize() async {
    // 1. Request permissions (especially for iOS and Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Get the device token and report it to the backend
    String? token = await _fcm.getToken();
    if (token != null) {
      print('FCM Token: $token');
      await authRepository.updateFCMToken(token);
    }

    // 3. Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      authRepository.updateFCMToken(newToken);
    });

    // 4. Setup Android Notification Channel for foreground alerts
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'High Importance Notifications', // title
      description: 'This channel is used for important notifications.', // description
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 5. Initialize local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    // 6. Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _localNotifications.show(
          message.hashCode,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    // 7. Handle notification clicks when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification clicked! Data: ${message.data}');
      // Navigation logic could go here
    });
  }
}
