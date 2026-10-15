import 'package:flutter/material.dart';
import '../services/api_service.dart';

class PdfHistoryScreen extends StatefulWidget {
  const PdfHistoryScreen({super.key});

  @override
  State<PdfHistoryScreen> createState() => _PdfHistoryScreenState();
}

class _PdfHistoryScreenState extends State<PdfHistoryScreen> {
  late Future<List<dynamic>> _uploadsFuture;

  @override
  void initState() {
    super.initState();
    _uploadsFuture = ApiService.getPdfUploads();
  }

  void _refresh() {
    setState(() {
      _uploadsFuture = ApiService.getPdfUploads();
    });
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF Geçmişi"),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _uploadsFuture,
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
                      size: 42,
                      color: Color(0xFFC96B3B),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Geçmiş yüklenemedi",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _refresh,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E6B52),
                      ),
                      child: const Text("Tekrar Dene"),
                    ),
                  ],
                ),
              ),
            );
          }

          final uploads = snapshot.data ?? [];

          if (uploads.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder_open_outlined,
                      size: 48,
                      color: Color(0xFF7B887F),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Henüz PDF yüklemedin",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Yüklediğin banka ekstreleri burada listelenecek.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64716B)),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              itemCount: uploads.length,
              itemBuilder: (context, index) {
                final upload = uploads[index] as Map<String, dynamic>;
                final total = (upload['total_count'] as num?)?.toInt() ?? 0;
                final added = (upload['added_count'] as num?)?.toInt() ?? 0;
                final skipped = (upload['skipped_count'] as num?)?.toInt() ?? 0;
                final pending = (upload['pending_count'] as num?)?.toInt() ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfUploadDetailScreen(
                            uploadId: upload['id'] as int,
                            filename: upload['filename']?.toString() ?? '',
                          ),
                        ),
                      );
                      _refresh();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFCF6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE8DFD3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E6B52).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_outlined,
                              color: Color(0xFF1E6B52),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  upload['filename']?.toString() ??
                                      'Bilinmeyen dosya',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(
                                    upload['uploaded_at']?.toString() ?? '',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7B887F),
                                  ),
                                ),
                                if ((upload['statement_date']?.toString() ?? '')
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'Ekstre tarihi: ${_formatDate(upload['statement_date'].toString())} · '
                                    '${upload['institution_name']?.toString() ?? 'Bilinmiyor'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7B887F),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _CountBadge(
                                      label: "$added eklendi",
                                      color: const Color(0xFF1E6B52),
                                    ),
                                    if (pending > 0)
                                      _CountBadge(
                                        label: "$pending bekliyor",
                                        color: const Color(0xFFC96B3B),
                                      ),
                                    if (skipped > 0)
                                      _CountBadge(
                                        label: "$skipped atlandı",
                                        color: const Color(0xFF9B8C7E),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "$total",
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: Color(0xFF1E2722),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: Color(0xFF9B8C7E),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CountBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class PdfUploadDetailScreen extends StatefulWidget {
  final int uploadId;
  final String filename;

  const PdfUploadDetailScreen({
    super.key,
    required this.uploadId,
    required this.filename,
  });

  @override
  State<PdfUploadDetailScreen> createState() => _PdfUploadDetailScreenState();
}

class _PdfUploadDetailScreenState extends State<PdfUploadDetailScreen> {
  late Future<Map<String, dynamic>> _detailFuture;
  final Set<int> _busyItemIds = {};

  @override
  void initState() {
    super.initState();
    _detailFuture = ApiService.getPdfUploadDetail(widget.uploadId);
  }

  void _refresh() {
    setState(() {
      _detailFuture = ApiService.getPdfUploadDetail(widget.uploadId);
    });
  }

  Future<void> _addItem(int itemId) async {
    final item = await _findItem(itemId);
    if (item == null) return;

    final sourceType = await _chooseSourceType(
      item['source_type']?.toString() ?? 'bank',
    );
    if (sourceType == null) return;

    setState(() => _busyItemIds.add(itemId));
    try {
      await ApiService.decidePdfUploadItem(
        uploadId: widget.uploadId,
        itemId: itemId,
        status: "added",
        sourceType: sourceType,
      );
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("İşlem eklendi")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyItemIds.remove(itemId));
    }
  }

  Future<Map<String, dynamic>?> _findItem(int itemId) async {
    final detail = await _detailFuture;
    final items = detail['items'] as List<dynamic>? ?? [];
    for (final rawItem in items) {
      final item = rawItem as Map<String, dynamic>;
      if (item['id'] == itemId) return item;
    }
    return null;
  }

  Future<String?> _chooseSourceType(String currentSourceType) {
    var selected = currentSourceType == 'credit_card' ? 'credit_card' : 'bank';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nereye eklensin?'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: const InputDecoration(labelText: 'Hesap türü'),
            items: const [
              DropdownMenuItem(value: 'bank', child: Text('Banka hesabı')),
              DropdownMenuItem(
                value: 'credit_card',
                child: Text('Kredi kartı'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeItem(int itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("İşlemi çıkar"),
        content: const Text(
          "Bu işlem portföyünden silinecek. Devam etmek istiyor musun?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB04242),
            ),
            child: const Text("Çıkar"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyItemIds.add(itemId));
    try {
      await ApiService.decidePdfUploadItem(
        uploadId: widget.uploadId,
        itemId: itemId,
        status: "skipped",
      );
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("İşlem çıkarıldı")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      }
    } finally {
      if (mounted) setState(() => _busyItemIds.remove(itemId));
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "added":
        return const Color(0xFF1E6B52);
      case "skipped":
        return const Color(0xFF9B8C7E);
      default:
        return const Color(0xFFC96B3B);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case "added":
        return "Eklendi";
      case "skipped":
        return "Atlandı";
      default:
        return "Bekliyor";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Detay yüklenemedi: ${snapshot.error}",
                textAlign: TextAlign.center,
              ),
            );
          }

          final items = (snapshot.data?['items'] as List<dynamic>? ?? []);

          if (items.isEmpty) {
            return const Center(child: Text("Bu yüklemede işlem bulunamadı"));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              final id = item['id'] as int;
              final status = item['status']?.toString() ?? 'pending';
              final amountRaw = item['amount'];
              final amount = amountRaw is num
                  ? amountRaw.toDouble()
                  : double.tryParse(amountRaw?.toString() ?? '0') ?? 0;
              final isBusy = _busyItemIds.contains(id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFCF6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8DFD3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(
                                      status,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item['category']?.toString() ?? 'Diğer',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7B887F),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item['title']?.toString() ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "${_formatDate(item['date']?.toString() ?? '')} · ₺${amount.abs().toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7B887F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (status != "added")
                        SizedBox(
                          height: 36,
                          child: FilledButton(
                            onPressed: isBusy ? null : () => _addItem(id),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E6B52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            child: isBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Ekle"),
                          ),
                        )
                      else
                        SizedBox(
                          height: 36,
                          child: OutlinedButton(
                            onPressed: isBusy ? null : () => _removeItem(id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB04242),
                              side: const BorderSide(color: Color(0xFFE8DFD3)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            child: isBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFB04242),
                                    ),
                                  )
                                : const Text("Çıkar"),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
