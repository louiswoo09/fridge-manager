import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/ingredient.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _notifications.initialize(settings: settings);

    const channel = AndroidNotificationChannel(
      'expiry_channel',
      '소비기한 알림',
      description: '소비기한 임박 식재료 알림',
      importance: Importance.high,
    );

    await _notifications
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(channel);

await _notifications
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
    ?.requestNotificationsPermission();
  }

  static int _generateId(String id, int offset) {
    return (id.hashCode & 0x7fffffff) + offset;
  }

  static Future<void> showSummaryNotification(List<Ingredient> items) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final todayItems = items.where((item) {
      final expiry = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return expiry.difference(today).inDays == 0;
    }).length;

    final tomorrowItems = items.where((item) {
      final expiry = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return expiry.difference(today).inDays == 1;
    }).length;

    // 테스트 중 주석 처리
    // if (todayItems == 0 && tomorrowItems == 0) return;

    String body = '테스트 알림 - 오늘: $todayItems개, 내일: $tomorrowItems개';

    await _notifications.zonedSchedule(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: '소비기한 임박 알림',
      body: body,
      scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(seconds: 30)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_channel',
          '소비기한 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelNotification(String itemId) async {
    await _notifications.cancel(id: _generateId(itemId, 0));
    await _notifications.cancel(id: _generateId(itemId, 1));
  }

  static Future<void> scheduleAllNotifications(List<Ingredient> items) async {
    await showSummaryNotification(items);
  }
}