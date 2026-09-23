import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String? _token;

  static void setToken(String? token) {
    _token = token;
  }

  static void clearToken() {
    _token = null;
  }

  static Future<Map<String, String>> _jsonHeaders() async {
    return {"Content-Type": "application/json"};
  }

  static Map<String, String> _authHeaders(String token) {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $token",
    };
  }

  static String _requireToken() {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception("Oturum bulunamadı. Lütfen tekrar giriş yap.");
    }
    return token;
  }

  static Map<String, String> _currentAuthHeaders() {
    return _authHeaders(_requireToken());
  }

  static Map<String, String> _bearerOnlyHeader() {
    return {"Authorization": "Bearer ${_requireToken()}"};
  }

  static dynamic _decodeBody(http.Response response) {
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  static String _extractError(http.Response response) {
    try {
      final body = _decodeBody(response);
      if (body is Map<String, dynamic> && body["detail"] != null) {
        return body["detail"].toString();
      }
    } catch (_) {}
    return "Sunucu hatasi: ${response.statusCode}";
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/register"),
      headers: await _jsonHeaders(),
      body: jsonEncode({"name": name, "email": email, "password": password}),
    );

    if (response.statusCode == 201) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/login"),
      headers: await _jsonHeaders(),
      body: jsonEncode({"email": email, "password": password}),
    );

    if (response.statusCode == 200) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> getMe({required String token}) async {
    final response = await http.get(
      Uri.parse("$baseUrl/auth/me"),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await http.get(
      Uri.parse("$baseUrl/auth/me"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> updateCurrentUser({
    required String name,
    required String email,
  }) async {
    final response = await http.put(
      Uri.parse("$baseUrl/auth/me"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "name": name,
        "email": email,
      }),
    );

    if (response.statusCode == 200) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/auth/change-password"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "current_password": currentPassword,
        "new_password": newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return (_decodeBody(response) as Map<String, dynamic>);
    }

    throw Exception(_extractError(response));
  }

  static Future<List<dynamic>> getTransactions() async {
    final response = await http.get(
      Uri.parse("$baseUrl/transactions"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw Exception("Veri alınamadı: ${response.statusCode}");
  }

  static Future<Map<String, dynamic>> addTransaction({
    required String title,
    required double amount,
    required String category,
    required DateTime date,
  }) async {
    final dateStr =
        "${date.year.toString().padLeft(4, '0')}-"
        "${date.month.toString().padLeft(2, '0')}-"
        "${date.day.toString().padLeft(2, '0')}";

    final response = await http.post(
      Uri.parse("$baseUrl/transactions"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "title": title,
        "amount": amount,
        "category": category,
        "date": dateStr,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception(
      "İşlem eklenemedi: ${response.statusCode} - ${response.body}",
    );
  }

  static Future<Map<String, dynamic>> updateTransaction({
    required int id,
    required String title,
    required double amount,
    required String category,
    required DateTime date,
  }) async {
    final dateStr =
        "${date.year.toString().padLeft(4, '0')}-"
        "${date.month.toString().padLeft(2, '0')}-"
        "${date.day.toString().padLeft(2, '0')}";

    final response = await http.put(
      Uri.parse("$baseUrl/transactions/$id"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "title": title,
        "amount": amount,
        "category": category,
        "date": dateStr,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception(_extractError(response));
  }

  static Future<void> deleteTransaction(int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/transactions/$id"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      return;
    }

    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> uploadPdf({
    required List<int> bytes,
    required String fileName,
    String statementType = 'bank',
    String institutionName = '',
  }) async {
    final request = http.MultipartRequest(
      "POST",
      Uri.parse("$baseUrl/upload-pdf"),
    );
    request.headers.addAll(_bearerOnlyHeader());
    request.fields['statement_type'] = statementType;
    request.fields['institution_name'] = institutionName;

    request.files.add(
      http.MultipartFile.fromBytes("file", bytes, filename: fileName),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception("PDF yüklenemedi: ${_extractError(response)}");
  }

  static Future<Map<String, dynamic>> getAnalytics() async {
    final response = await http.get(
      Uri.parse("$baseUrl/analytics"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception("Analitik verisi alınamadı");
  }

  static Future<Map<String, dynamic>> getPrediction() async {
    final response = await http.get(
      Uri.parse("$baseUrl/prediction"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception("Tahmin alınamadı");
  }

  static Future<Map<String, dynamic>> getDashboard() async {
    final response = await http.get(
      Uri.parse("$baseUrl/dashboard"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception("Dashboard alınamadı: ${response.statusCode}");
  }

  static Future<List<dynamic>> getPdfUploads() async {
    final response = await http.get(
      Uri.parse("$baseUrl/pdf-uploads"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }

    throw Exception("PDF geçmişi alınamadı: ${response.statusCode}");
  }

  static Future<Map<String, dynamic>> getPdfUploadDetail(int uploadId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/pdf-uploads/$uploadId"),
      headers: _currentAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception("PDF detayı alınamadı: ${response.statusCode}");
  }

  static Future<Map<String, dynamic>> decidePdfUploadItem({
    required int uploadId,
    required int itemId,
    required String status,
    String? title,
    String? description,
    String? category,
    String? sourceType,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/pdf-uploads/$uploadId/items/$itemId/decide"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "status": status,
        "title": ?title,
        "description": ?description,
        "category": ?category,
        "source_type": ?sourceType,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception(_extractError(response));
  }

  static Future<List<dynamic>> getPlans() async {
    final response = await http.get(
      Uri.parse("$baseUrl/plans"),
      headers: _currentAuthHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> createPlan({
    required String name,
    required String planType,
    required double targetAmount,
    required double monthlyAmount,
    required int totalInstallments,
    required int paidInstallments,
    required int paymentDay,
    required DateTime startDate,
    required String notes,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/plans"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "name": name,
        "plan_type": planType,
        "target_amount": targetAmount,
        "monthly_amount": monthlyAmount,
        "total_installments": totalInstallments,
        "paid_installments": paidInstallments,
        "payment_day": paymentDay,
        "start_date": _dateOnly(startDate),
        "notes": notes,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_extractError(response));
  }

  static Future<Map<String, dynamic>> addPlanEntry({
    required int planId,
    required String title,
    required double amount,
    required DateTime date,
    required String notes,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/plans/$planId/entries"),
      headers: _currentAuthHeaders(),
      body: jsonEncode({
        "title": title,
        "amount": amount,
        "date": _dateOnly(date),
        "notes": notes,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception(_extractError(response));
  }

  static Future<void> deletePlan(int id) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/plans/$id"),
      headers: _currentAuthHeaders(),
    );
    if (response.statusCode == 204) return;
    throw Exception(_extractError(response));
  }

  static String _dateOnly(DateTime date) =>
      "${date.year.toString().padLeft(4, '0')}-"
      "${date.month.toString().padLeft(2, '0')}-"
      "${date.day.toString().padLeft(2, '0')}";
}
