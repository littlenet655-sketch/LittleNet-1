import 'dart:async';
import 'package:flutter/material.dart';
import '../../api.dart';
import '../core/auth/auth_state.dart';
import '../core/models/user.dart';
import '../features/auth/email_otp_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_liveness_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../features/chat/chat_conversation_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/feed/comments_sheet.dart';
import '../features/feed/feed_screen.dart';
import '../features/kids/kids_home_screen.dart';
import '../features/learning/learning_screen.dart';
import '../features/moderator/incident_detail_screen.dart';
import '../features/moderator/moderation_queue_screen.dart';
import '../features/moderator/moderator_audit_screen.dart';
import '../features/moderator/moderator_dashboard_screen.dart';
import '../features/moderator/user_admin_screen.dart';
import '../features/parent/child_enrollment_screen.dart';
import '../features/parent/parent_controls_screen.dart';
import '../features/parent/parent_dashboard_screen.dart';
import '../features/parent/parent_follow_requests_screen.dart';
import '../features/parent/parent_safety_review_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/followers_following_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/requests_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/reels/reels_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/subpages/blocked_users_page.dart';
import '../features/settings/subpages/help_about_page.dart';
import '../features/settings/subpages/muted_users_page.dart';
import '../features/settings/subpages/notifications_page.dart';
import '../features/settings/subpages/parent_controls_page.dart';
import '../features/settings/subpages/privacy_settings_page.dart';
import '../features/settings/subpages/safety_settings_page.dart';
import '../features/settings/subpages/screen_time_page.dart';

class ScreenShowcaseApp extends StatefulWidget {
  const ScreenShowcaseApp({super.key, this.startAutoAdvance = true});

  final bool startAutoAdvance;

  @override
  State<ScreenShowcaseApp> createState() => _ScreenShowcaseAppState();
}

class _ScreenShowcaseAppState extends State<ScreenShowcaseApp> {
  late final ApiClient _apiClient;
  late final AuthState _kidAuth;
  late final AuthState _parentAuth;
  late final AuthState _adminAuth;

  int _currentIndex = 0;
  Timer? _timer;

