import 'package:flutter/material.dart';
import '../services/api_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late Future<List<dynamic>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = ApiService.getTransactions();
  }

  void _refreshTransactions() {
    setState(() {
      _transactionsFuture = ApiService.getTransactions();
    });
  }

  Future<void> _confirmDelete(BuildContext context, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("İşlemi sil"),
        content: const Text("Bu işlem kalıcı olarak silinecek. Devam etmek istiyor musun?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB04242)),
            child: const Text("Sil"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.deleteTransaction(id);
      _refreshTransactions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("İşlem silindi")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      }
    }
  }

  void _showTransactionDialog(BuildContext context, {Map<String, dynamic>? existing}) {
    final isEdit = existing != null;

    final existingAmount = isEdit
        ? (double.tryParse(existing['amount']?.toString() ?? '0') ?? 0)
        : 0.0;

    final titleController = TextEditingController(
      text: isEdit ? (existing['title']?.toString() ?? '') : '',
    );
    final amountController = TextEditingController(
      text: isEdit ? existingAmount.abs().toStringAsFixed(2) : '',
    );
    String selectedCategory = isEdit && _categories.contains(existing['category'])
        ? existing['category'] as String
        : 'Yeme İçme';
    DateTime selectedDate = isEdit
        ? (DateTime.tryParse(existing['date']?.toString() ?? '') ?? DateTime.now())
        : DateTime.now();
    bool isExpense = isEdit ? existingAmount < 0 : true;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFFFFCF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? "İşlemi düzenle" : "Yeni işlem ekle",
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: "İşlem açıklaması",
                    hintStyle: const TextStyle(color: Color(0xFFB8AFA5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: "Tutar (₺)",
                    hintStyle: const TextStyle(color: Color(0xFFB8AFA5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 14),
                StatefulBuilder(
                  builder: (context, setStateDialog) => Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text("Gider"),
                              selected: isExpense,
                              onSelected: (_) => setStateDialog(() => isExpense = true),
                              selectedColor: const Color(0xFFB04242).withOpacity(0.16),
                              labelStyle: TextStyle(
                                color: isExpense ? const Color(0xFFB04242) : const Color(0xFF64716B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text("Gelir"),
                              selected: !isExpense,
                              onSelected: (_) => setStateDialog(() => isExpense = false),
                              selectedColor: const Color(0xFF1E6B52).withOpacity(0.16),
                              labelStyle: TextStyle(
                                color: !isExpense ? const Color(0xFF1E6B52) : const Color(0xFF64716B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE8DFD3)),
                          ),
                          contentPadding: const EdgeInsets.all(14),
                        ),
                        items: _categories
                            .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() => selectedCategory = val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );

                          if (picked != null) {
                            setStateDialog(() => selectedDate = picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE8DFD3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF7B887F)),
                              const SizedBox(width: 10),
                              Text(
                                "${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}",
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (isEdit)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmDelete(context, existing['id'] as int);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB04242),
                            side: const BorderSide(color: Color(0xFFE8DFD3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Sil"),
                        ),
                      )
                    else
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE8DFD3)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("İptal"),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          if (titleController.text.isEmpty || amountController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Tüm alanları doldur")),
                            );
                            return;
                          }

                          final amount = double.tryParse(amountController.text) ?? 0;
                          if (amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Tutar 0'dan büyük olmalı")),
                            );
                            return;
                          }

                          final signedAmount = isExpense ? -amount : amount;

                          try {
                            if (isEdit) {
                              await ApiService.updateTransaction(
                                id: existing['id'] as int,
                                title: titleController.text,
                                amount: signedAmount,
                                category: selectedCategory,
                                date: selectedDate,
                              );
                            } else {
                              await ApiService.addTransaction(
                                title: titleController.text,
                                amount: signedAmount,
                                category: selectedCategory,
                                date: selectedDate,
                              );
                            }
                            if (mounted) {
                              Navigator.pop(ctx);
                              _refreshTransactions();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isEdit ? "İşlem güncellendi" : "İşlem eklendi")),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Hata: $e")),
                              );
                            }
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E6B52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(isEdit ? "Kaydet" : "Ekle"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
    } catch (_) {
      return dateStr;
    }
  }

  static const List<String> _categories = [
    'Alışveriş',
    'Eğitim',
    'Eğlence',
    'Yeme İçme',
    'Ulaşım',
    'Faturalar',
    'Sağlık',
    'Diğer',
  ];

  Color _categoryColor(String category) {
    final colors = {
      'Alışveriş': const Color(0xFF2E6F5E),
      'Eğitim': const Color(0xFF4E6FAF),
      'Eğlence': const Color(0xFFB8606A),
      'Yeme İçme': const Color(0xFF1E6B52),
      'Ulaşım': const Color(0xFFC96B3B),
      'Faturalar': const Color(0xFF7B887F),
      'Sağlık': const Color(0xFF6B8A7F),
      'Diğer': const Color(0xFF9B8C7E),
    };
    return colors[category] ?? const Color(0xFF7B887F);
  }

  IconData _categoryIcon(String category) {
    final icons = {
      'Alışveriş': Icons.shopping_bag_outlined,
      'Eğitim': Icons.school_outlined,
      'Eğlence': Icons.local_movies_outlined,
      'Yeme İçme': Icons.restaurant_outlined,
      'Ulaşım': Icons.directions_car_outlined,
      'Faturalar': Icons.receipt_long_outlined,
      'Sağlık': Icons.local_hospital_outlined,
      'Diğer': Icons.category_outlined,
    };
    return icons[category] ?? Icons.category_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: FutureBuilder<List<dynamic>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _TransactionsLoadingState();
          }

          if (snapshot.hasError) {
            return _TransactionsErrorState(
              onRetry: _refreshTransactions,
            );
          }

          final transactions = snapshot.data ?? [];

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "İşlemler",
                        style: theme.textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "${transactions.length} işlem kaydı",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: transactions.isEmpty
                      ? _EmptyTransactionsBlock()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final tx = transactions[index];
                            final amount = tx['amount']?.toString() ?? '0';
                            final amountNum = double.tryParse(amount) ?? 0;
                            final isIncome = amountNum >= 0;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _showTransactionDialog(context, existing: tx),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFCF6),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE8DFD3)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: _categoryColor(tx['category'] ?? 'Diğer').withOpacity(0.12),
                                        child: Icon(
                                          _categoryIcon(tx['category'] ?? 'Diğer'),
                                          color: _categoryColor(tx['category'] ?? 'Diğer'),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tx['title']?.toString() ?? 'İşlem',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: Color(0xFF1E2722),
                                              ),
                                            ),
                                            if ((tx['description']?.toString().trim() ?? '').isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                tx['description'].toString(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF7B887F),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              _formatDate(tx['date']?.toString() ?? ''),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF7B887F),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        "${isIncome ? '+' : ''}₺${amountNum.toStringAsFixed(2)}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: isIncome ? const Color(0xFF1E6B52) : const Color(0xFFB04242),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF9B8C7E),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTransactionDialog(context),
        backgroundColor: const Color(0xFF1E6B52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}

class _EmptyTransactionsBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
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
                Icons.inbox_outlined,
                size: 48,
                color: Color(0xFF7B887F),
              ),
              const SizedBox(height: 14),
              const Text(
                "Henüz işlem yok",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E2722),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "İlk işlemini eklemek için aşağıdaki butona tıkla.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64716B),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionsLoadingState extends StatelessWidget {
  const _TransactionsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class _TransactionsErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _TransactionsErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
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
                Icons.error_outline_rounded,
                size: 42,
                color: Color(0xFFC96B3B),
              ),
              const SizedBox(height: 14),
              const Text(
                "Bir hata oluştu",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "İşlemler yüklenirken hata. Lütfen tekrar dene.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF5B6761),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E6B52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text("Tekrar Dene"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}