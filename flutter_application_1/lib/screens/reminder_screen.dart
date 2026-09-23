import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  final List<Map<String, dynamic>> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('reminders_v1');

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _reminders.clear();
          for (final item in decoded) {
            if (item is Map) {
              _reminders.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
    });
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminders_v1', jsonEncode(_reminders));
  }

  Future<void> _showAddReminderDialog() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final dayController = TextEditingController(text: '15');
    final noteController = TextEditingController();
    String type = 'Ödeme';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hatırlatıcı ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Tür',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Ödeme',
                    'Yatırım',
                    'Hedef',
                  ].map((label) {
                    return DropdownMenuItem(value: label, child: Text(label));
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      type = value;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Hatırlatma günü (1-31)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (isteğe bağlı)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Not',
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

    if (result != true) return;

    final title = titleController.text.trim();
    final amountText = amountController.text.trim();
    final dayText = dayController.text.trim();
    final note = noteController.text.trim();

    if (title.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Başlık zorunlu.')),
        );
      }
      return;
    }

    final parsedDay = int.tryParse(dayText) ?? 15;
    final parsedAmount = double.tryParse(amountText.replaceAll(',', '.'));
    final reminderDay = parsedDay.clamp(1, 31);

    final reminder = {
      'title': title,
      'type': type,
      'day': reminderDay,
      'amount': parsedAmount ?? 0.0,
      'note': note,
      'enabled': true,
    };

    setState(() {
      _reminders.insert(0, reminder);
    });
    await _saveReminders();

    final message = type == 'Ödeme'
        ? '$title ödemesi için ayın $reminderDay. günü yaklaşıyor. Hazırlığınızı kontrol edin.'
        : '$title için para biriktirmeye devam edin. Yatırım gününüz yaklaştı.';

    await InstallmentReminderService.scheduleMonthlyBillReminder(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      reminderDay: reminderDay,
      customMessage: message,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hatırlatıcı oluşturuldu.')),
      );
    }
  }

  Future<void> _deleteReminder(int index) async {
    setState(() {
      _reminders.removeAt(index);
    });
    await _saveReminders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hatırlatıcılar'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddReminderDialog,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Hatırlatıcı ekle'),
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
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E6B52), Color(0xFF1B4E45)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Yaklaşan hatırlatıcılar',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${_reminders.length} kayıt',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_reminders.isEmpty)
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFCF6),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE9E2D8)),
                            ),
                            child: const Text(
                              'Henüz hatırlatıcı eklenmedi.\nAşağıdaki butondan otomatik bildirim oluşturabilirsin.',
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
                          itemCount: _reminders.length,
                          itemBuilder: (context, index) {
                            final item = _reminders[index];
                            final amount = (item['amount'] as num?)?.toDouble() ?? 0;
                            final title = item['title']?.toString() ?? 'Hatırlatıcı';
                            final day = (item['day'] as num?)?.toInt() ?? 15;
                            final type = item['type']?.toString() ?? 'Ödeme';

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
                                      _iconForType(type),
                                      color: const Color(0xFF2F5646),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF1E2722),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$type · ayın $day. günü',
                                          style: const TextStyle(
                                            color: Color(0xFF68756E),
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (amount > 0) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tutar: ₺${amount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: Color(0xFF3C5E52),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteReminder(index),
                                    icon: const Icon(Icons.delete_outline),
                                    color: const Color(0xFFB6542D),
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
    switch (type) {
      case 'Yatırım':
        return Icons.trending_up_rounded;
      case 'Hedef':
        return Icons.flag_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }
}
