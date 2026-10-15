import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'pdf_history_screen.dart';

class UploadScreen extends StatefulWidget {
  final String? initialInstitutionName;
  final DateTime? initialStatementDate;
  final String? initialOpeningBalance;

  const UploadScreen({
    super.key,
    this.initialInstitutionName,
    this.initialStatementDate,
    this.initialOpeningBalance,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadSectionLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _UploadSectionLabel({
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _UploadScreenState extends State<UploadScreen> {
  int _currentStep = 0;
  int _reviewIndex = 0;
  int _addedCount = 0;
  int _skippedCount = 0;
  int? _currentUploadId;
  String _uploadedFileName = '';
  String? _detectedStatementPeriod;
  String _statementType = 'bank';
  String? _emptyStateOverrideMessage;
  DateTime? _statementDate;
  String? _savedBalanceInstitutionName;
  DateTime? _savedBalanceDate;
  List<Map<String, dynamic>> _candidateTransactions = [];
  bool _isProcessing = false;
  bool _isDeciding = false;
  late Future<List<dynamic>> _uploadsFuture;
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _openingBalanceController =
      TextEditingController();
  final TextEditingController _statementNameController =
      TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _institutionController.text = widget.initialInstitutionName ?? '';
    _openingBalanceController.text = widget.initialOpeningBalance ?? '';
    _statementNameController.text = '';
    _statementDate = widget.initialStatementDate;
    if (widget.initialOpeningBalance?.trim().isNotEmpty == true) {
      _savedBalanceInstitutionName = widget.initialInstitutionName;
      _savedBalanceDate = widget.initialStatementDate;
    }
    _uploadsFuture = ApiService.getPdfUploads();
  }

  @override
  void dispose() {
    _institutionController.dispose();
    _openingBalanceController.dispose();
    _statementNameController.dispose();
    super.dispose();
  }

  void _refreshUploadHistory() {
    if (!mounted) return;
    setState(() {
      _uploadsFuture = ApiService.getPdfUploads();
    });
  }

  Future<void> _pickPdf([String? statementType]) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Dosya verisi okunamadı');
      }
      if (_statementNameController.text.trim().isEmpty) {
        _statementNameController.text = file.name;
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = true;
        _currentStep = 0;
      });

      await _extractPdfFromWeb(
        fileName: file.name,
        bytes: bytes,
        statementType: statementType ?? _statementType,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Dosya seçme hatası: $e")));
      }
    }
  }

