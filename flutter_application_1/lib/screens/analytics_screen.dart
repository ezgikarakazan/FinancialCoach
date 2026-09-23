import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../widgets/expense_pie_chart.dart';
import '../widgets/trend_line_chart.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final List<Map<String, dynamic>> _investments = [];
  final List<Map<String, dynamic>> _investmentHistory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInvestments();
    _loadInvestmentHistory();
  }

  Future<void> _loadInvestments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('investments_v1');

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _investments.clear();
          for (final item in decoded) {
            if (item is Map) {
              _investments.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    });
  }

  Future<void> _saveInvestments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('investments_v1', jsonEncode(_investments));
  }

  Future<void> _loadInvestmentHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('investment_history_v1');

    if (!mounted) return;

    setState(() {
      _investmentHistory.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              _investmentHistory.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    });
  }

  Future<void> _saveInvestmentHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('investment_history_v1', jsonEncode(_investmentHistory));
  }

  Map<String, dynamic>? _currentMonthInvestmentRecord() {
    final currentMonthKey = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    for (final item in _investmentHistory) {
      final monthKey = item['month_key']?.toString();
      if (monthKey == currentMonthKey) {
        return item;
      }
    }
    return null;
  }

  double get _totalInvested {
    return _investments.fold<double>(0, (sum, item) {
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      return sum + amount;
    });
  }

  Future<void> _showAddInvestmentDialog() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final reminderDayController = TextEditingController(text: '15');
    final notesController = TextEditingController();
    String selectedType = 'Hisse';
    DateTime selectedDate = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Yatırım ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Yatırım adı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Tür',
                        border: OutlineInputBorder(),
                      ),
                      items: const ['Hisse', 'Fon', 'Altın', 'Kripto', 'Döviz', 'Diğer']
                          .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tutar (₺)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reminderDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Her ayın kaçında yatırım yaparsın? (1-31)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Başlangıç tarihi',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Not (isteğe bağlı)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;

    final title = titleController.text.trim();
    final amountText = amountController.text.trim();
    final reminderDayText = reminderDayController.text.trim();
    final notes = notesController.text.trim();

    if (title.isEmpty || amountText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yatırım adı ve tutar zorunlu.')),
        );
      }
      return;
    }

    final parsedAmount = double.tryParse(amountText.replaceAll(',', '.'));
    if (parsedAmount == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçerli bir tutar gir.')),
        );
      }
      return;
    }

    final reminderDay = int.tryParse(reminderDayText) ?? 15;
    final normalizedReminderDay = reminderDay.clamp(1, 31);

    final entry = {
      'title': title,
      'type': selectedType,
      'amount': parsedAmount,
      'date': selectedDate.toIso8601String(),
      'reminder_day': normalizedReminderDay,
      'notes': notes,
    };

    setState(() {
      _investments.insert(0, entry);
    });
    await _saveInvestments();

    final monthKey = '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}';
    final existingIndex = _investmentHistory.indexWhere((item) => item['month_key'] == monthKey);
    if (existingIndex >= 0) {
      final currentAmount = (_investmentHistory[existingIndex]['amount'] as num?)?.toDouble() ?? 0;
      _investmentHistory[existingIndex]['amount'] = currentAmount + parsedAmount;
      _investmentHistory[existingIndex]['last_date'] = selectedDate.toIso8601String();
      _investmentHistory[existingIndex]['title'] = title;
    } else {
      _investmentHistory.insert(0, {
        'month_key': monthKey,
        'title': title,
        'amount': parsedAmount,
        'last_date': selectedDate.toIso8601String(),
      });
    }
    await _saveInvestmentHistory();

    final reminderMessage = '$title yatırımını $normalizedReminderDay. gün hatırlatıcıyla takip et. Birikim planına sadık kal.';

    await InstallmentReminderService.scheduleInvestmentGoalReminder(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      reminderDay: normalizedReminderDay,
      customMessage: reminderMessage,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yatırım hatırlatıcı eklendi.')),
      );
    }
  }

  Future<void> _deleteInvestment(int index) async {
    setState(() {
      _investments.removeAt(index);
    });
    await _saveInvestments();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisMonthRecord = _currentMonthInvestmentRecord();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analiz & yatırım',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Yatırım planları ve harcama analizi tek ekranda görünür.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E6B52), Color(0xFF265E4F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toplam yatırım',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '₺${_totalInvested.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.business_center_rounded, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${_investments.length} yatırım kaydı',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE0EAE4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      thisMonthRecord != null ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      color: thisMonthRecord != null ? const Color(0xFF1E6B52) : const Color(0xFFC96B3B),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        thisMonthRecord != null
                            ? 'Bu ay yatırım yapıldı • ₺${((thisMonthRecord['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'
                            : 'Bu ay yatırım yapılmadı. Hatırlatıcıya göre takip edebilirsin.',
                        style: const TextStyle(
                          color: Color(0xFF1E2722),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _showAddInvestmentDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Yatırım ekle'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Yatırım listesi',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_investments.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE9E2D8)),
                  ),
                  child: const Text(
                    'Henüz yatırım kaydı yok. Yatırım hedefini ekleyerek her ay hangi günde yatırım yaptığını tanımlayabilirsin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF68756E), height: 1.5),
                  ),
                )
              else
                ..._investments.map((item) {
                  final title = item['title']?.toString() ?? 'Yatırım';
                  final type = item['type']?.toString() ?? 'Hisse';
                  final amount = (item['amount'] as num?)?.toDouble() ?? 0;
                  final reminderDay = (item['reminder_day'] as num?)?.toInt() ?? 15;
                  final notes = item['notes']?.toString() ?? '';
                  final icon = _iconForType(type);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF6),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE9E2D8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFFE7EFEA),
                          child: Icon(icon, color: const Color(0xFF2F5646)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E2722),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$type • her ayın $reminderDay. günü',
                                style: const TextStyle(
                                  color: Color(0xFF68756E),
                                  fontSize: 12,
                                ),
                              ),
                              if (notes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  notes,
                                  style: const TextStyle(
                                    color: Color(0xFF5E615B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₺${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E6B52),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deleteInvestment(_investments.indexOf(item)),
                              icon: const Icon(Icons.delete_outline),
                              color: const Color(0xFFB6542D),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              if (_investmentHistory.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Geçmiş yatırım takibi',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                ..._investmentHistory.take(6).map((item) {
                  final monthKey = item['month_key']?.toString() ?? '-';
                  final amount = (item['amount'] as num?)?.toDouble() ?? 0;
                  final title = item['title']?.toString() ?? 'Yatırım';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE9E2D8)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7EFEA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF2F5646)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E2722),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                monthKey,
                                style: const TextStyle(
                                  color: Color(0xFF68756E),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₺${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E6B52),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 28),
              Text(
                'Kategori dağılımı',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: ApiService.getAnalytics(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _AnalyticsLoadingState();
                  }

                  if (snapshot.hasError) {
                    return const _AnalyticsMessageState(
                      icon: Icons.analytics_outlined,
                      title: 'Analiz verisi alınamadı',
                      subtitle: 'Backend bağlantısını veya analytics endpoint çıktısını kontrol et.',
                    );
                  }

                  final data = snapshot.data ?? {};
                  final categories = (data['categories'] as List<dynamic>? ?? []);
                  final monthly = (data['monthly_expenses'] as List<dynamic>? ?? []);

                  if (categories.isEmpty) {
                    return const _AnalyticsMessageCard(
                      title: 'Henüz kategori verisi yok',
                      subtitle: 'Negatif tutarlı işlemler eklendiğinde burada dağılım oluşacak.',
                    );
                  }

                  final totalExpense = categories.fold<double>(
                    0,
                    (sum, item) => sum + (((item as Map<String, dynamic>)['amount'] as num?)?.toDouble() ?? 0),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFCF6),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFE7DED2)),
                        ),
                        child: ExpensePieChart(categories: categories),
                      ),
                      const SizedBox(height: 28),
                      ...categories.map((item) {
                        final map = item as Map<String, dynamic>;
                        final categoryName = map['name']?.toString() ?? '-';
                        final amount = (map['amount'] as num?)?.toDouble() ?? 0;
                        final share = totalExpense > 0 ? (amount / totalExpense) * 100 : 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CategoryDetailCard(
                            title: categoryName,
                            amount: '₺${amount.toStringAsFixed(2)}',
                            share: '%${share.toStringAsFixed(1)}',
                            color: _getCategoryColor(categoryName),
                          ),
                        );
                      }),
                      const SizedBox(height: 28),
                      Text(
                        'Aylık trend',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      if (monthly.isEmpty)
                        const _AnalyticsMessageCard(
                          title: 'Trend için yeterli veri yok',
                          subtitle: 'Farklı tarihlerde gider eklediğinde aylık akış burada çizilecek.',
                        )
                      else
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF6),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: const Color(0xFFE7DED2)),
                          ),
                          child: TrendLineChart(monthlyExpenses: monthly),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Altın':
        return Icons.currency_bitcoin_rounded;
      case 'Fon':
        return Icons.account_balance_wallet_rounded;
      case 'Kripto':
        return Icons.monetization_on_rounded;
      case 'Döviz':
        return Icons.currency_exchange_rounded;
      default:
        return Icons.business_center_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    final colors = {
      'Market': const Color(0xFF1E6B52),
      'Yeme İçme': const Color(0xFFC96B3B),
      'Ulaşım': const Color(0xFF3C6E71),
      'Eğlence': const Color(0xFF9C6ADE),
      'Alışveriş': const Color(0xFFD96C8A),
      'Diger': const Color(0xFF7B887F),
      'Diğer': const Color(0xFF7B887F),
    };
    return colors[category] ?? const Color(0xFF5C7C6D);
  }
}

class _CategoryDetailCard extends StatelessWidget {
  final String title;
  final String amount;
  final String share;
  final Color color;

  const _CategoryDetailCard({
    required this.title,
    required this.amount,
    required this.share,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8E0D2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2722),
                  ),
                ),
              ),
              Text(
                amount,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: (double.tryParse(share.replaceAll('%', '')) ?? 0) / 100,
                    backgroundColor: const Color(0xFFEFE9DD),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                share,
                style: const TextStyle(
                  color: Color(0xFF68756E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalyticsMessageCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AnalyticsMessageCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7DED2)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.insights_rounded,
            size: 40,
            color: Color(0xFF7B887F),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E2722),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64716B),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsMessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AnalyticsMessageState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE9DED4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 42,
                  color: const Color(0xFFC96B3B),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF5B6761),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsLoadingState extends StatelessWidget {
  const _AnalyticsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}