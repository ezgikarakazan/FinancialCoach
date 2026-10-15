import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'upload_screen.dart';

class FinancialSetupScreen extends StatefulWidget {
  final Future<void> Function() onFinished;

  const FinancialSetupScreen({super.key, required this.onFinished});

  @override
  State<FinancialSetupScreen> createState() => _FinancialSetupScreenState();
}

class _FinancialSetupScreenState extends State<FinancialSetupScreen> {
  static const _categories = [
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

  final _institutionController = TextEditingController();
  final _balanceController = TextEditingController();
  final _goalNameController = TextEditingController();
  final _goalAmountController = TextEditingController();
  final Map<String, TextEditingController> _budgetControllers = {
    for (final category in _categories) category: TextEditingController(),
  };
  DateTime _balanceDate = DateTime.now();
  bool _saving = false;
  int _currentStep = 0;
  bool _loadingSavedSetup = true;
  String? _draftStorageKey;
  Timer? _draftSaveTimer;

  int get _stepCount => 3 + _categories.length + 2;

  bool get _isLastStep => _currentStep == _stepCount - 1;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _institutionController,
      _balanceController,
      _goalNameController,
      _goalAmountController,
      ..._budgetControllers.values,
    ]) {
      controller.addListener(_scheduleDraftSave);
    }
    unawaited(_loadSavedSetup());
  }

  Future<void> _loadSavedSetup() async {
    try {
      final user = await ApiService.getCurrentUser();
      final userKey = user['id']?.toString() ?? user['email']?.toString();
      final prefs = await SharedPreferences.getInstance();
      _draftStorageKey = userKey == null
          ? null
          : 'financial_setup_draft_$userKey';
      final draftJson = _draftStorageKey == null
          ? null
          : prefs.getString(_draftStorageKey!);

      try {
        final results = await Future.wait([
          ApiService.getAccountBalances(),
          ApiService.getCategoryBudgets(),
          ApiService.getPlans(),
        ]);

        final balances = results[0];
        final budgets = results[1];
        final plans = results[2];
        if (balances.isNotEmpty) {
          final latestBalance = Map<String, dynamic>.from(
            balances.first as Map,
          );
          _institutionController.text =
              latestBalance['institution_name']?.toString() ?? '';
          _balanceController.text = latestBalance['balance']?.toString() ?? '';
          final dateText = latestBalance['balance_date']?.toString();
          final date = dateText == null ? null : DateTime.tryParse(dateText);
          if (date != null) _balanceDate = date;
        }

        for (final rawBudget in budgets) {
          if (rawBudget is! Map) continue;
          final category = rawBudget['category']?.toString();
          final controller = _budgetControllers[category];
          if (controller != null) {
            controller.text = rawBudget['monthly_limit']?.toString() ?? '';
          }
        }

        for (final rawPlan in plans) {
          if (rawPlan is! Map || rawPlan['notes'] != 'financial_goal') continue;
          _goalNameController.text = rawPlan['name']?.toString() ?? '';
          _goalAmountController.text =
              rawPlan['target_amount']?.toString() ?? '';
          break;
        }
      } catch (error) {
        if (mounted) {
          _showMessage(
            'Sunucuda kayıtlı kurulum bilgileri alınamadı: '
            '${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }

      if (draftJson != null) {
        final decoded = jsonDecode(draftJson);
        if (decoded is Map<String, dynamic>) {
          _applyDraft(decoded);
        }
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Kurulum taslağı yüklenemedi: '
          '${error.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSavedSetup = false);
    }
  }

  void _applyDraft(Map<String, dynamic> decoded) {
    _institutionController.text =
        decoded['institution_name']?.toString() ?? _institutionController.text;
    _balanceController.text =
        decoded['balance']?.toString() ?? _balanceController.text;
    _goalNameController.text =
        decoded['goal_name']?.toString() ?? _goalNameController.text;
    _goalAmountController.text =
        decoded['goal_amount']?.toString() ?? _goalAmountController.text;
    final rawBudgets = decoded['budgets'];
    if (rawBudgets is Map) {
      for (final entry in rawBudgets.entries) {
        final controller = _budgetControllers[entry.key.toString()];
        if (controller != null) {
          controller.text = entry.value?.toString() ?? '';
        }
      }
    }
    final dateText = decoded['balance_date']?.toString();
    final date = dateText == null ? null : DateTime.tryParse(dateText);
    if (date != null) _balanceDate = date;
    final savedStep = decoded['step'];
    if (savedStep is num) {
      _currentStep = savedStep.toInt().clamp(0, _stepCount - 1);
    }
  }

  void _scheduleDraftSave() {
    if (_loadingSavedSetup || _draftStorageKey == null) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 300), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final key = _draftStorageKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'institution_name': _institutionController.text,
        'balance': _balanceController.text,
        'balance_date': _balanceDate.toIso8601String(),
        'budgets': {
          for (final entry in _budgetControllers.entries)
            entry.key: entry.value.text,
        },
        'goal_name': _goalNameController.text,
        'goal_amount': _goalAmountController.text,
        'step': _currentStep,
      }),
    );
  }

  Future<void> _clearDraft() async {
    _draftSaveTimer?.cancel();
    final key = _draftStorageKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _institutionController.dispose();
    _balanceController.dispose();
    _goalNameController.dispose();
    _goalAmountController.dispose();
    for (final controller in _budgetControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? get _balance =>
      double.tryParse(_balanceController.text.trim().replaceAll(',', '.'));

  Future<void> _save({required bool uploadStatement}) async {
    final institution = _institutionController.text.trim();
    final rawBalance = _balanceController.text.trim();
    final balance = _balance;
    final goalName = _goalNameController.text.trim();
    final rawGoalAmount = _goalAmountController.text.trim();
    final goalAmount = double.tryParse(rawGoalAmount.replaceAll(',', '.'));
    final categoryLimits = <MapEntry<String, double>>[];

    if (rawBalance.isNotEmpty && (institution.isEmpty || balance == null)) {
      _showMessage('Banka adını ve geçerli başlangıç bakiyesini girin.');
      return;
    }
    for (final entry in _budgetControllers.entries) {
      final rawAmount = entry.value.text.trim();
      if (rawAmount.isEmpty) continue;
      final amount = double.tryParse(rawAmount.replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        _showMessage('${entry.key} için geçerli bir aylık limit girin.');
        return;
      }
      categoryLimits.add(MapEntry(entry.key, amount));
    }
    if (goalName.isNotEmpty != rawGoalAmount.isNotEmpty ||
        (rawGoalAmount.isNotEmpty && (goalAmount == null || goalAmount <= 0))) {
      _showMessage('Hedef adı ve geçerli hedef tutarını birlikte girin.');
      return;
    }
    if (uploadStatement && institution.isEmpty) {
      _showMessage('Ekstreyi ilişkilendirmek için banka adını girin.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (rawBalance.isNotEmpty) {
        await ApiService.saveAccountBalance(
          institutionName: institution,
          balance: balance!,
          balanceDate: _balanceDate,
        );
      }
      for (final limit in categoryLimits) {
        await ApiService.saveCategoryBudget(
          category: limit.key,
          monthlyLimit: limit.value,
        );
      }
      if (goalName.isNotEmpty) {
        await ApiService.saveFinancialGoal(
          name: goalName,
          targetAmount: goalAmount!,
        );
      }

      if (!mounted) return;
      if (uploadStatement) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => UploadScreen(
              initialInstitutionName: institution,
              initialStatementDate: _balanceDate,
              initialOpeningBalance: rawBalance,
            ),
          ),
        );
      }
      await _clearDraft();
      await widget.onFinished();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skipStep() async {
    if (_isLastStep) {
      await _save(uploadStatement: false);
      return;
    }
    setState(() => _currentStep++);
    await _saveDraft();
  }

  Future<void> _continue() async {
    final rawBalance = _balanceController.text.trim();
    final rawBudget = _currentStep >= 3 && _currentStep < 3 + _categories.length
        ? _budgetControllers[_categories[_currentStep - 3]]!.text.trim()
        : '';
    final rawGoalAmount = _goalAmountController.text.trim();

    if (_currentStep == 1 && rawBalance.isNotEmpty) {
      if (_institutionController.text.trim().isEmpty) {
        _showMessage('Önceki adımda banka / hesap adını girin.');
        return;
      }
      if (_balance == null) {
        _showMessage('Geçerli bir başlangıç bakiyesi girin.');
        return;
      }
    }

    if (rawBudget.isNotEmpty) {
      final amount = double.tryParse(rawBudget.replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        _showMessage('Geçerli ve sıfırdan büyük bir aylık limit girin.');
        return;
      }
    }

    if (_isLastStep) {
      final goalName = _goalNameController.text.trim();
      final goalAmount = double.tryParse(rawGoalAmount.replaceAll(',', '.'));
      if (goalName.isNotEmpty != rawGoalAmount.isNotEmpty ||
          (rawGoalAmount.isNotEmpty &&
              (goalAmount == null || goalAmount <= 0))) {
        _showMessage('Hedef adı ve geçerli hedef tutarını birlikte girin.');
        return;
      }
      await _save(uploadStatement: false);
      return;
    }

    setState(() => _currentStep++);
    await _saveDraft();
  }

  Future<void> _close() async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kurulum kapatılsın mı?'),
        content: const Text(
          'Girdiğin bilgiler taslak olarak saklanacak. Daha sonra Panoramadaki '
          'kurulum kartından kaldığın yerden devam edebilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Devam et'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
    if (shouldClose == true) {
      await _saveDraft();
      await widget.onFinished();
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _balanceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() => _balanceDate = selected);
      await _saveDraft();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _dateLabel(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.'
      '${value.year}';

  String get _stepTitle {
    if (_currentStep == 0) return 'Banka / hesap adı';
    if (_currentStep == 1) return 'Başlangıç bakiyesi';
    if (_currentStep == 2) return 'Bakiye tarihi';
    if (_currentStep < 3 + _categories.length) {
      return '${_categories[_currentStep - 3]} limiti';
    }
    if (_currentStep == 3 + _categories.length) return 'Birikim hedefi';
    return 'Hedef tutarı';
  }

  String get _stepDescription {
    if (_currentStep == 0) {
      return 'Hesabını tanımak için banka veya hesap adını ekle.';
    }
    if (_currentStep == 1) {
      return 'Bu tutar gelir sayılmaz; seçtiğin tarihteki hesap bakiyesi olarak saklanır.';
    }
    if (_currentStep == 2) {
      return 'Başlangıç bakiyesinin veya ekstre döneminin tarihini seç.';
    }
    if (_currentStep < 3 + _categories.length) {
      return 'Bu kategori için aylık harcama sınırı belirleyebilirsin. Boş bırakırsan limit oluşturulmaz.';
    }
    if (_currentStep == 3 + _categories.length) {
      return 'Biriktirmek istediğin hedefe bir isim ver.';
    }
    return 'Hedefine ulaşmak için gereken toplam tutarı belirle.';
  }

  IconData get _stepIcon {
    if (_currentStep == 0) return Icons.account_balance_outlined;
    if (_currentStep == 1) return Icons.account_balance_wallet_outlined;
    if (_currentStep == 2) return Icons.calendar_month_outlined;
    if (_currentStep < 3 + _categories.length) {
      return Icons.savings_outlined;
    }
    return Icons.flag_outlined;
  }

  Widget _buildStepField() {
    if (_currentStep == 0) {
      return TextField(
        controller: _institutionController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Banka / hesap adı',
          hintText: 'Örn. Enpara',
          prefixIcon: Icon(Icons.account_balance_outlined),
        ),
      );
    }
    if (_currentStep == 1) {
      return TextField(
        controller: _balanceController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Başlangıç bakiyesi (₺)',
          hintText: 'Örn. 12500,50',
          prefixIcon: Icon(Icons.account_balance_wallet_outlined),
        ),
      );
    }
    if (_currentStep == 2) {
      return OutlinedButton.icon(
        onPressed: _saving ? null : _pickDate,
        icon: const Icon(Icons.event_outlined),
        label: Text('Tarih: ${_dateLabel(_balanceDate)}'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          alignment: Alignment.centerLeft,
        ),
      );
    }
    if (_currentStep < 3 + _categories.length) {
      final category = _categories[_currentStep - 3];
      return TextField(
        controller: _budgetControllers[category],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: '$category aylık limiti (₺)',
          hintText: 'İsteğe bağlı',
          prefixIcon: const Icon(Icons.savings_outlined),
        ),
      );
    }
    if (_currentStep == 3 + _categories.length) {
      return TextField(
        controller: _goalNameController,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Hedef adı',
          hintText: 'Örn. Acil durum fonu',
          prefixIcon: Icon(Icons.flag_outlined),
        ),
      );
    }
    return TextField(
      controller: _goalAmountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Hedef tutarı (₺)',
        hintText: 'Örn. 50000',
        prefixIcon: Icon(Icons.payments_outlined),
      ),
    );
  }

  Widget _buildUploadOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF1E6B52)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ekstreni şimdi yükle',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ekstre, girdiğin banka ve tarihle eşleştirilir. İşlemleri ayrıca onaylayabilirsin.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _save(uploadStatement: true),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Ekstre seç'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_currentStep + 1) / _stepCount;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F4),
      appBar: AppBar(
        title: const Text('Finansal başlangıç ayarları'),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Kurulumu kapat',
            onPressed: _saving ? null : _close,
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loadingSavedSetup
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ADIM ${_currentStep + 1} / $_stepCount',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: const Color(0xFF1E6B52),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            TextButton(
                              onPressed: _saving ? null : _skipStep,
                              child: const Text('Atla'),
                            ),
                          ],
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE3E9E3),
                            color: const Color(0xFF1E6B52),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4EFE8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              _stepIcon,
                              color: const Color(0xFF1E6B52),
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _stepTitle,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFF24332B),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _stepDescription,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF65736A),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _buildStepField(),
                          if (_currentStep == 2) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Tarihi değiştirmezsen bugünün tarihi kullanılır.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF65736A),
                              ),
                            ),
                          ],
                          if (_isLastStep) ...[
                            const SizedBox(height: 28),
                            _buildUploadOption(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE8ECE7))),
                    ),
                    child: Row(
                      children: [
                        if (_currentStep > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _currentStep--),
                              child: const Text('Geri dön'),
                            ),
                          ),
                        if (_currentStep > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _saving ? null : _continue,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E6B52),
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isLastStep
                                        ? 'Kaydet ve devam et'
                                        : 'Devam',
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
