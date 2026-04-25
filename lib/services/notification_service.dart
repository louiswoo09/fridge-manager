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
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
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

    String body = '';
    if (todayItems > 0 && tomorrowItems > 0) {
      body = '오늘 소비해야 할 식품 $todayItems개, 내일까지인 식품 $tomorrowItems개가 있어요.';
    } else if (todayItems > 0) {
      body = '오늘 소비해야 할 식품이 $todayItems개 있어요. 확인해보세요!';
    } else if (tomorrowItems > 0) {
      body = '내일까지 소비해야 할 식품이 $tomorrowItems개 있어요.';
    }

    if (todayItems == 0 && tomorrowItems == 0) {
      await _notifications.cancel(id: 9999);
      return;
    }
    await _notifications.cancel(id: 9999);

    final base = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
    final scheduledTime = base.isAfter(tz.TZDateTime.now(tz.local))
        ? base
        : base.add(const Duration(days: 1));

    await _notifications.zonedSchedule(
      id: 9999,
      title: '소비기한 임박 알림',
      body: body,
      scheduledDate: scheduledTime,
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

  static Future<void> scheduleAllNotifications(List<Ingredient> items) async {
    await showSummaryNotification(items);
  }
}
