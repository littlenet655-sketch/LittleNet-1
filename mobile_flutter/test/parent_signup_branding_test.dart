import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/brand_logo.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/features/auth/login_screen.dart';
import 'package:littlenet_native/features/auth/parent_signup_screen.dart';

class MockRegistrationApiClient extends ApiClient {
  MockRegistrationApiClient({this.handler})
      : super(baseUrl: 'http://localhost:5000');

  final Future<Map<String, dynamic>> Function(
      String path, Map<String, dynamic>? body)? handler;

  Map<String, dynamic>? lastBody;
  String? lastPath;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    lastPath = path;
    lastBody = body;
    if (handler != null) {
      return await handler!(path, body);
    }
    return {
      'ok': true,
      'pending_token': 'test_pending_token_123',
      'email_sent': true,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Parent Registration Form & Username Tests', () {
    testWidgets('Parent Signup renders Username field in correct position',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient();
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSignupScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      // Verify branding
      expect(find.byType(LittleNetAppLogo), findsOneWidget);

      // Verify all 5 fields exist
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);

      // Verify username hint & prefix icon
      expect(find.text('Choose a unique username'), findsOneWidget);
      expect(find.byIcon(Icons.alternate_email), findsOneWidget);

      // Verify field ordering: Full Name Y < Username Y < Email Y < Password Y
      final nameTop = tester.getTopLeft(find.text('Full Name')).dy;
      final usernameTop = tester.getTopLeft(find.text('Username')).dy;
      final emailTop = tester.getTopLeft(find.text('Email Address')).dy;
      final passwordTop = tester.getTopLeft(find.text('Password')).dy;

      expect(usernameTop, greaterThan(nameTop));
      expect(emailTop, greaterThan(usernameTop));
      expect(passwordTop, greaterThan(emailTop));
    });

    testWidgets('Client validation rejects empty, short, and invalid usernames',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient();
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSignupScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);

      // 1. Test empty username
      await tester.enterText(textFields.at(0), 'Jane Doe'); // Full Name
      await tester.enterText(textFields.at(1), ''); // Username empty
      await tester.enterText(textFields.at(2), 'jane@example.com');
      await tester.enterText(textFields.at(3), 'Password123!');
      await tester.enterText(textFields.at(4), 'Password123!');

      final submitBtn = find.text('Continue to Email Verification');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Username is required.'), findsOneWidget);

      // 2. Test too-short username (2 chars)
      await tester.enterText(textFields.at(1), 'ab');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Username must be 3–30 characters.'), findsOneWidget);

      // 3. Test invalid characters (spaces, special chars)
      await tester.enterText(textFields.at(1), 'jane doe!');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
          find.text('Only letters, numbers, underscores, and dots are allowed.'),
          findsOneWidget);

      // Request should not have been made
      expect(mockClient.lastPath, isNull);
    });

    testWidgets('Valid username is included in registration request body',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient();
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/parent/otp': (_) => const Scaffold(body: Text('OTP_SCREEN')),
          },
          home: ParentSignupScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Parent Guardian');
      await tester.enterText(textFields.at(1), 'parent_guardian.01');
      await tester.enterText(textFields.at(2), 'parent@example.com');
      await tester.enterText(textFields.at(3), 'SecurePass123!');
      await tester.enterText(textFields.at(4), 'SecurePass123!');

      final submitBtn = find.text('Continue to Email Verification');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(mockClient.lastPath, '/api/mobile/v1/auth/parent/register');
      expect(mockClient.lastBody?['username'], 'parent_guardian.01');
      expect(mockClient.lastBody?['full_name'], 'Parent Guardian');
      expect(mockClient.lastBody?['email'], 'parent@example.com');
      expect(mockClient.lastBody?['password'], 'SecurePass123!');
      expect(mockClient.lastBody?['confirm_password'], 'SecurePass123!');
      expect(mockClient.lastBody?['dob'], isNotNull);
      expect(mockClient.lastBody?['guardian_declaration'], '1');

      // Navigates to OTP
      expect(find.text('OTP_SCREEN'), findsOneWidget);
    });

    testWidgets('Duplicate username displays human friendly error message',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient(
        handler: (path, body) async {
          throw ApiException(
            400,
            "The username 'existing_user' already exists. Please choose a different username.",
          );
        },
      );
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: ParentSignupScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Parent User');
      await tester.enterText(textFields.at(1), 'existing_user');
      await tester.enterText(textFields.at(2), 'parent@example.com');
      await tester.enterText(textFields.at(3), 'SecurePass123!');
      await tester.enterText(textFields.at(4), 'SecurePass123!');

      final submitBtn = find.text('Continue to Email Verification');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('This username is already taken. Try another one.'),
        findsOneWidget,
      );
    });
  });

  group('Branding & Login Screen Tests', () {
    testWidgets(
        'Login screen displays LittleNetAppLogo and no shield placeholder',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient();
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      // LittleNetAppLogo must be present
      expect(find.byType(LittleNetAppLogo), findsOneWidget);

      // Generic shield placeholder must NOT exist
      expect(find.byIcon(Icons.shield_outlined), findsNothing);

      // Verify LittleNet title and tagline
      expect(find.text('LittleNet'), findsOneWidget);
      expect(find.text('Safe, positive, parent-guided social learning'),
          findsOneWidget);
    });

    testWidgets('Login identifier field shows appropriate label per role',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockClient = MockRegistrationApiClient();
      final authState = AuthState(apiClient: mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(authState: authState),
        ),
      );
      await tester.pumpAndSettle();

      // Kids tab is active by default
      expect(find.text('Username'), findsOneWidget);

      // Switch to Parent tab
      await tester.tap(find.text('Parent'));
      await tester.pumpAndSettle();

      expect(find.text('Username or Email'), findsOneWidget);
      expect(find.text('Enter your username or email'), findsOneWidget);

      // Switch to Admin tab
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();

      expect(find.text('Username or Email'), findsOneWidget);
    });
  });
}
