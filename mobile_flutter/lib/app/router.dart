import 'package:flutter/material.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/email_otp_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_liveness_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/discovery/discovery_screen.dart';
import '../features/kids/kids_main_shell.dart';
import '../features/learning/learning_screen.dart';
import '../features/parent/child_enrollment_screen.dart';
import '../features/parent/parent_controls_screen.dart';
import '../features/parent/parent_dashboard_screen.dart';
import '../features/parent/parent_follow_requests_screen.dart';
import '../features/parent/parent_safety_review_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/settings/settings_screen.dart';
import '../screens/admin.dart' as old_admin;

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

      // Kids V2 Main Shell (Home, Feed, Create Post, Reels, Profile)
      case '/kids/home':
      case '/kids/main':
        return MaterialPageRoute(
          builder: (_) => KidsMainShell(authState: authState),
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

      case '/kids/profile':
        return MaterialPageRoute(
          builder: (_) => ProfileScreen(authState: authState),
          settings: settings,
        );

      case '/kids/settings':
        return MaterialPageRoute(
          builder: (_) => SettingsScreen(authState: authState),
          settings: settings,
        );

      // Module 16: Learning & Quiz
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

      // Module 17: Discovery & Connections
      case '/kids/discover':
        return MaterialPageRoute(
          builder: (_) => DiscoveryScreen(authState: authState),
          settings: settings,
        );

      // Module 18: Parent Dashboard
      case '/parent/dashboard':
        return MaterialPageRoute(
          builder: (_) => ParentDashboardScreen(authState: authState),
          settings: settings,
        );

      // Module 19: Parent Controls
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

      // Module 20: Parent Safety Review & Follow Requests
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

      // Fallback to old screens while remaining V2 modules (Admin/Moderator) are pending
      case '/moderator/queue':
        return MaterialPageRoute(
          builder: (_) => old_admin.AdminShell(
            api: authState.apiClient,
            user: authState.currentUser?.toJson() ?? const {},
            onLogout: () => authState.logout(),
          ),
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
