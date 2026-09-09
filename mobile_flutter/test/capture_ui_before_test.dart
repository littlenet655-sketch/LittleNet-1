import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/models/user.dart';
import 'package:littlenet_native/features/auth/email_otp_screen.dart';
import 'package:littlenet_native/features/auth/login_screen.dart';
import 'package:littlenet_native/features/auth/parent_liveness_screen.dart';
import 'package:littlenet_native/features/auth/parent_signup_screen.dart';
import 'package:littlenet_native/features/chat/chat_conversation_screen.dart';
import 'package:littlenet_native/features/chat/chat_list_screen.dart';
import 'package:littlenet_native/features/create_post/create_post_screen.dart';
import 'package:littlenet_native/features/discovery/discovery_screen.dart';
import 'package:littlenet_native/features/feed/comments_sheet.dart';
import 'package:littlenet_native/features/feed/feed_screen.dart';
import 'package:littlenet_native/features/kids/kids_home_screen.dart';
import 'package:littlenet_native/features/learning/learning_screen.dart';
import 'package:littlenet_native/features/parent/child_enrollment_screen.dart';
import 'package:littlenet_native/features/parent/parent_controls_screen.dart';
import 'package:littlenet_native/features/parent/parent_dashboard_screen.dart';
import 'package:littlenet_native/features/parent/parent_follow_requests_screen.dart';
import 'package:littlenet_native/features/parent/parent_safety_review_screen.dart';
import 'package:littlenet_native/features/profile/edit_profile_screen.dart';
import 'package:littlenet_native/features/profile/profile_screen.dart';
import 'package:littlenet_native/features/quiz/quiz_screen.dart';
import 'package:littlenet_native/features/reels/reels_screen.dart';
import 'package:littlenet_native/features/settings/settings_screen.dart';
import 'package:littlenet_native/features/settings/subpages/account_settings_page.dart';
import 'package:littlenet_native/features/settings/subpages/blocked_users_page.dart';
import 'package:littlenet_native/features/settings/subpages/help_about_page.dart';
import 'package:littlenet_native/features/settings/subpages/muted_users_page.dart';
import 'package:littlenet_native/features/settings/subpages/notifications_page.dart';
import 'package:littlenet_native/features/settings/subpages/parent_controls_page.dart';
import 'package:littlenet_native/features/settings/subpages/privacy_settings_page.dart';
import 'package:littlenet_native/features/settings/subpages/safety_settings_page.dart';
import 'package:littlenet_native/features/settings/subpages/screen_time_page.dart';

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
  late AuthState parentAuthState;

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
      'dummy-test-token',
    );

    parentAuthState = AuthState(apiClient: client);
    parentAuthState.setAuthenticated(
      const User(
        userId: 10,
        username: 'parent_guardian',
        fullName: 'Priya Sharma',
        role: 'PARENT',
      ),
      'dummy-parent-token',
    );
  });

  Future<void> capture(
    WidgetTester tester,
    Widget screen,
    String filename,
  ) async {
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final file = File('../audit/ui_before/$filename');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pngBytes);
  }

  testWidgets('Capture ALL Current V2 Screens', (tester) async {
    // 1. Auth Screens
    await capture(tester, LoginScreen(authState: kidAuthState), '01_auth_login.png');
    await capture(tester, ParentSignupScreen(authState: parentAuthState), '02_auth_parent_signup.png');
    await capture(tester, EmailOtpScreen(authState: parentAuthState, pendingToken: 'dummy', email: 'parent@test.com'), '03_auth_email_otp.png');
    await capture(tester, ParentLivenessScreen(authState: parentAuthState, pendingToken: 'dummy'), '04_auth_parent_liveness.png');
    await capture(tester, ChildEnrollmentScreen(authState: parentAuthState), '05_auth_child_enrollment.png');

    // 2. Kids Screens
    await capture(tester, KidsHomeScreen(authState: kidAuthState), '06_kids_home.png');
    await capture(tester, FeedScreen(authState: kidAuthState), '07_kids_feed.png');
    await capture(tester, ReelsScreen(authState: kidAuthState), '08_kids_reels.png');
    await capture(tester, CreatePostScreen(authState: kidAuthState), '09_kids_create_post.png');
    await capture(tester, CommentsSheet(authState: kidAuthState, postId: 1), '10_kids_comments.png');
    await capture(tester, ChatListScreen(authState: kidAuthState), '11_kids_messages.png');
    await capture(tester, ChatConversationScreen(authState: kidAuthState, peerId: 99, peerName: 'Diya Patel'), '12_kids_conversation.png');
    await capture(tester, ProfileScreen(authState: kidAuthState), '13_kids_profile.png');
    await capture(tester, EditProfileScreen(authState: kidAuthState, currentProfile: const {'bio': 'Student explorer', 'interests': ['Space', 'Robotics']}), '14_kids_edit_profile.png');
    await capture(tester, SettingsScreen(authState: kidAuthState), '15_kids_settings.png');

    // 3. Settings Subpages
    await capture(tester, AccountSettingsPage(authState: kidAuthState, settingsData: const {'username': 'kid_tester', 'role': 'CHILD', 'age': 11}), '16_settings_account.png');
    await capture(tester, const PrivacySettingsPage(controls: {'allow_discover': true, 'allow_messaging': true}), '17_settings_privacy.png');
    await capture(tester, const SafetySettingsPage(safetyLevel: 'STRICT'), '18_settings_safety.png');
    await capture(tester, NotificationsPage(authState: kidAuthState), '19_settings_notifications.png');
    await capture(tester, const ScreenTimePage(minutesToday: 25, dailyLimit: 60), '20_settings_screen_time.png');
    await capture(tester, const ParentControlsPage(controls: {'allow_reels': true, 'allow_stories': true, 'educational_only_feed': false}), '21_settings_parent_controls.png');
    await capture(tester, BlockedUsersPage(authState: kidAuthState), '22_settings_blocked_users.png');
    await capture(tester, MutedUsersPage(authState: kidAuthState), '23_settings_muted_users.png');
    await capture(tester, const HelpAboutPage(), '24_settings_help_about.png');

    // 4. Learning, Quiz, Discovery
    await capture(tester, LearningScreen(authState: kidAuthState), '25_kids_learning.png');
    await capture(tester, QuizScreen(authState: kidAuthState), '26_kids_quiz.png');
    await capture(tester, DiscoveryScreen(authState: kidAuthState), '27_kids_discovery.png');

    // 5. Parent Screens
    await capture(tester, ParentDashboardScreen(authState: parentAuthState), '28_parent_dashboard.png');
    await capture(tester, ParentControlsScreen(authState: parentAuthState, childId: 42), '29_parent_controls.png');
    await capture(tester, ParentSafetyReviewScreen(authState: parentAuthState), '30_parent_safety_review.png');
    await capture(tester, ParentFollowRequestsScreen(authState: parentAuthState), '31_parent_follow_requests.png');
  });
}
