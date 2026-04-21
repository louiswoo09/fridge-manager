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

  static int _generateId(String id, int offset) {
    return (id.hashCode & 0x7fffffff) + offset;
  }

  static DateTime _at9am(DateTime date) {
    return DateTime(date.year, date.month, date.day, 9);
  }

  static Future<void> scheduleExpiryNotification(Ingredient item) async {
    final now = DateTime.now();
    final expiryDate = DateTime(
      item.expirationDate.year,
      item.expirationDate.month,
      item.expirationDate.day,
    );
    final d3 = expiryDate.subtract(const Duration(days: 3));
    final d1 = expiryDate.subtract(const Duration(days: 1));
    final d3Time = _at9am(d3);
    final d1Time = _at9am(d1);

    if (d3Time.isAfter(now)) {
      await _schedule(
        id: _generateId(item.id, 0),
        title: '소비기한 임박',
        body: '${item.name} 소비기한이 3일 남았어요.',
        scheduledDate: d3Time,
      );
    }

    if (d1Time.isAfter(now)) {
      await _schedule(
        id: _generateId(item.id, 1),
        title: '소비기한 임박',
        body: '${item.name} 소비기한이 내일까지예요.',
        scheduledDate: d1Time,
      );
    }
  }

  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (scheduledDate.isBefore(DateTime.now())) return;

    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'expiry_channel',
          '소비기한 알림',
          channelDescription: '소비기한 임박 식재료 알림',
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
    await Future.wait(
      items.map((item) async {
        await cancelNotification(item.id);
        await scheduleExpiryNotification(item);
      }),
    );
  }
}
