import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _quickPrompts = [
    'Tasarruf için ne yapmalıyım?',
    'Bu ay riskli bir durum var mı?',
    'Plan hedefime nasıl yaklaşırım?',
    'Harcama davranışımı özetle',
  ];

  bool _loading = true;
  bool _sending = false;

  Map<String, dynamic> _summary = {};
  final List<Map<String, dynamic>> _messages = [
    {
      'role': 'assistant',
      'text': 'Merhaba! Finansal görünümünü analiz edip sana net öneriler hazırlayayım.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final result = await ApiService.getAiCoachSummary(days: 30);
      if (!mounted) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitPrompt([String? prompt]) async {
    final text = (prompt ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;

    _controller.clear();
    setState(() {
      _sending = true;
      _messages.add({'role': 'user', 'text': text});
    });

    try {
      final result = await ApiService.askAiCoach(message: text, days: 30);
      if (!mounted) return;
      final response = (result['response'] ?? 'Özet alınamadı.').toString();
      setState(() {
        _messages.add({'role': 'assistant', 'text': response});
        if (result['summary'] is Map) {
          _summary = Map<String, dynamic>.from(result['summary'] as Map);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Şu an cevap üretilemedi. Lütfen bir dakika sonra tekrar deneyin.',
        });
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  String _formatMoney(dynamic value) {
    final number = (value as num?)?.toDouble() ?? 0;
    return '₺${number.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final totalIncome = (summary['total_income'] as num?)?.toDouble() ?? 0;
    final totalExpense = (summary['total_expense'] as num?)?.toDouble() ?? 0;
    final netSaving = (summary['net_saving'] as num?)?.toDouble() ?? 0;
    final risk = (summary['risk_level'] ?? 'Düşük').toString();
    final recommendations = (summary['recommendations'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .toList();
    final topCategories = (summary['top_categories'] as List<dynamic>? ?? []);

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Finans Koçu',
                                style: Theme.of(context).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Aylık veriyi analiz edip net kararlar öneririm.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF5F1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFCADFD3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.auto_awesome, color: Color(0xFF1E6B52), size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Canlı',
                                style: TextStyle(
                                  color: Color(0xFF1E6B52),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF17352A), Color(0xFF2B5E49), Color(0xFF477A67)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF17352A).withOpacity(0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Son 30 günlük görünüm',
                            style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _formatMoney(netSaving),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MiniStat(
                                  label: 'Gelir',
                                  value: _formatMoney(totalIncome),
                                  color: const Color(0xFFBFE6D7),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MiniStat(
                                  label: 'Gider',
                                  value: _formatMoney(totalExpense),
                                  color: const Color(0xFFF7D4BA),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Risk seviyesi: $risk',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Hızlı sorular', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _quickPrompts.map((prompt) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => _submitPrompt(prompt),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFCF6),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0xFFD8E0D8)),
                            ),
                            child: Text(
                              prompt,
                              style: const TextStyle(
                                color: Color(0xFF1E2722),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Text('Özet', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE9E0D4)),
                      ),
                      child: Text(
                        (summary['summary'] ?? 'Veri analiz ediliyor...').toString(),
                        style: const TextStyle(
                          color: Color(0xFF55635D),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('En çok harcama', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    if (topCategories.isEmpty)
                      const _EmptyStateCard(message: 'Henüz kategori verisi yok.')
                    else
                      ...topCategories.take(3).map((item) {
                        final category = (item['category'] ?? 'Diğer').toString();
                        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE7DED2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDDEEE7),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.pie_chart_rounded, color: Color(0xFF1E6B52)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E2722),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatMoney(amount),
                                      style: const TextStyle(
                                        color: Color(0xFF53625B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    Text('Öneriler', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    if (recommendations.isEmpty)
                      const _EmptyStateCard(message: 'Öneri üretmek için daha fazla veri gerekiyor.')
                    else
                      ...recommendations.map((item) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F3EB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDDEEE7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.check, size: 18, color: Color(0xFF1E6B52)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    color: Color(0xFF435248),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 24),
                    Text('Koç sohbeti', style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: const Color(0xFFE8E0D2)),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _messages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isUser = message['role'] == 'user';
                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF1E6B52) : const Color(0xFFF2F0EA),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                message['text'] as String,
                                style: TextStyle(
                                  color: isUser ? Colors.white : const Color(0xFF1E2722),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
      bottomSheet: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Koça soru sor...',
                    filled: true,
                    fillColor: const Color(0xFFFFFCF6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFD9DED7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFD9DED7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF1E6B52), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: (_) => _submitPrompt(),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _sending
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 52,
                        height: 52,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      )
                    : FilledButton(
                        key: const ValueKey('send'),
                        onPressed: () => _submitPrompt(),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          minimumSize: const Size(52, 52),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Icon(Icons.send_rounded),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
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

class _EmptyStateCard extends StatelessWidget {
  final String message;

  const _EmptyStateCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7DED2)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF55635D)),
      ),
    );
  }
}