  Future<void> _extractPdfFromWeb({
    required String fileName,
    required List<int> bytes,
    required String statementType,
  }) async {
    setState(() => _isProcessing = true);

    try {
      final openingBalanceText = statementType == 'bank'
          ? _openingBalanceController.text.trim()
          : '';
      if (openingBalanceText.isNotEmpty) {
        final institutionName = _institutionController.text.trim();
        final openingBalance = double.tryParse(
          openingBalanceText.replaceAll(',', '.'),
        );
        if (institutionName.isEmpty || _statementDate == null) {
          throw Exception(
            'Başlangıç bakiyesi için banka adını ve ekstre tarihini seçin.',
          );
        }
        if (openingBalance == null) {
          throw Exception('Geçerli bir başlangıç bakiyesi girin.');
        }
        await ApiService.saveAccountBalance(
          institutionName: institutionName,
          balance: openingBalance,
          balanceDate: _statementDate!,
          previousInstitutionName: _savedBalanceInstitutionName,
          previousBalanceDate: _savedBalanceDate,
        );
        _savedBalanceInstitutionName = institutionName;
        _savedBalanceDate = _statementDate;
      }

      final statementName = _normalizedStatementName(fileName);
      final response = await ApiService.uploadPdf(
        bytes: bytes,
        fileName: statementName,
        statementType: statementType,
        institutionName: _institutionController.text.trim(),
        statementDate: _statementDate,
      );

      final isDuplicate = response['duplicate'] == true;
      final uploadIdRaw = response['upload_id'];
      final uploadId = uploadIdRaw is int
          ? uploadIdRaw
          : int.tryParse(uploadIdRaw?.toString() ?? '');

      final allCandidates = _parseCandidatesFromResponse(response);
      final addedSoFar = allCandidates
          .where((c) => c['status'] == 'added')
          .length;
      final skippedSoFar = allCandidates
          .where((c) => c['status'] == 'skipped')
          .length;

      final reviewCandidates = isDuplicate
          ? allCandidates.where((c) => c['status'] == 'pending').toList()
          : allCandidates;

      setState(() {
        _currentUploadId = uploadId;
        _candidateTransactions = reviewCandidates;
        _addedCount = addedSoFar;
        _skippedCount = skippedSoFar;
        _reviewIndex = 0;
        _uploadedFileName = statementName;
        _statementNameController.text = statementName;
        _detectedStatementPeriod = response['detected_period']?.toString();
        _emptyStateOverrideMessage = (isDuplicate && reviewCandidates.isEmpty)
            ? "Bu PDF'i daha önce yükledin ve tüm işlemler zaten incelenmiş. Geçmişten tekrar bakabilirsin."
            : null;
        _currentStep = reviewCandidates.isEmpty ? 2 : 1;
        _uploadsFuture = ApiService.getPdfUploads();
      });

      if (isDuplicate && mounted) {
        final message = reviewCandidates.isEmpty
            ? "Bu PDF'i daha önce yükledin, tüm işlemler zaten incelenmiş."
            : "Bu PDF'i daha önce yükledin. Kalan ${reviewCandidates.length} işlemi incelemeye devam ediyorsun.";
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        _showUploadError(e);
        setState(() => _currentStep = 0);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _normalizedStatementName(String fallbackName) {
    final name = _statementNameController.text.trim();
    final selectedName = name.isEmpty ? fallbackName : name;
    return selectedName.toLowerCase().endsWith('.pdf')
        ? selectedName
        : '$selectedName.pdf';
  }

  void _showUploadError(Object error) {
    final message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('PDF yüklenemedi: ', '');
    final isCreditCardMessage = message.toLowerCase().contains('kredi kartı');
    final isStatementTypeError = message.toLowerCase().contains('seçeneğini');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PDF yüklenirken hata: $message'),
        duration: const Duration(seconds: 6),
        action: isStatementTypeError
            ? SnackBarAction(
                label: isCreditCardMessage
                    ? 'Kredi kartını seç'
                    : 'Banka ekstresini seç',
                onPressed: () {
                  setState(() {
                    _statementType = isCreditCardMessage
                        ? 'credit_card'
                        : 'bank';
                    if (_statementType == 'credit_card') {
                      _openingBalanceController.clear();
                    }
                  });
                },
              )
            : null,
      ),
    );
  }

  List<Map<String, dynamic>> _parseCandidatesFromResponse(
    Map<String, dynamic> response,
  ) {
    final backendParsed = response['parsed_transactions'];
    if (backendParsed is! List) return [];

    final converted = <Map<String, dynamic>>[];

    for (final item in backendParsed) {
      if (item is! Map) continue;

      final idRaw = item['id'];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw?.toString() ?? '');
      final dateRaw = item['date']?.toString();
      final title = item['title']?.toString().trim() ?? '';
      final description = item['description']?.toString().trim() ?? '';
      final category = item['category']?.toString().trim() ?? 'Diğer';
      final amountRaw = item['amount'];
      final status = item['status']?.toString() ?? 'pending';

      final date = dateRaw == null ? null : DateTime.tryParse(dateRaw);
      final amount = amountRaw is num
          ? amountRaw.toDouble()
          : double.tryParse(amountRaw.toString());

      if (id == null || date == null || title.isEmpty || amount == null) {
        continue;
      }

      converted.add({
        'id': id,
        'date': date,
        'title': title,
        'description': description,
        'amount': amount,
        'category': category,
        'learn_category': false,
        'source_type': item['source_type']?.toString() ?? _statementType,
        'status': status,
      });
    }

    return converted;
  }

