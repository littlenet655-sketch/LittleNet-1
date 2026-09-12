import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/features/auth/email_otp_screen.dart';
import 'package:littlenet_native/features/auth/login_screen.dart';
import 'package:littlenet_native/features/auth/parent_liveness_screen.dart';
import 'package:littlenet_native/features/auth/parent_signup_screen.dart';

void main() {
  testWidgets('LittleNetAppV2 initializes and shows LoginScreen',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(authState: authState),
      ),
    );
    await tester.pump();

    expect(find.text('LittleNet'), findsOneWidget);
    expect(find.text('Kids'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('ParentSignupScreen renders registration form', (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: ParentSignupScreen(authState: authState),
      ),
    );

    expect(find.text('Create Parent Account'), findsOneWidget);
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
    expect(find.text('Continue to Email Verification'), findsOneWidget);
  });

  testWidgets('EmailOtpScreen renders 6 OTP boxes and Resend countdown',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: EmailOtpScreen(
          authState: authState,
          pendingToken: 'test_token',
          email: 'parent@example.com',
        ),
      ),
    );

    expect(find.text('Enter Email OTP'), findsOneWidget);
    expect(find.textContaining('parent@example.com'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(find.text('Verify Code'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);
  });

  testWidgets('ParentLivenessScreen renders selfie camera flow',
      (tester) async {
    final client = ApiClient(baseUrl: 'http://localhost:5000');
    final authState = AuthState(apiClient: client);

    await tester.pumpWidget(
      MaterialApp(
        home: ParentLivenessScreen(
          authState: authState,
          pendingToken: 'test_token',
          email: 'parent@example.com',
        ),
      ),
    );

    expect(find.text('Verify Adult Parent'), findsOneWidget);
    expect(find.text('Open Camera & Take Selfie'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });

  test(
      'Email OTP resend contract targets /api/mobile/v1/auth/parent/resend-email',
      () async {
    String? calledPath;
    Map<String, dynamic>? calledBody;

    final mockClient = MockResendApiClient((path, body) {
      calledPath = path;
      calledBody = body;
      return {'ok': true};
    });

    final authState = AuthState(apiClient: mockClient);
    final res = await authState.apiClient.post(
      '/api/mobile/v1/auth/parent/resend-email',
      body: {'pending_token': 'test_pending_token'},
    );

    expect(calledPath, '/api/mobile/v1/auth/parent/resend-email');
    expect(calledBody?['pending_token'], 'test_pending_token');
    expect(res['ok'], true);
  });
}

class MockResendApiClient extends ApiClient {
  MockResendApiClient(this.handler) : super(baseUrl: 'http://localhost:5000');

  final Map<String, dynamic> Function(String path, Map<String, dynamic>? body)
      handler;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    return handler(path, body);
  }
}
