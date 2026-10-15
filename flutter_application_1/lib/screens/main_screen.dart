import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_screen.dart';
import 'upload_screen.dart';
import 'transactions_screen.dart';
import 'plans_screen.dart';
import 'investment_screen.dart';
import 'analytics_screen.dart';
import 'prediction_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class MainScreen extends StatefulWidget {
  final Future<void> Function() onLogout;

  const MainScreen({super.key, required this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_checkCategoryBudgetAlerts());
  }

  Future<void> _checkCategoryBudgetAlerts() async {
    try {
      final user = await ApiService.getCurrentUser();
      final budgets = await ApiService.getCategoryBudgets();
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final userId = user['id']?.toString() ?? 'current';

      for (final rawBudget in budgets) {
        if (rawBudget is! Map<String, dynamic>) continue;
        final budgetId = (rawBudget['id'] as num?)?.toInt();
        final category = rawBudget['category']?.toString() ?? 'Kategori';
        final warningPercent =
            (rawBudget['warning_percent'] as num?)?.toDouble() ?? 80;
        final percentUsed =
            (rawBudget['percent_used'] as num?)?.toDouble() ?? 0;
        if (budgetId == null || percentUsed < warningPercent) continue;

        final exceeded = percentUsed >= 100;
        final stage = exceeded ? 'exceeded' : 'warning';
        final preferenceKey =
            'category_budget_alert_${userId}_${monthKey}_${budgetId}_$stage';
        if (prefs.getBool(preferenceKey) == true) continue;

        final message = exceeded
            ? '$category kategorisindeki aylık limitini aştın.'
            : '$category kategorisindeki aylık limitinin '
                  '%${warningPercent.round()}’ine ulaştın.';
        await InstallmentReminderService.showCategoryBudgetAlert(
          id: budgetId * 2 + (exceeded ? 1 : 0),
          category: category,
          message: message,
        );
        await prefs.setBool(preferenceKey, true);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Kategori bütçeleri kontrol edilemedi: '
              '${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardScreen(),
      const UploadScreen(),
      const TransactionsScreen(),
      const PlansScreen(),
      const InvestmentScreen(),
      const AnalyticsScreen(),
      const PredictionScreen(),
      ProfilScreen(onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: pages[currentIndex],

      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          if (index != currentIndex) {
            unawaited(_checkCategoryBudgetAlerts());
          }
          setState(() {
            currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: "Ana Sayfa",
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_file_outlined),
            selectedIcon: Icon(Icons.upload_file),
            label: "Yükle",
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: "İşlemler",
          ),
          NavigationDestination(
            icon: Icon(Icons.track_changes_outlined),
            selectedIcon: Icon(Icons.track_changes),
            label: "Planlar",
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: "Yatırım",
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: "Analiz",
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: "AI",
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: "Profil",
          ),
        ],
      ),
    );
  }
}