import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<dynamic>> _plansFuture;
  final List<Map<String, dynamic>> _reminders = [];
  bool _loadingReminders = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('reminders_v1');

    if (!mounted) return;

    setState(() {
      _loadingReminders = false;
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _reminders.clear();
          for (final item in decoded) {
            if (item is Map) {
              final reminder = Map<String, dynamic>.from(item);
              if (reminder['time'] == null || reminder['time'].toString().trim().isEmpty) {
                reminder['time'] = '09:00';
              }
              _reminders.add(reminder);
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
    final timeController = TextEditingController(text: '09:00');
    final noteController = TextEditingController();
    String type = 'Ödeme';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Özel hatırlatıcı ekle'),
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
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: 'Tür',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['Ödeme', 'Yatırım', 'Hedef']
                      .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                      .toList(),
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
                  controller: timeController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Saat (SS:DD)',
                    border: OutlineInputBorder(),
                    hintText: '09:00',
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
    final dayText = dayController.text.trim();
    final timeText = timeController.text.trim();
    final amountText = amountController.text.trim();
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

    final timeParts = timeText.split(':');
    final hour = int.tryParse(timeParts.first) ?? 9;
    final minute = int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0;
    final safeHour = hour.clamp(0, 23);
    final safeMinute = minute.clamp(0, 59);

    final reminder = {
      'title': title,
      'type': type,
      'day': reminderDay,
      'time': '${safeHour.toString().padLeft(2, '0')}:${safeMinute.toString().padLeft(2, '0')}',
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

    final notificationSupported = !kIsWeb && !Platform.isWindows;
    if (notificationSupported) {
      await InstallmentReminderService.scheduleMonthlyBillReminder(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: title,
        reminderDay: reminderDay,
        hour: safeHour,
        minute: safeMinute,
        customMessage: message,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notificationSupported
                ? 'Hatırlatıcı oluşturuldu.'
                : 'Hatırlatıcı kaydedildi. Web tarayıcısında sistem bildirimi gelmez; Android/iOS cihazda görünür.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteReminder(int index) async {
    setState(() {
      _reminders.removeAt(index);
    });
    await _saveReminders();
  }

  Future<void> _refresh() async {
    final plansFuture = ApiService.getPlans();

    if (mounted) {
      setState(() {
        _plansFuture = plansFuture;
      });
    } else {
      _plansFuture = plansFuture;
    }

    final plans = await plansFuture;
    for (final plan in plans) {
      final planMap = plan as Map<String, dynamic>;
      if (planMap['plan_type'] == 'installment') {
        final paymentDay = (planMap['payment_day'] as num?)?.toInt() ?? 1;
        final planName = planMap['name']?.toString() ?? 'Taksit';
        await InstallmentReminderService.scheduleMonthlyBillReminder(
          id: planMap['id'] as int,
          title: planName,
          reminderDay: paymentDay,
          customMessage: '$planName ödemesi için ayın $paymentDay. günü yaklaşıyor. Hazırlığınızı kontrol edin.',
        );
      }
    }
  }

  Future<void> _createPlan() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreatePlanDialog(),
    );
    if (created == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _addEntry(Map<String, dynamic> plan) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _AddPlanEntryDialog(plan: plan),
    );
    if (updated == true && mounted) {
      await _refresh();
    }
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Planı sil'),
        content: Text('“${plan['name']}” planı ve içindeki kayıtlar silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deletePlan(plan['id'] as int);
      if (mounted) {
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _openPlanDetail(Map<String, dynamic> plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlanDetailPage(
          plan: plan,
          onRefresh: _refresh,
          onDeletePlan: () => _deletePlan(plan),
          onAddEntry: () => _addEntry(plan),
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<dynamic>>(
          future: _plansFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Planlar yüklenemedi: ${snapshot.error}'));
            }
            final plans = snapshot.data ?? [];
            return RefreshIndicator(
              onRefresh: () async => setState(_refresh),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                children: [
                  Text('Planlar & Hatırlatıcılar', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Planları yönet, hatırlatıcıları saatli takip et ve her bir bütçeyi ayrı ayrı izle.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE8DFD3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hatırlatıcılar',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E2722),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _loadingReminders
                                    ? 'Yükleniyor...'
                                    : _reminders.isEmpty
                                        ? 'Kayıtlı hatırlatıcı yok.'
                                        : '${_reminders.length} hatırlatıcı aktif',
                                style: const TextStyle(
                                  color: Color(0xFF68756E),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _showAddReminderDialog,
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Ekle'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_loadingReminders)
                    if (_reminders.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF6F9F8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE4EAE7)),
                        ),
                        child: const Text(
                          'Ödeme, kira, sigorta veya hedef tarihin için saatli hatırlatıcı ekleyebilirsin.',
                          style: TextStyle(color: Color(0xFF5F6F68), height: 1.5),
                        ),
                      )
                    else
                      ..._reminders.asMap().entries.map((entry) {
                        final index = entry.key;
                        final reminder = entry.value;
                        final title = reminder['title']?.toString() ?? 'Hatırlatıcı';
                        final type = reminder['type']?.toString() ?? 'Ödeme';
                        final day = (reminder['day'] as num?)?.toInt() ?? 15;
                        final time = reminder['time']?.toString() ?? '09:00';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8DFD3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFE7EFEA),
                                child: Icon(
                                  type == 'Yatırım'
                                      ? Icons.trending_up_rounded
                                      : type == 'Hedef'
                                          ? Icons.flag_rounded
                                          : Icons.receipt_long_rounded,
                                  color: const Color(0xFF2F5646),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E2722),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$type • ayın $day. günü • $time',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF68756E),
                                      ),
                                    ),
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
                      }),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Planlar',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (plans.isNotEmpty)
                          Text(
                            '${plans.length} plan',
                            style: const TextStyle(color: Color(0xFF68756E), fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (plans.isEmpty)
                    const _EmptyPlans()
                  else
                    ...plans.map(
                      (rawPlan) => _PlanCard(
                        plan: rawPlan as Map<String, dynamic>,
                        onOpenDetail: () => _openPlanDetail(rawPlan),
                        onAddEntry: () => _addEntry(rawPlan),
                        onDelete: () => _deletePlan(rawPlan),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPlan,
        icon: const Icon(Icons.add),
        label: const Text('Yeni plan'),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final VoidCallback onOpenDetail;
  final VoidCallback onAddEntry;
  final VoidCallback onDelete;

  const _PlanCard({
    required this.plan,
    required this.onOpenDetail,
    required this.onAddEntry,
    required this.onDelete,
  });

  String _money(dynamic value) => '₺${(value as num? ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final isInstallment = plan['plan_type'] == 'installment';
    final notes = (plan['notes'] as String? ?? '').trim();
    final target = (plan['target_amount'] as num? ?? 0).toDouble();
    final spent = (plan['spent_amount'] as num? ?? 0).toDouble();
    final progress = target <= 0 ? 0.0 : (spent / target).clamp(0.0, 1.0);
    final paid = plan['paid_installments'] as num? ?? 0;
    final total = plan['total_installments'] as num? ?? 0;
    final color = isInstallment ? const Color(0xFF1E6B52) : const Color(0xFFC96B3B);

    return InkWell(
      onTap: onOpenDetail,
      borderRadius: BorderRadius.circular(18),
      child: Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE8DFD3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(isInstallment ? Icons.receipt_long : Icons.savings_outlined, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      plan['name'].toString(),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onOpenDetail,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Detay'),
                  ),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  notes,
                  style: const TextStyle(color: Color(0xFF5F6F68), fontSize: 13, height: 1.5),
                ),
              ],
              const SizedBox(height: 18),
              if (isInstallment) ...[
                Text('$paid / $total taksit ödendi', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('${plan['remaining_installments']} taksit kaldı • Aylık ${_money(plan['monthly_amount'])}', style: const TextStyle(color: Color(0xFF7B887F))),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: total == 0 ? 0 : (paid / total).clamp(0, 1).toDouble(), color: color, backgroundColor: const Color(0xFFE8DFD3)),
              ] else ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Harcanan ${_money(spent)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Kalan ${_money(plan['remaining_amount'])}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: progress, color: color, backgroundColor: const Color(0xFFE8DFD3)),
              ],
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onAddEntry,
                  icon: Icon(isInstallment ? Icons.check : Icons.add),
                  label: Text(isInstallment ? 'Taksit ödendi' : 'Harcama ekle'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanDetailPage extends StatelessWidget {
  final Map<String, dynamic> plan;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onDeletePlan;
  final Future<void> Function() onAddEntry;

  const _PlanDetailPage({
    required this.plan,
    required this.onRefresh,
    required this.onDeletePlan,
    required this.onAddEntry,
  });

  String _money(dynamic value) => '₺${(value as num? ?? 0).toStringAsFixed(2)}';

  String _date(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 10) return text.substring(0, 10).split('-').reversed.join('.');
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final entries = (plan['entries'] as List<dynamic>? ?? const <dynamic>[]).cast<Map<String, dynamic>>();
    final isInstallment = plan['plan_type'] == 'installment';
    final notes = (plan['notes'] as String? ?? '').trim();
    final color = isInstallment ? const Color(0xFF1E6B52) : const Color(0xFFC96B3B);

    return Scaffold(
      appBar: AppBar(
        title: Text(plan['name']?.toString() ?? 'Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Planı sil',
            onPressed: () async {
              await onDeletePlan();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE8DFD3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(isInstallment ? Icons.receipt_long : Icons.savings_outlined, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          plan['name']?.toString() ?? 'Plan',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (notes.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F6F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE7E0D5)),
                      ),
                      child: Text(
                        notes,
                        style: const TextStyle(color: Color(0xFF5F6F68), height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (isInstallment) ...[
                    Text('${plan['paid_installments']} / ${plan['total_installments']} taksit ödendi', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('${plan['remaining_installments']} taksit kaldı • Aylık ${_money(plan['monthly_amount'])}', style: const TextStyle(color: Color(0xFF7B887F))),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Harcanan ${_money(plan['spent_amount'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('Kalan ${_money(plan['remaining_amount'])}', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kayıtlar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await onAddEntry();
                    if (context.mounted) {
                      await onRefresh();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F6F1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7E0D5)),
                ),
                child: const Text(
                  'Henüz harcama eklenmedi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6D736E), height: 1.5),
                ),
              )
            else
              ...entries.map((entry) {
                final entryNotes = entry['notes']?.toString() ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F6F1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E0D5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.receipt_long, size: 18, color: color),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['title']?.toString() ?? 'Kayıt',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entryNotes.isEmpty ? _date(entry['date']) : '${_date(entry['date'])} • $entryNotes',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF6D736E)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _money(entry['amount']),
                        style: TextStyle(color: color, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: const Color(0xFFFFFCF6), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8DFD3))),
    child: const Column(children: [
      Icon(Icons.track_changes_outlined, size: 42, color: Color(0xFF1E6B52)),
      SizedBox(height: 12),
      Text('Henüz planın yok', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      SizedBox(height: 6),
      Text('Bir taksit veya bütçe hedefi oluşturarak başlayabilirsin.', textAlign: TextAlign.center),
    ]),
  );
}

class _CreatePlanDialog extends StatefulWidget {
  const _CreatePlanDialog();

  @override
  State<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends State<_CreatePlanDialog> {
  final name = TextEditingController();
  final target = TextEditingController();
  final monthly = TextEditingController();
  final total = TextEditingController();
  final paid = TextEditingController(text: '0');
  final notes = TextEditingController();
  final paymentDay = TextEditingController(text: '1');
  String type = 'budget';
  bool saving = false;

  @override
  void dispose() {
    for (final controller in [name, target, monthly, total, paid, paymentDay, notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final targetAmount = double.tryParse(target.text.replaceAll(',', '.')) ?? 0;
    final monthlyAmount = double.tryParse(monthly.text.replaceAll(',', '.')) ?? 0;
    final totalInstallments = int.tryParse(total.text) ?? 0;
    final paidInstallments = int.tryParse(paid.text) ?? 0;
    final installmentDay = int.tryParse(paymentDay.text) ?? 1;
    if (name.text.trim().isEmpty || (type == 'budget' && targetAmount <= 0) || (type == 'installment' && (totalInstallments <= 0 || monthlyAmount <= 0))) return;
    setState(() => saving = true);
    try {
      await ApiService.createPlan(name: name.text.trim(), planType: type, targetAmount: targetAmount, monthlyAmount: monthlyAmount, totalInstallments: totalInstallments, paidInstallments: paidInstallments, paymentDay: installmentDay, startDate: DateTime.now(), notes: notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Yeni plan'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'budget', label: Text('Bütçe')), ButtonSegment(value: 'installment', label: Text('Taksit'))], selected: {type}, onSelectionChanged: (value) => setState(() => type = value.first)),
      const SizedBox(height: 16),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Plan adı', hintText: 'Örn. Antalya tatili')),
      if (type == 'budget') TextField(controller: target, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Toplam bütçe (₺)')),
      if (type == 'installment') ...[
        TextField(controller: monthly, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Aylık taksit (₺)')),
        TextField(controller: total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Toplam taksit sayısı')),
        TextField(controller: paid, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daha önce ödenen taksit')),
        TextField(controller: paymentDay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ödeme günü (1-31)')),
      ],
      TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Not (opsiyonel)')),
    ])),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Vazgeç')), FilledButton(onPressed: saving ? null : _submit, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Oluştur'))],
  );
}

class _AddPlanEntryDialog extends StatefulWidget {
  final Map<String, dynamic> plan;
  const _AddPlanEntryDialog({required this.plan});

  @override
  State<_AddPlanEntryDialog> createState() => _AddPlanEntryDialogState();
}

class _AddPlanEntryDialogState extends State<_AddPlanEntryDialog> {
  final title = TextEditingController();
  final amount = TextEditingController();
  final notes = TextEditingController();
  bool saving = false;

  @override
  void dispose() { title.dispose(); amount.dispose(); notes.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final value = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    if (title.text.trim().isEmpty || value <= 0) return;
    setState(() => saving = true);
    try {
      await ApiService.addPlanEntry(planId: widget.plan['id'] as int, title: title.text.trim(), amount: value, date: DateTime.now(), notes: notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.plan['plan_type'] == 'installment' ? 'Taksit ödemesi ekle' : 'Bütçe harcaması ekle'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: title, decoration: InputDecoration(labelText: widget.plan['plan_type'] == 'installment' ? 'Ödeme adı' : 'Harcama adı', hintText: widget.plan['plan_type'] == 'installment' ? 'Örn. Eylül taksidi' : 'Örn. Otel')),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tutar (₺)')),
      TextField(controller: notes, decoration: const InputDecoration(labelText: 'Not (opsiyonel)')),
    ]),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Vazgeç')), FilledButton(onPressed: saving ? null : _submit, child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kaydet'))],
  );
}