import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'financial_setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> _dashboardFuture;
  late Future<Map<String, dynamic>> _setupOverviewFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = ApiService.getDashboard();
    _setupOverviewFuture = _loadSetupOverview();
  }

  Future<Map<String, dynamic>> _loadSetupOverview() async {
    final user = await ApiService.getCurrentUser();
    final userKey = user['id']?.toString() ?? user['email']?.toString();
    final prefs = await SharedPreferences.getInstance();
    final draftJson = userKey == null
        ? null
        : prefs.getString('financial_setup_draft_$userKey');
    final draft = draftJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(draftJson) as Map);
    final results = await Future.wait([
      ApiService.getAccountBalances(),
      ApiService.getCategoryBudgets(),
      ApiService.getPlans(),
    ]);
    final balances = results[0]
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final budgets = results[1]
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    Map<String, dynamic>? goal;
    for (final item in results[2].whereType<Map>()) {
      if (item['notes'] == 'financial_goal') {
        goal = Map<String, dynamic>.from(item);
        break;
      }
    }

    if (draft.isNotEmpty) {
      final draftBalance = draft['balance']?.toString().trim() ?? '';
      final draftInstitution =
          draft['institution_name']?.toString().trim() ?? '';
      final draftDate = draft['balance_date']?.toString();
      balances
        ..clear()
        ..add({
          'institution_name': draftInstitution,
          'balance': draftBalance,
          'balance_date': draftDate,
        });

      final draftBudgets = draft['budgets'];
      if (draftBudgets is Map) {
        budgets
          ..clear()
          ..addAll(
            draftBudgets.entries
                .where((entry) => entry.value.toString().trim().isNotEmpty)
                .map(
                  (entry) => {
                    'category': entry.key.toString(),
                    'monthly_limit': entry.value,
                  },
                ),
          );
      }

      final draftGoalName = draft['goal_name']?.toString().trim() ?? '';
      final draftGoalAmount = draft['goal_amount']?.toString().trim() ?? '';
      goal = draftGoalName.isEmpty && draftGoalAmount.isEmpty
          ? null
          : {'name': draftGoalName, 'target_amount': draftGoalAmount};
    }

    return {
      'balances': balances,
      'budgets': budgets,
      'goal': goal,
      'has_draft': draft.isNotEmpty,
      'step': draft['step'],
    };
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinancialSetupScreen(
          onFinished: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _dashboardFuture = ApiService.getDashboard();
      _setupOverviewFuture = _loadSetupOverview();
    });
  }

  void _refreshSetupOverview() {
    setState(() => _setupOverviewFuture = _loadSetupOverview());
  }

  String _formatMoney(dynamic value) {
    final number = (value as num?)?.toDouble() ?? 0;
    return "₺${number.toStringAsFixed(2)}";
  }

  String _signedMoney(num value) {
    final prefix = value < 0 ? "-₺" : "₺";
    return "$prefix${value.abs().toStringAsFixed(2)}";
  }

  Color _amountColor(num value) {
    if (value < 0) return const Color(0xFFB6542D);
    if (value > 0) return const Color(0xFF1E6B52);
    return const Color(0xFF1E2722);
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case "market":
        return Icons.shopping_bag_rounded;
      case "yeme içme":
        return Icons.restaurant_rounded;
      case "ulaşım":
        return Icons.directions_bus_rounded;
      case "gelir":
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  String _riskMessage(String risk) {
    switch (risk) {
      case "Low":
        return "Harcamaların gelirine göre dengeli ilerliyor. Mevcut disiplin korunursa hedef birikim için uygun zemin var.";
      case "Medium":
        return "Giderlerin gelire yaklaşmaya başlıyor. Özellikle değişken kategorilerde küçük kesintiler etkili olabilir.";
      default:
        return "Finansal akış baskı altında görünüyor. Gider yoğun kategorileri azaltman kısa vadede rahatlama sağlar.";
    }
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case "Low":
        return const Color(0xFF1E6B52);
      case "Medium":
        return const Color(0xFFC96B3B);
      default:
        return const Color(0xFFB04242);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _DashboardLoadingState();
          }

          if (snapshot.hasError) {
            return _DashboardErrorState(
              message:
                  "Dashboard verisi alınamadı. Backend bağlantısını ve endpoint yanıtını kontrol et.",
            );
          }

          final data = snapshot.data ?? {};
          final income = (data["income"] as num?) ?? 0;
          final expense = (data["expense"] as num?) ?? 0;
          final saving = (data["saving"] as num?) ?? 0;
          final balance = (data["balance"] as num?) ?? saving;
          final risk = data["risk"]?.toString() ?? "-";
          final recentTransactions =
              (data["recent_transactions"] as List<dynamic>? ?? []);

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Finansal\npanorama",
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Bugünün görünümü gelir, gider ve davranış trendlerinden derlendi.",
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  _HeroBalanceCard(
                    balance: _formatMoney(balance),
                    income: _formatMoney(income),
                    expense: _formatMoney(expense),
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _setupOverviewFuture,
                    builder: (context, setupSnapshot) {
                      if (setupSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const _SetupOverviewLoadingCard();
                      }
                      if (setupSnapshot.hasError) {
                        return _SetupOverviewErrorCard(
                          onRetry: _refreshSetupOverview,
                        );
                      }
                      return _SetupOverviewCard(
                        data: setupSnapshot.data ?? const {},
                        onContinue: _openSetup,
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricPanel(
                          title: "Gelir",
                          value: _formatMoney(income),
                          icon: Icons.north_east_rounded,
                          tone: const Color(0xFFDDEEE7),
                          iconColor: const Color(0xFF1E6B52),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _MetricPanel(
                          title: "Gider",
                          value: _formatMoney(expense),
                          icon: Icons.south_east_rounded,
                          tone: const Color(0xFFF4E0D6),
                          iconColor: const Color(0xFFC96B3B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricPanel(
                          title: "Tasarruf",
                          value: _formatMoney(saving),
                          icon: Icons.savings_rounded,
                          tone: const Color(0xFFE7ECE8),
                          iconColor: const Color(0xFF304238),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _MetricPanel(
                          title: "Risk",
                          value: risk,
                          icon: Icons.shield_outlined,
                          tone: const Color(0xFFF1EEE5),
                          iconColor: _riskColor(risk),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _InsightCard(
                    risk: risk,
                    message: _riskMessage(risk),
                    accent: _riskColor(risk),
                  ),
                  const SizedBox(height: 28),
                  Text("Son işlemler", style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  if (recentTransactions.isEmpty)
                    const _EmptyBlock(
                      title: "Henüz işlem görünmüyor",
                      subtitle:
                          "İşlem ekledikçe burada en güncel hareketleri göreceksin.",
                    )
                  else
                    ...recentTransactions.map((item) {
                      final map = item as Map<String, dynamic>;
                      final amount = (map["amount"] as num?) ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TransactionCard(
                          title: map["title"]?.toString() ?? "-",
                          category: map["category"]?.toString() ?? "-",
                          amount: _signedMoney(amount),
                          amountColor: _amountColor(amount),
                          icon: _categoryIcon(
                            map["category"]?.toString() ?? "",
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeroBalanceCard extends StatelessWidget {
  final String balance;
  final String income;
  final String expense;

  const _HeroBalanceCard({
    required this.balance,
    required this.income,
    required this.expense,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF17352A), Color(0xFF28503F), Color(0xFF3D6A55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Toplam bakiye",
            style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 15),
          ),
          const SizedBox(height: 12),
          Text(
            balance,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: "Gelir", value: income),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(label: "Gider", value: expense),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPanel extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color tone;
  final Color iconColor;

  const _MetricPanel({
    required this.title,
    required this.value,
    required this.icon,
    required this.tone,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6E1D7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tone,
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF64726C),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1E2722),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String risk;
  final String message;
  final Color accent;

  const _InsightCard({
    required this.risk,
    required this.message,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE8E0D2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Risk: $risk",
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "Finans notu",
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E2722),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF55635D),
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final String title;
  final String category;
  final String amount;
  final Color amountColor;
  final IconData icon;

  const _TransactionCard({
    required this.title,
    required this.category,
    required this.amount,
    required this.amountColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9E2D8)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFE7EFEA),
            child: Icon(icon, color: const Color(0xFF2F5646)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF1E2722),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  style: const TextStyle(
                    color: Color(0xFF68756E),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _SetupOverviewLoadingCard extends StatelessWidget {
  const _SetupOverviewLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SetupOverviewErrorCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _SetupOverviewErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Expanded(child: Text('Kurulum bilgileri yüklenemedi.')),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

class _SetupOverviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onContinue;

  const _SetupOverviewCard({required this.data, required this.onContinue});

  String _money(dynamic value) {
    final amount = double.tryParse(value?.toString() ?? '');
    return amount == null ? '—' : '₺${amount.toStringAsFixed(2)}';
  }

  String _balanceDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Tarih belirtilmedi';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final balances = (data['balances'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          return item['institution_name']?.toString().trim().isNotEmpty ==
                  true ||
              item['balance']?.toString().trim().isNotEmpty == true;
        })
        .toList();
    final budgets = (data['budgets'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final goalRaw = data['goal'];
    final goal = goalRaw is Map<String, dynamic> ? goalRaw : null;
    final hasDraft = data['has_draft'] == true;
    final savedStep = (data['step'] as num?)?.toInt();
    final hasAnySetup =
        balances.isNotEmpty || budgets.isNotEmpty || goal != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5E9E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4EFE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF1E6B52)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Başlangıç ayarların',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E2722),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasDraft
                          ? 'Kurulum taslağın kaydedildi.'
                          : hasAnySetup
                          ? 'Kaydettiğin bilgiler burada.'
                          : 'Finansal görünümünü kişiselleştir.',
                      style: const TextStyle(
                        color: Color(0xFF68756E),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasDraft && savedStep != null) ...[
            const SizedBox(height: 14),
            Text(
              'Kaldığın yer: ${savedStep + 1} / 14. adım',
              style: const TextStyle(
                color: Color(0xFF1E6B52),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (!hasAnySetup && !hasDraft) ...[
            const SizedBox(height: 14),
            const Text(
              'Başlangıç bakiyesi, aylık kategori limitleri ve birikim hedefini ekleyebilirsin.',
              style: TextStyle(color: Color(0xFF68756E), height: 1.4),
            ),
          ],
          if (balances.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SetupSectionTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Banka bakiyeleri',
            ),
            const SizedBox(height: 8),
            ...balances.map(
              (balance) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${balance['institution_name']?.toString().trim().isNotEmpty == true ? balance['institution_name'] : 'Banka'}'
                  ' · ${_money(balance['balance'])}'
                  ' · ${_balanceDate(balance['balance_date'])}',
                  style: const TextStyle(color: Color(0xFF44534A)),
                ),
              ),
            ),
          ],
          if (budgets.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _SetupSectionTitle(
              icon: Icons.savings_outlined,
              title: 'Aylık kategori limitleri',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: budgets.map((budget) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3EF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${budget['category']}: ${_money(budget['monthly_limit'])}',
                    style: const TextStyle(
                      color: Color(0xFF44534A),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (goal != null) ...[
            const SizedBox(height: 14),
            _SetupSectionTitle(
              icon: Icons.flag_outlined,
              title:
                  'Birikim hedefi · '
                  '${goal['name']?.toString().trim().isNotEmpty == true ? goal['name'] : 'Hedef'}'
                  ' · ${_money(goal['target_amount'])}',
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onContinue,
              icon: Icon(
                hasDraft ? Icons.play_arrow_rounded : Icons.edit_outlined,
              ),
              label: Text(
                hasDraft
                    ? 'Kuruluma kaldığım yerden devam et'
                    : hasAnySetup
                    ? 'Ayarları düzenle'
                    : 'Kurulumu başlat',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SetupSectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: const Color(0xFF1E6B52)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF34443B),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  final String message;

  const _DashboardErrorState({required this.message});

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
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 42,
                  color: Color(0xFFC96B3B),
                ),
                const SizedBox(height: 14),
                const Text(
                  "Veri alınamadı",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
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

class _EmptyBlock extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyBlock({required this.title, required this.subtitle});

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
          const Icon(Icons.inbox_rounded, size: 40, color: Color(0xFF7B887F)),
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
            style: const TextStyle(color: Color(0xFF64716B), height: 1.45),
          ),
        ],
      ),
    );
  }
}
