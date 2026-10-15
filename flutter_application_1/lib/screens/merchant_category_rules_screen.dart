import 'package:flutter/material.dart';

import '../services/api_service.dart';

class MerchantCategoryRulesScreen extends StatefulWidget {
  const MerchantCategoryRulesScreen({super.key});

  @override
  State<MerchantCategoryRulesScreen> createState() =>
      _MerchantCategoryRulesScreenState();
}

class _MerchantCategoryRulesScreenState
    extends State<MerchantCategoryRulesScreen> {
  static const List<String> _categories = [
    'Alışveriş',
    'Yatırım',
    'Eğitim',
    'Eğlence',
    'Yeme İçme',
    'Ulaşım',
    'Faturalar',
    'Sağlık',
    'Diğer',
  ];

  late Future<List<dynamic>> _rulesFuture;
  final Set<int> _busyRuleIds = {};

  @override
  void initState() {
    super.initState();
    _rulesFuture = ApiService.getMerchantCategoryRules();
  }

  void _refresh() {
    setState(() {
      _rulesFuture = ApiService.getMerchantCategoryRules();
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor:
              isError ? const Color(0xFFB04242) : const Color(0xFF1E6B52),
          content: Text(message),
        ),
      );
  }

  Future<void> _editRule(Map<String, dynamic> rule) async {
    final ruleId = (rule['id'] as num?)?.toInt();
    if (ruleId == null || _busyRuleIds.contains(ruleId)) return;
    final currentCategory = rule['category']?.toString() ?? 'Diğer';
    var selectedCategory = _categories.contains(currentCategory)
        ? currentCategory
        : 'Diğer';

    final category = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${_displayName(rule)} kategorisi'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedCategory,
            decoration: const InputDecoration(labelText: 'Kategori'),
            items: _categories
                .map(
                  (item) => DropdownMenuItem(value: item, child: Text(item)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setDialogState(() => selectedCategory = value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selectedCategory),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (category == null || category == currentCategory) return;

    setState(() => _busyRuleIds.add(ruleId));
    try {
      await ApiService.updateMerchantCategoryRule(
        ruleId: ruleId,
        category: category,
      );
      _refresh();
      _showMessage('Kategori tercihi güncellendi.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(ruleId));
    }
  }

  Future<void> _deleteRule(Map<String, dynamic> rule) async {
    final ruleId = (rule['id'] as num?)?.toInt();
    if (ruleId == null || _busyRuleIds.contains(ruleId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tercihi sil'),
        content: Text(
          '${_displayName(rule)} için kaydedilen kategori tercihi silinecek. '
          'Devam etmek istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB04242),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyRuleIds.add(ruleId));
    try {
      await ApiService.deleteMerchantCategoryRule(ruleId);
      _refresh();
      _showMessage('Öğrenilen tercih silindi.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyRuleIds.remove(ruleId));
    }
  }

  String _displayName(Map<String, dynamic> rule) {
    final merchant = rule['merchant_key']?.toString() ?? '';
    if (merchant.isEmpty) return 'İşletme';
    return '${merchant[0].toUpperCase()}${merchant.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Öğrenilen kategoriler'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _rulesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 44,
                      color: Color(0xFFB04242),
                    ),
                    const SizedBox(height: 12),
                    const Text('Tercihler yüklenemedi.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            );
          }

          final rules = (snapshot.data ?? [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          if (rules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_outlined,
                      size: 48,
                      color: Color(0xFF1E6B52),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Henüz öğrenilmiş tercih yok',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PDF incelemesinde bir işlemin kategorisini kendin '
                      'değiştirip eklediğinde tercih burada saklanır.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                const Text(
                  'Bu tercihler yalnızca senin hesabında kullanılır. '
                  'İşletme adı tam eşleştiğinde sonraki PDF’lerde uygulanır.',
                  style: TextStyle(
                    color: Color(0xFF64716B),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                ...rules.map((rule) {
                  final ruleId = (rule['id'] as num?)?.toInt();
                  final category = rule['category']?.toString() ?? 'Diğer';
                  final isBusy =
                      ruleId != null && _busyRuleIds.contains(ruleId);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE8DFD3)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDEEE7),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.storefront_outlined,
                          color: Color(0xFF1E6B52),
                        ),
                      ),
                      title: Text(
                        _displayName(rule),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('Kategori: $category'),
                      trailing: isBusy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') _editRule(rule);
                                if (action == 'delete') _deleteRule(rule);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Kategoriyi değiştir'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Tercihi sil'),
                                ),
                              ],
                            ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
