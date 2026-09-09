import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, [this.payload]);

  final int statusCode;
  final String message;
  final Map<String, dynamic>? payload;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl})
      : baseUrl = (baseUrl ??
                const String.fromEnvironment(
                  'LITTLENET_API_BASE',
                  defaultValue:
                      'https://littlenet655--littlenet-web-web.modal.run',
                ))
            .replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _token;

  Future<void> restore() async {
    try {
      _token = await _storage.read(key: 'littlenet_mobile_token');
    } catch (_) {
      _token = null;
    }
  }

  bool get hasToken => _token != null && _token!.isNotEmpty;

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: 'littlenet_mobile_token', value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: 'littlenet_mobile_token');
  }

  Future<void> clear() => clearToken();

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      getJson(path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) =>
      postJson(path, body ?? const {});

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) =>
      putJson(path, body ?? const {});

  Map<String, String> get authHeaders => {
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) params[key] = value.toString();
    });
    return Uri.parse('$baseUrl$normalized').replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await http.get(uri(path, query), headers: authHeaders);
    return _decode(response);
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      uri(path),
      headers: {...authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.put(
      uri(path),
      headers: {...authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> multipart(
    String path, {
    Map<String, String>? fields,
    File? file,
    String fileField = 'media',
  }) async {
    final request = http.MultipartRequest('POST', uri(path));
    request.headers.addAll(authHeaders);
    request.fields.addAll(fields ?? const {});
    if (file != null) {
      request.files
          .add(await http.MultipartFile.fromPath(fileField, file.path));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
    required String mode,
  }) async {
    final data = await postJson('/api/mobile/v1/auth/login', {
      'identifier': identifier,
      'password': password,
      'mode': mode,
    });
    final token = data['token']?.toString();
    if (token != null && token.isNotEmpty) await setToken(token);
    return data;
  }

  Future<void> logout() async {
    try {
      if (hasToken) await postJson('/api/mobile/v1/auth/logout', const {});
    } catch (_) {
      // Local token removal must still work when the network is unavailable.
    }
    await clearToken();
  }

  Future<Map<String, dynamic>> faceLogin({
    required String identifier,
    required String mode,
    required File photo,
  }) async {
    final data = await multipart(
      '/api/mobile/v1/auth/face-login',
      fields: {'identifier': identifier, 'mode': mode},
      file: photo,
      fileField: 'photo',
    );
    final token = data['token']?.toString();
    if (token != null && token.isNotEmpty) await setToken(token);
    return data;
  }

  Future<Map<String, dynamic>> enrollChildFace(File photo) => multipart(
        '/api/mobile/v1/kids/face/enroll',
        file: photo,
        fileField: 'photo',
      );

  Future<Map<String, dynamic>> uploadPost({
    required String kind,
    required String caption,
    required String category,
    required String audience,
    File? media,
  }) =>
      multipart(
        '/api/mobile/v1/kids/posts',
        fields: {
          'kind': kind,
          'caption': caption,
          'content_category': category,
          'audience_age_group': audience,
        },
        file: media,
      );

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      data = <String, dynamic>{
        'error': response.body.isEmpty ? 'empty_response' : response.body,
      };
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['error']?.toString() ??
          data['message']?.toString() ??
          'Request failed (${response.statusCode})';
      throw ApiException(response.statusCode, message, data);
    }
    return data;
  }
}