  Future<void> _decideCurrentTransaction(bool shouldAdd) async {
    if (_isDeciding ||
        _candidateTransactions.isEmpty ||
        _reviewIndex >= _candidateTransactions.length ||
        _currentUploadId == null) {
      return;
    }

    final tx = _candidateTransactions[_reviewIndex];
    final status = shouldAdd ? 'added' : 'skipped';

    if (shouldAdd) {
      final customized = await _customizeTransaction(tx);
      if (!customized) return;
    }

    setState(() => _isDeciding = true);

    try {
      await ApiService.decidePdfUploadItem(
        uploadId: _currentUploadId!,
        itemId: tx['id'] as int,
        status: status,
        title: shouldAdd ? tx['title'] as String : null,
        description: shouldAdd ? tx['description'] as String : null,
        category: shouldAdd ? tx['category'] as String : null,
        sourceType: shouldAdd ? tx['source_type'] as String : null,
        learnCategory: shouldAdd && tx['learn_category'] == true,
      );
      if (shouldAdd && tx['category'] == 'Yatırım') {
        await _saveInvestmentFromTransaction(tx);
      }

      setState(() {
        tx['status'] = status;
        if (shouldAdd) {
          _addedCount++;
        } else {
          _skippedCount++;
        }

        if (_reviewIndex < _candidateTransactions.length - 1) {
          _reviewIndex++;
        } else {
          _currentStep = 3;
        }
        _uploadsFuture = ApiService.getPdfUploads();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeciding = false);
    }
  }

  String _investmentTypeForTitle(String title) {
    final normalized = title.toLowerCase();
    if (normalized.contains('altın') ||
        normalized.contains('altin') ||
        normalized.contains('gold')) {
      return 'Altın';
    }
    if (normalized.contains('hisse')) return 'Hisse';
    if (normalized.contains('fon')) return 'Fon';
    if (normalized.contains('kripto')) return 'Kripto';
    if (normalized.contains('döviz') || normalized.contains('doviz'))
      return 'Döviz';
    return 'Diğer';
  }

  Future<void> _saveInvestmentFromTransaction(Map<String, dynamic> tx) async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString('investments_v1') ?? '[]');
    final investments = decoded is List
        ? decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    final uploadId = _currentUploadId!;
    final itemId = tx['id'] as int;
    if (investments.any(
      (investment) =>
          investment['source_upload_id'] == uploadId &&
          investment['source_item_id'] == itemId,
    )) {
      return;
    }

