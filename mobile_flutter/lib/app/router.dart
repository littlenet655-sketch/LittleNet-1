import 'package:flutter/material.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/email_otp_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_liveness_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/create_post/create_post_screen.dart';
import '../features/kids/kids_main_shell.dart';
import '../features/parent/child_enrollment_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../screens/admin.dart' as old_admin;
import '../screens/parent.dart' as old_parent;

class AppRouter {
  const AppRouter({required this.authState});

  final AuthState authState;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final args = settings.arguments as Map<String, dynamic>? ?? {};

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

      // Temporary fallback to old screens while remaining V2 modules are under construction
      case '/parent/dashboard':
        return MaterialPageRoute(
          builder: (_) => old_parent.ParentShell(
            api: authState.apiClient,
            user: authState.currentUser?.toJson() ?? const {},
            onLogout: () => authState.logout(),
          ),
          settings: settings,
        );

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
