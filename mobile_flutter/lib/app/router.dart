import 'package:flutter/material.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/email_otp_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_liveness_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../features/chat/chat_conversation_screen.dart';
import '../features/chat/chat_details_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/kids/kids_main_shell.dart';
import '../features/kids/notifications_screen.dart';
import '../features/kids/story_viewer_screen.dart';
import '../features/learning/learning_screen.dart';
import '../features/moderator/incident_detail_screen.dart';
import '../features/moderator/moderator_audit_screen.dart';
import '../features/moderator/moderator_main_shell.dart';
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

class AppRouter {
  const AppRouter({required this.authState});

  final AuthState authState;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final rawArgs = settings.arguments;
    final Map<String, dynamic> args =
        rawArgs is Map<String, dynamic> ? rawArgs : {};

    switch (settings.name) {
      case '/':
      case '/login':
        return MaterialPageRoute(
          builder: (_) => LoginScreen(authState: authState),
          settings: settings,
        );

      case '/parent/signup':
        return MaterialPageRoute(
          builder: (_) => ParentSignupScreen(authState: authState),
          settings: settings,
        );

      case '/parent/otp':
        return MaterialPageRoute(
          builder: (_) => EmailOtpScreen(
            authState: authState,
            pendingToken: args['pending_token']?.toString() ??
                authState.pendingToken ??
                '',
            email: args['email']?.toString(),
          ),
          settings: settings,
        );

      case '/parent/liveness':
        return MaterialPageRoute(
          builder: (_) => ParentLivenessScreen(
            authState: authState,
            pendingToken: args['pending_token']?.toString() ??
                authState.pendingToken ??
                '',
            email: args['email']?.toString(),
          ),
          settings: settings,
        );

      case '/parent/children/add':
      case '/parent/add-child':
        return MaterialPageRoute(
          builder: (_) => ChildEnrollmentScreen(authState: authState),
          settings: settings,
        );

      // Kids V2 Main Shell (Home, Explore, Create, Reels, Profile)
      case '/kids/home':
      case '/kids/main':
        return MaterialPageRoute(
          builder: (_) => KidsMainShell(authState: authState),
          settings: settings,
        );

      case '/kids/explore':
        return MaterialPageRoute(
          builder: (_) => ExploreScreen(authState: authState),
          settings: settings,
        );

      case '/kids/feed':
        return MaterialPageRoute(
          builder: (_) => FeedScreen(authState: authState),
          settings: settings,
        );

      case '/kids/reels':
        return MaterialPageRoute(
          builder: (_) => ReelsScreen(authState: authState),
          settings: settings,
        );

      case '/kids/create-post':
        return MaterialPageRoute(
          builder: (_) => CreatePostScreen(
            authState: authState,
            initialKind: args['kind'] == 'reel'
                ? PostKind.reel
                : args['kind'] == 'story'
                    ? PostKind.story
                    : PostKind.post,
          ),
          settings: settings,
        );

      case '/kids/messages':
        return MaterialPageRoute(
          builder: (_) => ChatListScreen(authState: authState),
          settings: settings,
        );

      case '/kids/chat':
        final peerId = args['peer_id'] is int
            ? args['peer_id'] as int
            : int.tryParse(args['peer_id']?.toString() ?? '') ?? 0;
        final peerName = args['peer_name']?.toString() ?? 'Friend';
        final peerAvatarUrl = args['peer_avatar_url']?.toString();
        return MaterialPageRoute(
          builder: (_) => ChatConversationScreen(
            authState: authState,
            peerId: peerId,
            peerName: peerName,
            peerAvatarUrl: peerAvatarUrl,
          ),
          settings: settings,
        );

      case '/kids/chat/details':
      case '/kids/chat/info':
        final peerId = args['peer_id'] is int
            ? args['peer_id'] as int
            : int.tryParse(args['peer_id']?.toString() ?? '') ?? 0;
        final peerName = args['peer_name']?.toString() ?? 'Classmate';
        final peerAvatarUrl = args['peer_avatar_url']?.toString();
        return MaterialPageRoute(
          builder: (_) => ChatDetailsScreen(
            authState: authState,
            peerId: peerId,
            peerName: peerName,
            peerAvatarUrl: peerAvatarUrl,
          ),
          settings: settings,
        );

      case '/kids/story-viewer':
        return MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            authState: authState,
            authorName: args['author_name']?.toString() ?? 'Classmate',
            authorHandle: args['author_handle']?.toString() ?? '@classmate',
            avatarUrl: args['avatar_url']?.toString(),
            mediaUrl: args['media_url']?.toString(),
            caption: args['caption']?.toString() ?? 'Classroom STEM update! 🚀',
          ),
          settings: settings,
        );

      case '/kids/notifications':
        return MaterialPageRoute(
          builder: (_) => NotificationsScreen(authState: authState),
          settings: settings,
        );

      case '/kids/profile':
        return MaterialPageRoute(
          builder: (_) => ProfileScreen(authState: authState),
          settings: settings,
        );

      case '/kids/edit-profile':
        final currentProfile =
            args['current_profile'] as Map<String, dynamic>? ?? const {};
        return MaterialPageRoute(
          builder: (_) => EditProfileScreen(
            authState: authState,
            currentProfile: currentProfile,
          ),
          settings: settings,
        );

      case '/kids/connections':
      case '/kids/followers':
      case '/kids/following':
        return MaterialPageRoute(
          builder: (_) => FollowersFollowingScreen(
            authState: authState,
            initialTab: args['tab_index'] is int
                ? args['tab_index'] as int
                : (settings.name == '/kids/following' ? 1 : 0),
          ),
          settings: settings,
        );

      case '/kids/requests':
        return MaterialPageRoute(
          builder: (_) => RequestsScreen(authState: authState),
          settings: settings,
        );

      case '/kids/settings':
        return MaterialPageRoute(
          builder: (_) => SettingsScreen(authState: authState),
          settings: settings,
        );

      // Learning & Education
      case '/kids/learning':
        return MaterialPageRoute(
          builder: (_) => LearningScreen(authState: authState),
          settings: settings,
        );

      case '/kids/quiz':
        return MaterialPageRoute(
          builder: (_) => QuizScreen(authState: authState),
          settings: settings,
        );

      case '/kids/discover':
        return MaterialPageRoute(
          builder: (_) => DiscoveryScreen(authState: authState),
          settings: settings,
        );

      // Parent Guardian Suite
      case '/parent/dashboard':
        return MaterialPageRoute(
          builder: (_) => ParentDashboardScreen(authState: authState),
          settings: settings,
        );

      case '/parent/controls':
        final childId = rawArgs is int
            ? rawArgs
            : int.tryParse(args['child_id']?.toString() ?? '') ?? 0;
        return MaterialPageRoute(
          builder: (_) => ParentControlsScreen(
            authState: authState,
            childId: childId,
          ),
          settings: settings,
        );

      case '/parent/safety-reviews':
        return MaterialPageRoute(
          builder: (_) => ParentSafetyReviewScreen(authState: authState),
          settings: settings,
        );

      case '/parent/follow-requests':
        return MaterialPageRoute(
          builder: (_) => ParentFollowRequestsScreen(authState: authState),
          settings: settings,
        );

      // Moderator & Admin V2 Suite
      case '/moderator/main':
      case '/moderator/dashboard':
      case '/moderator/queue':
        return MaterialPageRoute(
          builder: (_) => ModeratorMainShell(
            authState: authState,
            onLogout: () => authState.logout(),
          ),
          settings: settings,
        );

      case '/moderator/incident':
        final eventId = args['event_id'] is int
            ? args['event_id'] as int
            : int.tryParse(args['event_id']?.toString() ?? '') ?? 0;
        return MaterialPageRoute(
          builder: (_) => IncidentDetailScreen(
            authState: authState,
            eventId: eventId,
            initialEvent: args['event'] as Map<String, dynamic>?,
          ),
          settings: settings,
        );

      case '/moderator/users':
        return MaterialPageRoute(
          builder: (_) => UserAdminScreen(authState: authState),
          settings: settings,
        );

      case '/moderator/audit':
        return MaterialPageRoute(
          builder: (_) => ModeratorAuditScreen(authState: authState),
          settings: settings,
        );

      default:
        return MaterialPageRoute(
          builder: (_) => LoginScreen(authState: authState),
          settings: settings,
        );
    }
  }
}