  final List<String> screenNames = [
    '01_login.png',
    '02_parent_signup.png',
    '03_email_otp.png',
    '04_parent_liveness.png',
    '05_child_enrollment.png',
    '06_home.png',
    '07_search_explore.png',
    '08_feed.png',
    '09_reels.png',
    '10_create_post.png',
    '11_comments.png',
    '12_messages.png',
    '13_chat.png',
    '14_profile.png',
    '15_edit_profile.png',
    '16_settings.png',
    '17_privacy.png',
    '18_safety.png',
    '19_notifications.png',
    '20_screen_time.png',
    '21_parent_controls_info.png',
    '22_blocked_users.png',
    '23_muted_users.png',
    '24_help_about.png',
    '25_learning.png',
    '26_quiz.png',
    '27_discovery.png',
    '28_followers_following.png',
    '29_requests.png',
    '30_parent_dashboard.png',
    '31_parent_controls.png',
    '32_parent_screen_time.png',
    '33_parent_safety_review.png',
    '34_parent_follow_requests.png',
    '35_moderator_dashboard.png',
    '36_moderation_queue.png',
    '37_incident_detail.png',
    '38_user_admin.png',
    '39_moderator_audit.png',
  ];

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: 'http://localhost:5000');

    _kidAuth = AuthState(apiClient: _apiClient);
    _kidAuth.setAuthenticated(
      const User(
        userId: 42,
        username: 'aarav_explorer',
        fullName: 'Aarav Sharma',
        role: 'CHILD',
        age: 11,
      ),
      'test-kid-token',
    );

    _parentAuth = AuthState(apiClient: _apiClient);
    _parentAuth.setAuthenticated(
      const User(
        userId: 10,
        username: 'priya_guardian',
        fullName: 'Priya Sharma',
        role: 'PARENT',
      ),
      'test-parent-token',
    );

    _adminAuth = AuthState(apiClient: _apiClient);
    _adminAuth.setAuthenticated(
      const User(
        userId: 1,
        username: 'moderator_admin',
        fullName: 'Safety Operations Admin',
        role: 'ADMIN',
      ),
      'test-admin-token',
    );

    if (widget.startAutoAdvance) {
      _timer = Timer.periodic(const Duration(milliseconds: 2500), (t) {
        if (_currentIndex < screenNames.length - 1) {
          setState(() => _currentIndex++);
        } else {
          t.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _getScreenWidget(int index) {
    switch (index) {
      case 0:
        return LoginScreen(authState: _kidAuth);
      case 1:
        return ParentSignupScreen(authState: _parentAuth);
      case 2:
        return EmailOtpScreen(
            authState: _parentAuth,
            pendingToken: 'tok',
            email: 'parent@example.com');
      case 3:
        return ParentLivenessScreen(authState: _parentAuth, pendingToken: 'tok');
      case 4:
        return ChildEnrollmentScreen(authState: _parentAuth);
      case 5:
        return KidsHomeScreen(authState: _kidAuth);
      case 6:
        return ExploreScreen(authState: _kidAuth);
      case 7:
        return FeedScreen(authState: _kidAuth);
      case 8:
        return ReelsScreen(authState: _kidAuth);
      case 9:
        return CreatePostScreen(authState: _kidAuth);
      case 10:
        return CommentsSheet(authState: _kidAuth, postId: 1);
      case 11:
        return ChatListScreen(authState: _kidAuth);
      case 12:
        return ChatConversationScreen(
            authState: _kidAuth, peerId: 99, peerName: 'Diya Patel');
      case 13:
        return ProfileScreen(authState: _kidAuth);
      case 14:
        return EditProfileScreen(authState: _kidAuth, currentProfile: const {
          'bio': 'Learning coder & space explorer! 🚀',
          'interests': ['Robotics', 'Space', 'Astronomy']
        });
      case 15:
        return SettingsScreen(authState: _kidAuth);
      case 16:
        return const PrivacySettingsPage(
            controls: {'allow_discover': true, 'allow_messaging': true});
      case 17:
        return const SafetySettingsPage(safetyLevel: 'STRICT');
      case 18:
        return NotificationsPage(authState: _kidAuth);
      case 19:
        return const ScreenTimePage(minutesToday: 25, dailyLimit: 60);
      case 20:
        return const ParentControlsPage(controls: {
          'allow_reels': true,
          'allow_stories': true,
          'educational_only_feed': false
        });
      case 21:
        return BlockedUsersPage(authState: _kidAuth);
      case 22:
        return MutedUsersPage(authState: _kidAuth);
      case 23:
        return const HelpAboutPage();
      case 24:
        return LearningScreen(authState: _kidAuth);
      case 25:
        return QuizScreen(authState: _kidAuth);
      case 26:
        return DiscoveryScreen(authState: _kidAuth);
      case 27:
        return FollowersFollowingScreen(authState: _kidAuth, initialTab: 0);
      case 28:
        return RequestsScreen(authState: _kidAuth);
      case 29:
        return ParentDashboardScreen(authState: _parentAuth);
      case 30:
        return ParentControlsScreen(authState: _parentAuth, childId: 42);
      case 31:
        return ParentControlsScreen(authState: _parentAuth, childId: 42);
      case 32:
        return ParentSafetyReviewScreen(authState: _parentAuth);
      case 33:
        return ParentFollowRequestsScreen(authState: _parentAuth);
      case 34:
        return ModeratorDashboardScreen(authState: _adminAuth);
      case 35:
        return ModerationQueueScreen(authState: _adminAuth);
      case 36:
        return IncidentDetailScreen(
          authState: _adminAuth,
          eventId: 101,
          initialEvent: const {
            'event_id': 101,
            'full_name': 'Aarav Sharma',
            'username': 'aarav_s',
            'content_type': 'IMAGE',
            'reason': 'Content analysis flag: potential external link / PII',
            'risk_score': 74.0,
            'created_at': 'Just now',
          },
        );
      case 37:
        return UserAdminScreen(authState: _adminAuth);
      case 38:
        return ModeratorAuditScreen(authState: _adminAuth);
      default:
        return LoginScreen(authState: _kidAuth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            KeyedSubtree(
              key: ValueKey(_currentIndex),
              child: _getScreenWidget(_currentIndex),
            ),
            // Subdued index watermark for screenshot verification
            Positioned(
              top: 36,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1}/${screenNames.length} · ${screenNames[_currentIndex]}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
