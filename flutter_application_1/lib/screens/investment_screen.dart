import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';

class InvestmentScreen extends StatefulWidget {
  const InvestmentScreen({super.key});

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen> {
  final List<Map<String, dynamic>> _investments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInvestments();
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

  double get _totalInvested {
    return _investments.fold<double>(0, (sum, item) {
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      return sum + amount;
    });
  }

  Future<void> _showAddInvestmentDialog() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final startDayController = TextEditingController(text: '1');
    final endDayController = TextEditingController(text: '31');
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
                      items: const [
                        'Hisse',
                        'Fon',
                        'Altın',
                        'Kripto',
                        'Döviz',
                        'Diğer',
                      ].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startDayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Ayın başlangıç günü',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: endDayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Ayın bitiş günü',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reminderDayController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hatırlatma günü (1-31)',
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
                          labelText: 'Tarih',
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
    final startDayText = startDayController.text.trim();
    final endDayText = endDayController.text.trim();
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

    final parsedStartDay = int.tryParse(startDayText) ?? 1;
    final parsedEndDay = int.tryParse(endDayText) ?? 31;
    final parsedReminderDay = int.tryParse(reminderDayText) ?? parsedEndDay;
    final normalizedStart = parsedStartDay.clamp(1, 31);
    final normalizedEnd = parsedEndDay.clamp(1, 31);
    final normalizedReminderDay = parsedReminderDay.clamp(1, 31);

    final entry = {
      'title': title,
      'type': selectedType,
      'amount': parsedAmount,
      'date': selectedDate.toIso8601String(),
      'start_day': normalizedStart,
      'end_day': normalizedEnd,
      'reminder_day': normalizedReminderDay,
      'notes': notes,
    };

    setState(() {
      _investments.insert(0, entry);
    });
    await _saveInvestments();

    final reminderMessage = title.toLowerCase().contains('ev')
        ? 'Ev almak için para biriktirmeye devam edin. Yatırım gününüz yaklaştı.'
        : '$title için yatırım gününüz yaklaşıyor. Birikiminize devam edin.';

    await InstallmentReminderService.scheduleInvestmentGoalReminder(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      reminderDay: normalizedReminderDay,
      customMessage: reminderMessage,
    );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yatırımlarım'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddInvestmentDialog,
        icon: const Icon(Icons.add),
        label: const Text('Yatırım ekle'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '₺${_totalInvested.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_investments.length} yatırım kaydı',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Yatırım listem',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 14),
                    if (_investments.isEmpty)
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFCF6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFE9E2D8)),
                            ),
                            child: const Text(
                              'Henüz yatırım kaydı yok.\nAşağıdaki + butonundan ilk yatırımını ekleyebilirsin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF68756E),
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _investments.length,
                          itemBuilder: (context, index) {
                            final item = _investments[index];
                            final amount = (item['amount'] as num?)?.toDouble() ?? 0;
                            final date = DateTime.tryParse(item['date']?.toString() ?? '') ?? DateTime.now();
                            final startDay = (item['start_day'] as num?)?.toInt() ?? 1;
                            final endDay = (item['end_day'] as num?)?.toInt() ?? 31;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFCF6),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: const Color(0xFFE9E2D8)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFE7EFEA),
                                    child: Icon(
                                      _iconForType(item['type']?.toString() ?? 'Diğer'),
                                      color: const Color(0xFF2F5646),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['title']?.toString() ?? 'Yatırım',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1E2722),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${item['type'] ?? 'Diğer'} · ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                                          style: const TextStyle(
                                            color: Color(0xFF68756E),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Eklenme aralığı: ayın $startDay-$endDay. günü',
                                          style: const TextStyle(
                                            color: Color(0xFF3C5E52),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if ((item['notes'] ?? '').toString().trim().isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            item['notes'].toString(),
                                            style: const TextStyle(
                                              color: Color(0xFF58675F),
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₺${amount.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Color(0xFF1E6B52),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      IconButton(
                                        onPressed: () => _deleteInvestment(index),
                                        icon: const Icon(Icons.delete_outline),
                                        color: const Color(0xFFB6542D),
                                        tooltip: 'Sil',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'hisse':
        return Icons.trending_up_rounded;
      case 'fon':
        return Icons.pie_chart_rounded;
      case 'altın':
        return Icons.currency_bitcoin_rounded;
      case 'kripto':
        return Icons.currency_bitcoin_rounded;
      case 'döviz':
        return Icons.attach_money_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }
}
