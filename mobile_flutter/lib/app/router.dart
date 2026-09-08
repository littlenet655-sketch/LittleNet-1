import 'package:flutter/material.dart';
import '../core/auth/auth_state.dart';
import '../features/auth/email_otp_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/parent_liveness_screen.dart';
import '../features/auth/parent_signup_screen.dart';
import '../screens/admin.dart' as old_admin;
import '../screens/kids.dart' as old_kids;
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

      // Temporary fallback to old screens while remaining V2 modules are under construction
      case '/kids/home':
        return MaterialPageRoute(
          builder: (_) => old_kids.KidsShell(
            api: authState.apiClient,
            user: authState.currentUser?.toJson() ?? const {},
            onLogout: () => authState.logout(),
          ),
          settings: settings,
        );

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
