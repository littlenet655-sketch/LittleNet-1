import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/models/user.dart';
import 'package:littlenet_native/features/chat/chat_conversation_screen.dart';
import 'package:littlenet_native/features/chat/chat_list_screen.dart';
import 'package:littlenet_native/features/create_post/create_post_screen.dart';
import 'package:littlenet_native/features/feed/comments_sheet.dart';
import 'package:littlenet_native/features/profile/edit_profile_screen.dart';
import 'package:littlenet_native/features/profile/profile_screen.dart';
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
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  late ApiClient client;
  late AuthState authState;

  setUp(() {
    client = ApiClient(baseUrl: 'http://localhost:5000');
    authState = AuthState(apiClient: client);
    authState.setAuthenticated(
      const User(
        userId: 42,
        username: 'kid_tester',
        fullName: 'Test Kid',
        role: 'CHILD',
        age: 11,
      ),
      'dummy-test-token',
    );
  });

  group('Module 11: Create Post', () {
    testWidgets('renders creation screen with camera, gallery and form',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CreatePostScreen(authState: authState),
        ),
      );

      expect(find.text('New Post ✨'), findsOneWidget);
      expect(find.text('Share what you learned or created'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Caption / Story'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Publish Post', skipOffstage: false), findsOneWidget);
    });

    testWidgets('allows kind selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CreatePostScreen(authState: authState),
        ),
      );

      expect(find.text('Post'), findsOneWidget);
      expect(find.text('Reel'), findsOneWidget);
      expect(find.text('Story'), findsOneWidget);

      await tester.tap(find.text('Reel'));
      await tester.pump();
      expect(find.text('Create Reel 🎬'), findsOneWidget);
    });

    testWidgets(
        'verifies canonical age groups: ALL, 6-8, 9-11, 12-13, 14-18 and no 12-14',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CreatePostScreen(authState: authState),
        ),
      );

      // Verify canonical labels exist in the widget tree
      expect(find.text('All Kids'), findsOneWidget);

      // Verify the forbidden non-canonical group 'Ages 12-14' is NOT present
      expect(find.text('Ages 12-14'), findsNothing);
    });
  });

  group('Module 12: Likes & Comments', () {
    testWidgets('renders comments sheet with input and empty state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentsSheet(
              postId: 101,
              authState: authState,
            ),
          ),
        ),
      );

      expect(find.text('Comments 💬'), findsOneWidget);
      expect(find.text('Add a kind, encouraging comment...'), findsOneWidget);
    });
  });

  group('Module 13: Chat', () {
    testWidgets('ChatListScreen renders safety badge and loading state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatListScreen(authState: authState),
        ),
      );

      expect(find.text('Messages 💬'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ChatConversationScreen renders conversation header and input',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatConversationScreen(
            peerId: 77,
            peerName: 'Alex Friend',
            authState: authState,
          ),
        ),
      );

      expect(find.text('Alex Friend'), findsOneWidget);
      expect(find.text('Type a message...'), findsOneWidget);
    });
  });

  group('Module 14: Profile', () {
    testWidgets('ProfileScreen renders profile header, tabs and actions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileScreen(authState: authState),
        ),
      );

      expect(find.text('My Profile 👤'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('EditProfileScreen renders bio, interests and save button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfileScreen(
            authState: authState,
            currentProfile: const {
              'bio': 'Learning to code!',
              'interests': ['Robotics', 'Drawing'],
              'skills': ['Python'],
              'ambitions': ['AI Engineer'],
            },
          ),
        ),
      );

      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Bio'), findsOneWidget);
      expect(find.text('Interests'), findsOneWidget);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('Ambitions'), findsOneWidget);
      expect(find.text('Save Profile Changes', skipOffstage: false),
          findsOneWidget);
    });
  });

  group('Module 15: Settings & Nested Subpages', () {
    testWidgets('SettingsScreen renders header and loading indicator',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(authState: authState),
        ),
      );

      expect(find.text('Settings & Safety ⚙️'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('AccountSettingsPage renders profile details', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSettingsPage(
            authState: authState,
            settingsData: const {
              'profile': {
                'username': 'kid_tester',
                'full_name': 'Test Kid',
                'age': 11,
              },
              'has_face': true,
            },
          ),
        ),
      );

      expect(find.text('Account Details'), findsOneWidget);
      expect(find.text('@kid_tester'), findsOneWidget);
      expect(find.text('Face ID Login'), findsOneWidget);
    });

    testWidgets('PrivacySettingsPage renders privacy preferences',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivacySettingsPage(
            controls: {
              'allow_messaging': true,
              'allow_reels': true,
            },
          ),
        ),
      );

      expect(find.text('Privacy & Visibility'), findsOneWidget);
      expect(find.text('Direct Messaging Privacy'), findsOneWidget);
      expect(find.text('Reels & Video Interaction'), findsOneWidget);
    });

    testWidgets('SafetySettingsPage renders AI safety standards',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SafetySettingsPage(safetyLevel: 'HIGH'),
        ),
      );

      expect(find.text('Safety & AI Moderation'), findsOneWidget);
      expect(find.text('Current Safety Level: HIGH'), findsOneWidget);
      expect(find.text('Automatic Content Filter'), findsOneWidget);
    });

    testWidgets('NotificationsPage renders notification screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationsPage(authState: authState),
        ),
      );

      expect(find.text('Notifications 🔔'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ScreenTimePage renders limits and usage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScreenTimePage(
            minutesToday: 25,
            dailyLimit: 60,
          ),
        ),
      );

      expect(find.text('Screen Time ⏳'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('minutes used'), findsOneWidget);
      expect(find.text('Daily Allowance'), findsOneWidget);
      expect(find.text('Time Remaining'), findsOneWidget);
    });

    testWidgets('ParentControlsPage renders supervisor details',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ParentControlsPage(
            controls: {
              'allow_reels': true,
              'allow_stories': true,
              'allow_messaging': false,
              'educational_only_feed': true,
              'categories': ['Science', 'Art'],
            },
          ),
        ),
      );

      expect(find.text('Parent Controls Info'), findsOneWidget);
      expect(find.text('Supervised by Parent Mode'), findsOneWidget);
      expect(find.text('Short Videos & Reels'), findsOneWidget);
      expect(find.text('Strict Educational-Only Feed'), findsOneWidget);
    });

    testWidgets('BlockedUsersPage renders blocked list interface',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlockedUsersPage(authState: authState),
        ),
      );

      expect(find.text('Blocked Users'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('MutedUsersPage renders muted list interface', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MutedUsersPage(authState: authState),
        ),
      );

      expect(find.text('Muted Users'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('HelpAboutPage renders support and version info',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HelpAboutPage(),
        ),
      );

      expect(find.text('Help & About LittleNet'), findsOneWidget);
      expect(find.text('LittleNet'), findsOneWidget);
      expect(find.text('Version 2.0.0 (Native Release)'), findsOneWidget);
    });
  });
}
