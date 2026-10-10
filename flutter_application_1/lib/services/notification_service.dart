import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class InstallmentReminderService {
  static const AndroidNotificationChannel _installmentChannel = AndroidNotificationChannel(
    'installment_reminders',
    'Taksit Hatırlatıcıları',
    description: 'Aylık taksit ve yatırım hatırlatmaları',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();
        await androidImpl.createNotificationChannel(_installmentChannel);
      }
    }

    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  static DateTime _nextReminderDateForDay({
    required int reminderDay,
    required int leadDays,
    int hour = 9,
    int minute = 0,
  }) {
    final now = DateTime.now();
    final safeDay = reminderDay.clamp(1, 31);
    DateTime candidate = DateTime(now.year, now.month, safeDay, hour, minute);

    if (candidate.isBefore(now)) {
      candidate = DateTime(now.year, now.month + 1, safeDay, hour, minute);
    }

    final reminderTarget = candidate.subtract(Duration(days: leadDays));
    if (reminderTarget.isBefore(now)) {
      return candidate;
    }
    return reminderTarget;
  }

  static Future<void> scheduleInvestmentGoalReminder({
    required int id,
    required String title,
    required int reminderDay,
    String? customMessage,
    int hour = 9,
    int minute = 0,
  }) async {
    if (kIsWeb || Platform.isWindows) {
      return;
    }

    final message = (customMessage ?? '').trim().isNotEmpty
        ? customMessage!.trim()
        : '$title için para biriktirmeye devam edin. Yatırım gününüz yaklaştı.';

    final scheduledDate = tz.TZDateTime.from(
      _nextReminderDateForDay(reminderDay: reminderDay, leadDays: 2, hour: hour, minute: minute),
      tz.local,
    );

    await _notifications.zonedSchedule(
      id,
      'Yatırım hatırlatıcı',
      message,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _installmentChannel.id,
          _installmentChannel.name,
          channelDescription: _installmentChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: title,
      matchDateTimeComponents: null,
    );
  }

  static Future<void> scheduleMonthlyBillReminder({
    required int id,
    required String title,
    required int reminderDay,
    String? customMessage,
    int hour = 9,
    int minute = 0,
  }) async {
    if (kIsWeb || Platform.isWindows) {
      return;
    }

    final stages = [
      {'leadDays': 3, 'label': '3 gün önce'},
      {'leadDays': 1, 'label': '1 gün önce'},
      {'leadDays': 0, 'label': 'Ödeme günü'},
    ];

    for (var i = 0; i < stages.length; i++) {
      final leadDays = stages[i]['leadDays'] as int;
      final stageLabel = stages[i]['label'] as String;
      final reminderMessage = (customMessage ?? '').trim().isNotEmpty
          ? customMessage!.trim()
          : '$title ödemesi için ayın ${reminderDay.clamp(1, 31)}. günü yaklaşıyor. Hazırlığınızı kontrol edin.';

      final scheduledDate = tz.TZDateTime.from(
        _nextReminderDateForDay(reminderDay: reminderDay, leadDays: leadDays, hour: hour, minute: minute),
        tz.local,
      );

      final stageMessage = leadDays == 0
          ? '$title için ödeme günü! Bugün ödeme zamanı.'
          : '$title için ödeme $stageLabel. Hatırlatma: ${reminderDay.clamp(1, 31)}. gün.';

      await _notifications.zonedSchedule(
        id + i * 1000,
        'Ödeme hatırlatıcı',
        stageMessage.isNotEmpty ? stageMessage : reminderMessage,
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _installmentChannel.id,
            _installmentChannel.name,
            channelDescription: _installmentChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: title,
        matchDateTimeComponents: null,
      );
    }
  }

  static DateTime nextPaymentDate({
    required DateTime startDate,
    required int paymentDay,
    required int paidInstallments,
  }) {
    final safeDay = paymentDay.clamp(1, 31);
    DateTime candidate = DateTime(startDate.year, startDate.month, safeDay, 9, 0);

    if (candidate.isBefore(startDate)) {
      candidate = DateTime(candidate.year, candidate.month + 1, safeDay, 9, 0);
    }

    final monthOffset = paidInstallments;
    if (monthOffset > 0) {
      candidate = DateTime(
        startDate.year,
        startDate.month + monthOffset,
        safeDay,
        9,
        0,
      );
    }

    return candidate;
  }

  static List<DateTime> upcomingReminderDates({
    required DateTime startDate,
    required int paymentDay,
    required int paidInstallments,
    required int totalInstallments,
  }) {
    final reminders = <DateTime>[];
    final effectiveStart = DateTime(startDate.year, startDate.month, 1);

    for (int i = 1; i <= totalInstallments; i++) {
      final monthIndex = i - 1;
      final month = effectiveStart.month + monthIndex;
      final year = effectiveStart.year + ((month - 1) ~/ 12);
      final monthNumber = ((month - 1) % 12) + 1;
      DateTime dueDate = DateTime(year, monthNumber, paymentDay.clamp(1, 31), 9, 0);
      if (dueDate.isBefore(startDate)) {
        continue;
      }
      if (i <= paidInstallments) {
        continue;
      }
      reminders.add(dueDate.subtract(const Duration(days: 1)));
    }

    return reminders;
  }

  static Future<void> scheduleInstallmentReminder({
    required int id,
    required String title,
    required DateTime startDate,
    required int paymentDay,
    required int paidInstallments,
    required int totalInstallments,
  }) async {
    if (kIsWeb || Platform.isWindows) {
      return;
    }

    final reminders = upcomingReminderDates(
      startDate: startDate,
      paymentDay: paymentDay,
      paidInstallments: paidInstallments,
      totalInstallments: totalInstallments,
    );

    for (final reminder in reminders) {
      final reminderDate = reminder;
      if (reminderDate.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
        continue;
      }

      final scheduledDate = tz.TZDateTime.from(reminderDate, tz.local);

      await _notifications.zonedSchedule(
        id + reminders.indexOf(reminder),
        'Taksit hatırlatıcısı',
        '$title için ödeme günü yaklaşmakta: ${reminder.day}/${reminder.month}',
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _installmentChannel.id,
            _installmentChannel.name,
            channelDescription: _installmentChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: title,
        matchDateTimeComponents: null,
      );
    }
  }
}
