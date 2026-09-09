import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/app/router.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/models/user.dart';
import 'package:littlenet_native/features/discovery/discovery_screen.dart';
import 'package:littlenet_native/features/learning/learning_screen.dart';
import 'package:littlenet_native/features/parent/parent_controls_screen.dart';
import 'package:littlenet_native/features/parent/parent_dashboard_screen.dart';
import 'package:littlenet_native/features/parent/parent_follow_requests_screen.dart';
import 'package:littlenet_native/features/parent/parent_safety_review_screen.dart';
import 'package:littlenet_native/features/quiz/quiz_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  late ApiClient client;
  late AuthState kidAuthState;
  late AuthState parentAuthState;

  setUp(() {
    client = ApiClient(baseUrl: 'http://localhost:5000');
    kidAuthState = AuthState(apiClient: client);
    kidAuthState.setAuthenticated(
      const User(
        userId: 42,
        username: 'kid_tester',
        fullName: 'Test Kid',
        role: 'CHILD',
        age: 11,
      ),
      'dummy-test-token',
    );

    parentAuthState = AuthState(apiClient: client);
    parentAuthState.setAuthenticated(
      const User(
        userId: 10,
        username: 'parent_guardian',
        fullName: 'Test Guardian',
        role: 'PARENT',
      ),
      'dummy-parent-token',
    );
  });

  group('Module 16: Learning & Quiz', () {
    testWidgets('LearningScreen renders title and loading indicator',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningScreen(authState: kidAuthState),
        ),
      );

      expect(find.text('Learning Lab 🔬'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('QuizScreen renders title and loading indicator',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuizScreen(authState: kidAuthState),
        ),
      );

      expect(find.text('Brain Quiz 🧠'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Module 17: Discovery & Connections', () {
    testWidgets('DiscoveryScreen renders safe search bar and title',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryScreen(authState: kidAuthState),
        ),
      );

      expect(find.text('Discover Friends 🔍'), findsOneWidget);
      expect(
        find.text('Search by username or topic (#science, #art)...'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Module 18: Parent Dashboard', () {
    testWidgets('ParentDashboardScreen renders guardian console and sections',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentDashboardScreen(authState: parentAuthState),
        ),
      );

      expect(find.text('Parent Guardian Console'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Module 19: Parent Controls & Screen Time', () {
    testWidgets('ParentControlsScreen renders child id and loading indicator',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentControlsScreen(
            authState: parentAuthState,
            childId: 42,
          ),
        ),
      );

      expect(find.text('Child Controls (#42)'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Module 20: Parent Safety Review & Follow Requests', () {
    testWidgets('ParentSafetyReviewScreen renders safety queue',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentSafetyReviewScreen(authState: parentAuthState),
        ),
      );

      expect(find.text('Parent Safety Queue'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
        'ParentFollowRequestsScreen renders connection approval console',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ParentFollowRequestsScreen(authState: parentAuthState),
        ),
      );

      expect(find.text('Connection Approvals'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Modules 16–20 AppRouter routing', () {
    testWidgets('navigates to learning route', (tester) async {
      final router = AppRouter(authState: kidAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/kids/learning'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to quiz route', (tester) async {
      final router = AppRouter(authState: kidAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/kids/quiz'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to discover route', (tester) async {
      final router = AppRouter(authState: kidAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/kids/discover'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to parent dashboard route', (tester) async {
      final router = AppRouter(authState: parentAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/parent/dashboard'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to parent controls route', (tester) async {
      final router = AppRouter(authState: parentAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/parent/controls', arguments: 42),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to parent safety reviews route', (tester) async {
      final router = AppRouter(authState: parentAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/parent/safety-reviews'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });

    testWidgets('navigates to parent follow requests route', (tester) async {
      final router = AppRouter(authState: parentAuthState);
      final route = router.onGenerateRoute(
        const RouteSettings(name: '/parent/follow-requests'),
      );
      expect(route, isNotNull);
      expect(route, isA<MaterialPageRoute>());
    });
  });
}