    final date = tx['date'] as DateTime;
    final type = _investmentTypeForTitle(tx['title'] as String);
    investments.insert(0, {
      'title': type == 'Altın' ? 'Altın alımı' : tx['title'],
      'type': type,
      'amount': (tx['amount'] as num).abs(),
      'date': date.toIso8601String(),
      'start_day': 1,
      'end_day': 31,
      'reminder_day': date.day,
      'notes': tx['description']?.toString() ?? '',
      'source_upload_id': uploadId,
      'source_item_id': itemId,
    });
    await prefs.setString('investments_v1', jsonEncode(investments));
  }

  Future<bool> _customizeTransaction(Map<String, dynamic> tx) async {
    final titleController = TextEditingController(text: tx['title'] as String);
    final descriptionController = TextEditingController(
      text: tx['description']?.toString() ?? '',
    );
    var selectedCategory = _categories.contains(tx['category'])
        ? tx['category'] as String
        : 'Diğer';
    var selectedSourceType = tx['source_type'] == 'credit_card'
        ? 'credit_card'
        : 'bank';
    var categoryWasExplicitlyChanged = tx['learn_category'] == true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('İşlemi özelleştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'İşlem adı'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Açıklama / taksit bilgisi (opsiyonel)',
                  hintText: 'Örn. Araba taksidi',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _categories.contains(selectedCategory)
                    ? selectedCategory
                    : 'Diğer',
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedCategory = value;
                      categoryWasExplicitlyChanged = true;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedSourceType,
                decoration: const InputDecoration(labelText: 'Hesap türü'),
                items: const [
                  DropdownMenuItem(value: 'bank', child: Text('Banka hesabı')),
                  DropdownMenuItem(
                    value: 'credit_card',
                    child: Text('Kredi kartı'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedSourceType = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                tx['title'] = title;
                tx['description'] = descriptionController.text.trim();
                tx['category'] = selectedCategory;
                tx['learn_category'] = categoryWasExplicitlyChanged;
                tx['source_type'] = selectedSourceType;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    descriptionController.dispose();
    return result == true;
  }

  Future<void> _goToPreviousReview() async {
    if (_candidateTransactions.isEmpty ||
        _isDeciding ||
        _currentUploadId == null)
      return;

    final previousIndex = _reviewIndex - 1;
    if (previousIndex < 0) {
      if (_currentStep == 3) {
        setState(() {
          _currentStep = 1;
          _reviewIndex = _candidateTransactions.length - 1;
        });
      }
      return;
    }

    final previousTx = _candidateTransactions[previousIndex];
    if (previousTx['status'] != 'pending') {
      try {
        await ApiService.decidePdfUploadItem(
          uploadId: _currentUploadId!,
          itemId: previousTx['id'] as int,
          status: 'skipped',
        );

        if (previousTx['status'] == 'added') {
          _addedCount = (_addedCount > 0) ? _addedCount - 1 : 0;
        } else if (previousTx['status'] == 'skipped') {
          _skippedCount = (_skippedCount > 0) ? _skippedCount - 1 : 0;
        }

        previousTx['status'] = 'pending';
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _reviewIndex = previousIndex;
      _currentStep = 1;
    });
  }

  void _reset() {
    setState(() {
      _currentStep = 0;
      _reviewIndex = 0;
      _addedCount = 0;
      _skippedCount = 0;
      _currentUploadId = null;
      _uploadedFileName = '';
      _detectedStatementPeriod = null;
      _statementNameController.clear();
      _emptyStateOverrideMessage = null;
      _candidateTransactions = [];
      _uploadsFuture = ApiService.getPdfUploads();
    });
  }

  Future<void> _resumeUpload(Map<String, dynamic> upload) async {
    final rawId = upload['id'];
    final uploadId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (uploadId == null || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final detail = await ApiService.getPdfUploadDetail(uploadId);
      if (!mounted) return;
      final rawItems = detail['items'] as List<dynamic>? ?? [];
      final pendingItems = rawItems.where((item) {
        return item is Map && item['status'] == 'pending';
      }).toList();

      if (pendingItems.isEmpty) {
        _refreshUploadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu dosyada bekleyen işlem kalmamış.'),
            ),
          );
        }
        return;
      }

      final firstPending = pendingItems.first as Map;
      final sourceType = firstPending['source_type']?.toString();
      setState(() {
        _statementType = sourceType == 'credit_card' ? 'credit_card' : 'bank';
        _currentUploadId = uploadId;
        _uploadedFileName =
            detail['filename']?.toString() ??
            upload['filename']?.toString() ??
            'PDF ekstresi';
        _candidateTransactions = _parseCandidatesFromResponse({
          'parsed_transactions': pendingItems,
        });
        _addedCount = (upload['added_count'] as num?)?.toInt() ?? 0;
        _skippedCount = (upload['skipped_count'] as num?)?.toInt() ?? 0;
        _reviewIndex = 0;
        _emptyStateOverrideMessage = null;
        _currentStep = _candidateTransactions.isEmpty ? 0 : 1;
      });
      if (_candidateTransactions.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bekleyen işlemler okunamadı. Lütfen tekrar deneyin.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openUploadDetail(Map<String, dynamic> upload) async {
    final rawId = upload['id'];
    final uploadId = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '');
    if (uploadId == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfUploadDetailScreen(
          uploadId: uploadId,
          filename: upload['filename']?.toString() ?? '',
        ),
      ),
    );
    _refreshUploadHistory();
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PdfHistoryScreen()),
    );
  }

  Color _categoryColor(String category) {
    final colors = {
      'Alışveriş': const Color(0xFF2E6F5E),
      'Yatırım': const Color(0xFFB88935),
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
      'Yatırım': Icons.savings_outlined,
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
      body: SafeArea(
        child: _isProcessing
            ? const Center(child: CircularProgressIndicator())
            : _currentStep == 0
            ? _buildStep0(theme)
            : _currentStep == 1
            ? _buildStep1(theme)
            : _currentStep == 2
            ? _buildStep2(theme)
            : _buildStep3(theme),
      ),
    );
  }

  Widget _buildStep0(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  "Akıllı\nYükleme",
                  style: theme.textTheme.headlineLarge,
                ),
              ),
              IconButton(
                onPressed: _openHistory,
                tooltip: "PDF Geçmişi",
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFFCF6),
                  side: const BorderSide(color: Color(0xFFE8DFD3)),
                ),
                icon: const Icon(
                  Icons.folder_outlined,
                  color: Color(0xFF1E6B52),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Banka ekstresi PDF'sini yükle. İşlemler otomatik olarak ayrıştırılacak.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFE8DF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildTypeSelectorButton(
                    label: 'Banka ekstresi',
                    value: 'bank',
                    icon: Icons.account_balance_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTypeSelectorButton(
                    label: 'Kredi kartı',
                    value: 'credit_card',
                    icon: Icons.credit_card_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _statementNameController,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Ekstre adı',
              hintText: 'Dosyayı seçince PDF adı otomatik gelir',
              prefixIcon: const Icon(Icons.drive_file_rename_outline),
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _institutionController,
            decoration: InputDecoration(
              labelText: 'Banka veya kart kurumu (isteğe bağlı)',
              hintText: 'Örn. Garanti BBVA',
              prefixIcon: const Icon(Icons.account_balance_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_statementType == 'bank') ...[
            const SizedBox(height: 14),
            TextField(
              controller: _openingBalanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Ekstre tarihindeki başlangıç bakiyesi (isteğe bağlı)',
                hintText: 'Örn. 12500,50',
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _isProcessing
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _statementDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null && mounted) {
                      setState(() => _statementDate = picked);
                    }
                  },
            icon: const Icon(Icons.event_outlined),
            label: Text(
              _statementDate == null
                  ? 'Ekstre tarihini seç (isteğe bağlı)'
                  : 'Ekstre tarihi: ${_statementDate!.day.toString().padLeft(2, '0')}.'
                        '${_statementDate!.month.toString().padLeft(2, '0')}.'
                        '${_statementDate!.year}',
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => _pickPdf(_statementType),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCF6),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE8DFD3), width: 2),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E6B52).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 40,
                      color: Color(0xFF1E6B52),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "PDF dosyasını seç",
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Desteklenen format: PDF (banka ekstreleri)\nSınırlandırma: 10MB'a kadar",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF7B887F),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _buildRecentUploadsSection(theme),
          const SizedBox(height: 32),
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
                const Text(
                  "📋 Desteklenen format",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Tarih | İşlem Açıklaması | Tutar\n"
                  "Örnek: 15.06.2026 | Starbucks | 125.50",
                  style: TextStyle(
                    color: Color(0xFF64716B),
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'Courier',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentUploadsSection(ThemeData theme) {
    return FutureBuilder<List<dynamic>>(
      future: _uploadsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8DFD3)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Son yüklenen dosyalar alınamadı.',
                    style: TextStyle(color: Color(0xFF64716B)),
                  ),
                ),
                TextButton(
                  onPressed: _refreshUploadHistory,
                  child: const Text('Tekrar dene'),
                ),
              ],
            ),
          );
        }

        final uploads = (snapshot.data ?? [])
            .whereType<Map>()
            .map((upload) => Map<String, dynamic>.from(upload))
            .toList();
        if (uploads.isEmpty) return const SizedBox.shrink();

        final pendingUploads = uploads
            .where((upload) {
              return ((upload['pending_count'] as num?)?.toInt() ?? 0) > 0;
            })
            .take(3)
            .toList();
        final completedUploads = uploads
            .where((upload) {
              return ((upload['pending_count'] as num?)?.toInt() ?? 0) == 0;
            })
            .take(3)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Son yüklenen dosyalar', style: theme.textTheme.headlineSmall),
            if (pendingUploads.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _UploadSectionLabel(
                title: 'Devam edilecekler',
                icon: Icons.pending_actions_rounded,
                color: Color(0xFFC96B3B),
              ),
              const SizedBox(height: 10),
              ...pendingUploads.map(
                (upload) => _buildUploadHistoryCard(upload, isPending: true),
              ),
            ],
            if (completedUploads.isNotEmpty) ...[
              const SizedBox(height: 12),
              const _UploadSectionLabel(
                title: 'Tamamlananlar',
                icon: Icons.check_circle_outline_rounded,
                color: Color(0xFF1E6B52),
              ),
              const SizedBox(height: 10),
              ...completedUploads.map(
                (upload) => _buildUploadHistoryCard(upload, isPending: false),
              ),
            ],
            if (uploads.length > 3 ||
                uploads.any(
                  (upload) => (upload['pending_count'] as num?)?.toInt() == 0,
                ))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Tüm PDF geçmişi'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildUploadHistoryCard(
    Map<String, dynamic> upload, {
    required bool isPending,
  }) {
    final filename = upload['filename']?.toString() ?? 'PDF ekstresi';
    final pending = (upload['pending_count'] as num?)?.toInt() ?? 0;
    final added = (upload['added_count'] as num?)?.toInt() ?? 0;
    final skipped = (upload['skipped_count'] as num?)?.toInt() ?? 0;
    final uploadedAt = upload['uploaded_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DFD3)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color:
                  (isPending
                          ? const Color(0xFFC96B3B)
                          : const Color(0xFF1E6B52))
                      .withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isPending
                  ? Icons.picture_as_pdf_outlined
                  : Icons.task_alt_rounded,
              color: isPending
                  ? const Color(0xFFC96B3B)
                  : const Color(0xFF1E6B52),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E2722),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPending
                      ? '$pending işlem bekliyor · $added eklendi'
                      : '$added eklendi · $skipped atlandı',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7B887F),
                  ),
                ),
                if (uploadedAt.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _formatUploadDate(uploadedAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9B8C7E),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          isPending
              ? FilledButton(
                  onPressed: () => _resumeUpload(upload),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B52),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Devam et'),
                )
              : IconButton(
                  onPressed: () => _openUploadDetail(upload),
                  tooltip: 'Ayrıntıları gör',
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF7B887F),
                  ),
                ),
        ],
      ),
    );
  }

  String _formatUploadDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Widget _buildTypeSelectorButton({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _statementType == value;

    return Material(
      color: isSelected ? const Color(0xFF1E6B52) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _statementType = value;
            if (value == 'credit_card') _openingBalanceController.clear();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF1E2722),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF1E2722),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1(ThemeData theme) {
    if (_candidateTransactions.isEmpty) {
      return _buildStep2(theme);
    }

    final tx = _candidateTransactions[_reviewIndex];
    final date = tx['date'] as DateTime;
    final amount = (tx['amount'] as num).toDouble();
    final isExpense = amount < 0;
    final signedLabel = isExpense
        ? '-₺${amount.abs().toStringAsFixed(2)}'
        : '+₺${amount.abs().toStringAsFixed(2)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Ekstre bilgilerini düzenle',
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(Icons.arrow_back_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Ekstredeki İşlemler",
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$_uploadedFileName · ${_reviewIndex + 1}/${_candidateTransactions.length} işlem",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7B887F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_detectedStatementPeriod != null) ...[
            const SizedBox(height: 16),
            _buildDetectedPeriodBanner(),
          ],
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE8DFD3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _categoryColor(
                        tx['category'],
                      ).withOpacity(0.12),
                      child: Icon(
                        _categoryIcon(tx['category']),
                        color: _categoryColor(tx['category']),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tx['category'],
                        style: TextStyle(
                          color: _categoryColor(tx['category']),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      signedLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: isExpense
                            ? const Color(0xFFB04242)
                            : const Color(0xFF1E6B52),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tx['title'],
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E2722),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isDeciding
                          ? null
                          : () => _customizeTransaction(tx).then((changed) {
                              if (changed && mounted) setState(() {});
                            }),
                      tooltip: 'İşlemi özelleştir',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                  ],
                ),
                if ((tx['description']?.toString().trim() ?? '')
                    .isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tx['description'].toString(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7B887F),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}",
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7B887F),
                  ),
                ),
                const SizedBox(height: 18),
                if (tx['status'] != 'pending')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (tx['status'] == 'added'
                                  ? const Color(0xFF1E6B52)
                                  : const Color(0xFF9B8C7E))
                              .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tx['status'] == 'added' ? "Eklendi" : "Atlandı",
                      style: TextStyle(
                        color: tx['status'] == 'added'
                            ? const Color(0xFF1E6B52)
                            : const Color(0xFF9B8C7E),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  Text(
                    tx['category'] == 'Yatırım'
                        ? "Bu işlemi Yatırımlarım'a da eklemek istiyor musun?"
                        : "Bu işlemi eklemek istiyor musun?",
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF3D4A44),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: (_reviewIndex + 1) / _candidateTransactions.length,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            color: const Color(0xFF1E6B52),
            backgroundColor: const Color(0xFFE8DFD3),
          ),
          const SizedBox(height: 8),
          Text(
            "Şu ana kadar $_addedCount işlem eklendi, $_skippedCount işlem atlandı.",
            style: const TextStyle(fontSize: 12, color: Color(0xFF7B887F)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (_isDeciding || _reviewIndex == 0)
                      ? null
                      : _goToPreviousReview,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE8DFD3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Önceki"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isDeciding
                      ? null
                      : () => _decideCurrentTransaction(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB8606A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text("Atla"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isDeciding
                      ? null
                      : () => _decideCurrentTransaction(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isDeciding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Ekle"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedPeriodBanner() {
    final selectedDate = _statementDate;
    final selectedDateLabel = selectedDate == null
        ? 'Ekstre tarihi henüz seçilmedi.'
        : 'Seçilen ekstre tarihi: '
              '${selectedDate.day.toString().padLeft(2, '0')}.'
              '${selectedDate.month.toString().padLeft(2, '0')}.'
              '${selectedDate.year}.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E5DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: Color(0xFF1E6B52),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İşlem tarihlerine göre bu ekstre '
                  '$_detectedStatementPeriod dönemine ait görünüyor.',
                  style: const TextStyle(
                    color: Color(0xFF1E6B52),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$selectedDateLabel Dönem bilgisi PDF’deki işlemlerden çıkarıldı.',
                  style: const TextStyle(
                    color: Color(0xFF64716B),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    final message =
        _emptyStateOverrideMessage ??
        "PDF'den işlem ayrıştırılamadı. Formatı kontrol edip tekrar dene.";

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE9DED4)),
        ),
        child: Column(
          children: [
            if (_detectedStatementPeriod != null) ...[
              _buildDetectedPeriodBanner(),
              const SizedBox(height: 16),
            ],
            Icon(
              _emptyStateOverrideMessage != null
                  ? Icons.folder_copy_outlined
                  : Icons.inbox_outlined,
              size: 40,
              color: const Color(0xFF7B887F),
            ),
            const SizedBox(height: 12),
            Text(
              _emptyStateOverrideMessage != null
                  ? "Bu PDF zaten incelenmiş"
                  : "İşlem bulunamadı",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64716B), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_emptyStateOverrideMessage != null) ...[
                  OutlinedButton(
                    onPressed: _openHistory,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8DFD3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Geçmişi Gör"),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton(
                  onPressed: _reset,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6B52),
                  ),
                  child: const Text("Yeni PDF Yükle"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 120),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF6),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE8DFD3)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E6B52).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: Color(0xFF1E6B52),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "İnceleme tamamlandı!",
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  "$_addedCount işlem portföyüne eklendi, $_skippedCount işlem atlandı.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (_skippedCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Atladığın işlemleri PDF Geçmişi'nden istediğin zaman ekleyebilirsin.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF7B887F),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: _openHistory,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE8DFD3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text("PDF Geçmişi"),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _reset,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E6B52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text("Yeni Dosya Yükle"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
