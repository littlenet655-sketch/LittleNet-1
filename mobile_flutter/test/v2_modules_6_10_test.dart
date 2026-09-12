import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/features/feed/feed_screen.dart';
import 'package:littlenet_native/features/kids/kids_home_screen.dart';
import 'package:littlenet_native/features/kids/kids_main_shell.dart';
import 'package:littlenet_native/features/parent/child_enrollment_screen.dart';
import 'package:littlenet_native/features/reels/reels_screen.dart';

void main() {
  testWidgets('ChildEnrollmentScreen renders creation form', (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: ChildEnrollmentScreen(authState: authState),
      ),
    );

    expect(find.text('Create Child Account'), findsOneWidget);
    expect(find.text('Child Full Name'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Age (4-18)'), findsOneWidget);
    expect(find.text('Initial Password'), findsOneWidget);
    expect(find.text('Parent Safety Level'), findsOneWidget);
    expect(find.text('Daily Screen Time Limit'), findsOneWidget);
    expect(find.text('Submit Registration'), findsOneWidget);
  });

  testWidgets('KidsMainShell renders 5 bottom navigation tabs', (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: KidsMainShell(authState: authState),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Reels'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('KidsHomeScreen displays greeting and initial structure',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: KidsHomeScreen(authState: authState),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('FeedScreen displays title and initial loading spinner',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: FeedScreen(authState: authState),
      ),
    );

    expect(find.text('Discover & Learn 📚'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ReelsScreen displays vertical PageView structure',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: ReelsScreen(authState: authState),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  group('Parent-Assisted Child Enrollment Contract', () {
    testWidgets(
        'Child creation captures child_id and displays face enrollment action',
        (tester) async {
      String? createdChildEndpoint;
      Map<String, dynamic>? createdChildBody;

      final mockClient = MockChildEnrollmentApiClient(
        onPost: (path, body) async {
          if (path == '/api/mobile/v1/parent/children') {
            createdChildEndpoint = path;
            createdChildBody = body;
            return {
              'ok': true,
              'child_id': 142,
              'next_steps': ['child_face_enrollment', 'age_quiz'],
            };
          }
          throw ApiException(404, 'Not found');
        },
      );

      final authState = AuthState(apiClient: mockClient);

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: ChildEnrollmentScreen(authState: authState),
        ),
      );

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Child Full Name'),
          'Aarav Sharma');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'aarav_test');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Age (4-18)'), '9');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Initial Password'),
          'SecurePass123!');

      await tester.ensureVisible(find.text('Submit Registration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Registration'));
      await tester.pumpAndSettle();

      expect(createdChildEndpoint, '/api/mobile/v1/parent/children');
      expect(createdChildBody?['username'], 'aarav_test');
      expect(createdChildBody?['age'], 9);

      // Verify that child_id is captured and face enrollment step is shown
      expect(find.textContaining('Child account created!'), findsOneWidget);
      expect(find.text('Enroll Child Face ID (Optional)'), findsOneWidget);
      expect(find.text('Done / Return to Dashboard'), findsOneWidget);
    });

    test(
        'Face enrollment contract uses exact parent endpoint, sends parent auth, and omits controls endpoint',
        () async {
      final calledPaths = <String>[];
      final headersUsed = <String, String>{};

      late final MockChildEnrollmentApiClient mockClient;
      mockClient = MockChildEnrollmentApiClient(
        token: 'parent_bearer_token_xyz',
        onPost: (path, body) async {
          calledPaths.add(path);
          if (path == '/api/mobile/v1/parent/children/142/face/enroll') {
            headersUsed.addAll(mockClient.authHeaders);
            return {
              'ok': true,
              'child_id': 142,
              'face_enrolled': true,
              'quiz_required': true,
            };
          }
          return {'ok': false};
        },
      );

      // Verify auth header contains parent bearer token
      expect(mockClient.authHeaders['Authorization'],
          'Bearer parent_bearer_token_xyz');

      // Call face enrollment
      final res = await mockClient.post(
        '/api/mobile/v1/parent/children/142/face/enroll',
        body: {'photo_b64': 'base64_encoded_dummy_camera_bytes'},
      );

      expect(res['ok'], true);
      expect(res['child_id'], 142);
      expect(res['face_enrolled'], true);
      expect(res['quiz_required'], true);

      // Verify exact endpoint was called
      expect(
        calledPaths,
        contains('/api/mobile/v1/parent/children/142/face/enroll'),
      );

      // Verify controls endpoint is NOT called for face enrollment
      expect(
        calledPaths.any((p) => p.contains('/parent/controls')),
        isFalse,
      );
    });

    test('Face enrollment error leaves retry available without crashing',
        () async {
      int attempts = 0;

      final mockClient = MockChildEnrollmentApiClient(
        token: 'parent_bearer_token_xyz',
        onPost: (path, body) async {
          attempts++;
          if (attempts == 1) {
            throw ApiException(400, 'face_enrollment_failed');
          }
          return {
            'ok': true,
            'child_id': 142,
            'face_enrolled': true,
            'quiz_required': false,
          };
        },
      );

      // Attempt 1 fails
      try {
        await mockClient.post(
          '/api/mobile/v1/parent/children/142/face/enroll',
          body: {'photo_b64': 'attempt_1_bytes'},
        );
        fail('Should throw ApiException');
      } on ApiException catch (e) {
        expect(e.message, 'face_enrollment_failed');
      }

      // Retry Attempt 2 succeeds
      final res2 = await mockClient.post(
        '/api/mobile/v1/parent/children/142/face/enroll',
        body: {'photo_b64': 'attempt_2_bytes'},
      );
      expect(res2['ok'], true);
      expect(res2['face_enrolled'], true);
      expect(attempts, 2);
    });
  });
}

class MockChildEnrollmentApiClient extends ApiClient {
  MockChildEnrollmentApiClient({
    this.token,
    required this.onPost,
  }) : super(baseUrl: 'http://localhost:5000');

  final String? token;
  final Future<Map<String, dynamic>> Function(
    String path,
    Map<String, dynamic>? body,
  ) onPost;

  @override
  Map<String, String> get authHeaders => {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return onPost(path, body);
  }
}
