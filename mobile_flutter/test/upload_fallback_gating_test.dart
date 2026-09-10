import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/upload/upload_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File testFile;

  setUpAll(() {
    testFile = File('${Directory.systemTemp.path}/test_upload_media.jpg');
    testFile.writeAsBytesSync(List.generate(1024, (i) => i % 256));
  });

  tearDownAll(() {
    if (testFile.existsSync()) {
      testFile.deleteSync();
    }
  });

  UploadParams createParams(ApiClient client) {
    final auth = AuthState(apiClient: client);
    return UploadParams(
      file: testFile,
      kind: 'post',
      caption: 'Test post',
      category: 'Art',
      audience: 'ALL',
      tags: ['art'],
      authState: auth,
    );
  }

  group('V2 to V1 Fallback Gating Contract', () {
    test('401 Unauthorized -> NO fallback, surfaces error', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response('{"error": "unauthorized"}', 401);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: '401 must NEVER fallback to V1');
      expect(manager.state.stage, equals(UploadStage.failed));
      expect(manager.state.error, contains('unauthorized'));
    });

    test('403 Forbidden (Parent Control) -> NO fallback, surfaces error', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response('{"error": "posting_disabled_by_parent"}', 403);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: '403 must NEVER fallback to V1');
      expect(manager.state.stage, equals(UploadStage.failed));
      expect(manager.state.error, contains('posting_disabled_by_parent'));
    });

    test('413 File Size Exceeded -> NO fallback, surfaces error', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response('{"error": "file_size_exceeded", "max_bytes": 20971520}', 413);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: '413 must NEVER fallback to V1');
      expect(manager.state.stage, equals(UploadStage.failed));
      expect(manager.state.error, contains('file_size_exceeded'));
    });

    test('Validation Error (400 unsupported_extension) -> NO fallback, surfaces error', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response('{"error": "unsupported_extension"}', 400);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: 'Validation error must NEVER fallback to V1');
      expect(manager.state.stage, equals(UploadStage.failed));
      expect(manager.state.error, contains('unsupported_extension'));
    });

    test('Generic 500 Server Error -> NO fallback, surfaces error', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response('{"error": "internal_server_error"}', 500);
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: 'Generic 500 must NEVER fallback to V1');
      expect(manager.state.stage, equals(UploadStage.failed));
      expect(manager.state.error, contains('internal_server_error'));
    });

    test('direct_upload_unavailable with fallback_allowed=false -> NO fallback', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "post_id": 999}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response(
            '{"error": "direct_upload_unavailable", "fallback_allowed": false}',
            503,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isFalse, reason: 'fallback_allowed=false must NOT fallback');
      expect(manager.state.stage, equals(UploadStage.failed));
    });

    test('direct_upload_unavailable with fallback_allowed=true -> PERMITTED fallback to V1', () async {
      bool v1Called = false;
      final mockClient = MockClient((req) async {
        if (req.url.path.contains('/api/mobile/v1/kids/posts')) {
          v1Called = true;
          return http.Response('{"ok": true, "status": "ALLOW", "post_id": 888}', 200);
        }
        if (req.url.path.contains('/api/mobile/v2/uploads/session')) {
          return http.Response(
            '{"error": "direct_upload_unavailable", "fallback_allowed": true}',
            503,
          );
        }
        return http.Response('{"error": "not_found"}', 404);
      });

      final apiClient = ApiClient(httpClient: mockClient);
      final manager = UploadManager.instance;
      await manager.startUpload(createParams(apiClient));

      expect(v1Called, isTrue, reason: 'Explicit fallback_allowed=true MUST trigger V1 fallback');
      expect(manager.state.postId, equals(888));
    });
  });
}
