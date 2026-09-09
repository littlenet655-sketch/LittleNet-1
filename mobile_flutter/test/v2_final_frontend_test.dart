import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/app/router.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/models/user.dart';
import 'package:littlenet_native/features/explore/explore_screen.dart';
import 'package:littlenet_native/features/moderator/moderation_queue_screen.dart';
import 'package:littlenet_native/features/moderator/moderator_audit_screen.dart';
import 'package:littlenet_native/features/moderator/moderator_dashboard_screen.dart';
import 'package:littlenet_native/features/moderator/moderator_main_shell.dart';
import 'package:littlenet_native/features/moderator/user_admin_screen.dart';
import 'package:littlenet_native/features/profile/followers_following_screen.dart';
import 'package:littlenet_native/features/profile/requests_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  late ApiClient client;
  late AuthState kidAuthState;
  late AuthState adminAuthState;

  setUp(() {
    client = ApiClient(baseUrl: 'http://localhost:5000');
    kidAuthState = AuthState(apiClient: client);
    kidAuthState.setAuthenticated(
      const User(
        userId: 42,
        username: 'kid_tester',
        fullName: 'Aarav Sharma',
        role: 'CHILD',
        age: 11,
      ),
      'test-kid-token',
    );

    adminAuthState = AuthState(apiClient: client);
    adminAuthState.setAuthenticated(
      const User(
        userId: 1,
        username: 'admin_moderator',
        fullName: 'Safety Moderator',
        role: 'ADMIN',
      ),
      'test-admin-token',
    );
  });

  testWidgets('ExploreScreen renders search bar, chips, and tabs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExploreScreen(authState: kidAuthState),
        ),
      ),
    );
    await tester.pump();

    // Verify search bar exists
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Learning'), findsOneWidget);

    // Verify category chips
    expect(find.text('✨ All'), findsOneWidget);
    expect(find.text('🚀 Science'), findsOneWidget);
  });

  testWidgets('FollowersFollowingScreen renders tabs and search bar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowersFollowingScreen(
            authState: kidAuthState,
            initialTab: 0,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0 Followers'), findsOneWidget);
    expect(find.text('0 Following'), findsOneWidget);
    expect(find.text('Suggested'), findsOneWidget);
  });

  testWidgets('RequestsScreen renders incoming and outgoing tabs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RequestsScreen(authState: kidAuthState),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connection Requests 🤝'), findsOneWidget);
    expect(find.text('Received (0)'), findsOneWidget);
    expect(find.text('Sent (0)'), findsOneWidget);
  });

  testWidgets('ModeratorMainShell renders operational tabs and branding',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ModeratorMainShell(
          authState: adminAuthState,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Audit'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('ModeratorDashboardScreen renders header and title',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ModeratorDashboardScreen(authState: adminAuthState),
      ),
    );
    await tester.pump();

    expect(find.text('LittleNet Operations'), findsOneWidget);
    expect(find.text('Child Safety & Compliance Console'), findsOneWidget);
  });

  testWidgets('ModerationQueueScreen renders All, Critical, and Review tabs',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ModerationQueueScreen(authState: adminAuthState),
      ),
    );
    await tester.pump();

    expect(find.text('Moderation Queue'), findsOneWidget);
    expect(find.text('All (0)'), findsOneWidget);
    expect(find.text('Critical (0)'), findsOneWidget);
    expect(find.text('Review (0)'), findsOneWidget);
  });

  testWidgets('UserAdminScreen renders user directory and filters',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UserAdminScreen(authState: adminAuthState),
      ),
    );
    await tester.pump();

    expect(find.text('User Administration'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('ModeratorAuditScreen renders audit trail header',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ModeratorAuditScreen(authState: adminAuthState),
      ),
    );
    await tester.pump();

    expect(find.text('Audit & Compliance Trail'), findsOneWidget);
  });

  testWidgets('AppRouter generates all V2 routes without errors',
      (tester) async {
    final router = AppRouter(authState: adminAuthState);

    final exploreRoute =
        router.onGenerateRoute(const RouteSettings(name: '/kids/explore'));
    expect(exploreRoute, isNotNull);

    final connectionsRoute =
        router.onGenerateRoute(const RouteSettings(name: '/kids/connections'));
    expect(connectionsRoute, isNotNull);

    final requestsRoute =
        router.onGenerateRoute(const RouteSettings(name: '/kids/requests'));
    expect(requestsRoute, isNotNull);

    final modMainRoute =
        router.onGenerateRoute(const RouteSettings(name: '/moderator/main'));
    expect(modMainRoute, isNotNull);

    final modUsersRoute =
        router.onGenerateRoute(const RouteSettings(name: '/moderator/users'));
    expect(modUsersRoute, isNotNull);

    final modAuditRoute =
        router.onGenerateRoute(const RouteSettings(name: '/moderator/audit'));
    expect(modAuditRoute, isNotNull);
  });
}
