import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<dynamic>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _plansFuture = ApiService.getPlans();
  }

  Future<void> _createPlan() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreatePlanDialog(),
    );
    if (created == true && mounted) setState(_refresh);
  }

  Future<void> _addEntry(Map<String, dynamic> plan) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _AddPlanEntryDialog(plan: plan),
    );
    if (updated == true && mounted) setState(_refresh);
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
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
      }
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
                  Text('Planlar', style: theme.textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Taksitlerini ve hedef bütçelerini tek yerde takip et.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (plans.isEmpty)
                    const _EmptyPlans()
                  else
                    ...plans.map(
                      (rawPlan) => _PlanCard(
                        plan: rawPlan as Map<String, dynamic>,
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
  final VoidCallback onAddEntry;
  final VoidCallback onDelete;

  const _PlanCard({required this.plan, required this.onAddEntry, required this.onDelete});

  String _money(dynamic value) => '₺${(value as num? ?? 0).toStringAsFixed(2)}';

  String _date(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 10) return text.substring(0, 10).split('-').reversed.join('.');
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final isInstallment = plan['plan_type'] == 'installment';
    final target = (plan['target_amount'] as num? ?? 0).toDouble();
    final spent = (plan['spent_amount'] as num? ?? 0).toDouble();
    final progress = target <= 0 ? 0.0 : (spent / target).clamp(0.0, 1.0);
    final paid = plan['paid_installments'] as num? ?? 0;
    final total = plan['total_installments'] as num? ?? 0;
    final color = isInstallment ? const Color(0xFF1E6B52) : const Color(0xFFC96B3B);

    return Card(
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
                Expanded(child: Text(plan['name'].toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Planı sil'))],
                ),
              ],
            ),
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
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onAddEntry,
                icon: Icon(isInstallment ? Icons.check : Icons.add),
                label: Text(isInstallment ? 'Taksit ödendi' : 'Harcama ekle'),
              ),
            ),
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Detay', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${(plan['entries'] as List<dynamic>? ?? []).length} kayıt'),
              children: [
                ...((plan['entries'] as List<dynamic>? ?? []).map((rawEntry) {
                  final entry = rawEntry as Map<String, dynamic>;
                  final notes = entry['notes']?.toString() ?? '';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(Icons.receipt_long, size: 17, color: color),
                    ),
                    title: Text(entry['title']?.toString() ?? 'Kayıt'),
                    subtitle: Text(
                      notes.isEmpty ? _date(entry['date']) : '${_date(entry['date'])} • $notes',
                    ),
                    trailing: Text(
                      _money(entry['amount']),
                      style: TextStyle(color: color, fontWeight: FontWeight.w800),
                    ),
                  );
                })),
                if ((plan['entries'] as List<dynamic>? ?? []).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Henüz harcama eklenmedi.'),
                    ),
                  ),
              ],
            ),
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
  String type = 'budget';
  bool saving = false;

  @override
  void dispose() {
    for (final controller in [name, target, monthly, total, paid, notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final targetAmount = double.tryParse(target.text.replaceAll(',', '.')) ?? 0;
    final monthlyAmount = double.tryParse(monthly.text.replaceAll(',', '.')) ?? 0;
    final totalInstallments = int.tryParse(total.text) ?? 0;
    final paidInstallments = int.tryParse(paid.text) ?? 0;
    if (name.text.trim().isEmpty || (type == 'budget' && targetAmount <= 0) || (type == 'installment' && (totalInstallments <= 0 || monthlyAmount <= 0))) return;
    setState(() => saving = true);
    try {
      await ApiService.createPlan(name: name.text.trim(), planType: type, targetAmount: targetAmount, monthlyAmount: monthlyAmount, totalInstallments: totalInstallments, paidInstallments: paidInstallments, startDate: DateTime.now(), notes: notes.text.trim());
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