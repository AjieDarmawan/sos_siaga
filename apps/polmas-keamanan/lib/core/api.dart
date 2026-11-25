import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:http/http.dart' as http;

/// Alamat API SiagaSOS. Build rilis (APK/AAB Play Store) selalu ke produksi `https://sos.tip2.co`; build debug ke
/// `http://localhost:4000` (pakai `adb reverse tcp:4000 tcp:4000`). Bisa ditimpa: `--dart-define=API_URL=...`.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: kReleaseMode ? 'https://sos.tip2.co' : 'http://localhost:4000');

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  bool get isNetwork => status == 0;
  @override
  String toString() => message;
}

/// Klien `/v1/pk`. Token pks_… berumur 12 jam; 401 diteruskan ke [onUnauthorized] (login cepat ulang).
class Api {
  Api({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  String? token;
  Future<bool> Function()? onUnauthorized;

  Uri _u(String path, [Map<String, String?>? q]) {
    final query = <String, String>{};
    q?.forEach((k, v) {
      if (v != null && v.isNotEmpty) query[k] = v;
    });
    return Uri.parse('$apiUrl/v1/pk$path').replace(queryParameters: query.isEmpty ? null : query);
  }

  Future<dynamic> get(String path, [Map<String, String?>? q]) => _send('GET', path, q: q);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);
  Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  Future<dynamic> _send(String method, String path, {Map<String, String?>? q, Object? body, bool retried = false}) async {
    final req = http.Request(method, _u(path, q));
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Koneksi lambat. Periksa sinyal lalu coba lagi.');
    } on SocketException {
      throw ApiException(0, 'offline', 'Tidak ada koneksi internet.');
    } on http.ClientException {
      throw ApiException(0, 'offline', 'Tidak bisa terhubung ke server.');
    }
    if (res.statusCode == 204) return null;
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final err = data is Map ? data['error'] as Map? : null;
    final code = err?['code']?.toString() ?? 'http_${res.statusCode}';
    if (res.statusCode == 401 && !retried && token != null && !path.startsWith('/auth/') && onUnauthorized != null) {
      if (await onUnauthorized!()) return _send(method, path, q: q, body: body, retried: true);
    }
    throw ApiException(res.statusCode, code, err?['message']?.toString() ?? 'Terjadi kesalahan (${res.statusCode}).');
  }
}
