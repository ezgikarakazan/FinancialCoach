import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/notification_service.dart';

void main() {
  group('InstallmentReminderService', () {
    test('next payment date is built from the selected payment day', () {
      final nextDate = InstallmentReminderService.nextPaymentDate(
        startDate: DateTime(2026, 1, 5),
        paymentDay: 10,
        paidInstallments: 0,
      );

      expect(nextDate, DateTime(2026, 1, 10, 9, 0));
    });

    test('reminder list contains dates before the payment day', () {
      final reminders = InstallmentReminderService.upcomingReminderDates(
        startDate: DateTime(2026, 1, 5),
        paymentDay: 10,
        paidInstallments: 0,
        totalInstallments: 3,
      );

      expect(reminders.length, 3);
      expect(reminders.first, DateTime(2026, 1, 9, 9, 0));
      expect(reminders.last, DateTime(2026, 3, 9, 9, 0));
    });
  });
}
