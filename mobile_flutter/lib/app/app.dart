import 'package:flutter/material.dart';
import '../../api.dart';
import '../core/auth/auth_state.dart';
import '../core/upload/upload_manager.dart';
import 'router.dart';
import 'theme.dart';

class LittleNetAppV2 extends StatefulWidget {
  const LittleNetAppV2({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<LittleNetAppV2> createState() => _LittleNetAppV2State();
}

class _LittleNetAppV2State extends State<LittleNetAppV2> {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool _isQuizScreenOpen = false;

  late final ApiClient _apiClient;
  late final AuthState _authState;
  late final AppRouter _router;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? ApiClient();
    _authState = AuthState(apiClient: _apiClient);
    _router = AppRouter(authState: _authState);

    int lastQuizPush = 0;
    ApiClient.onQuizRequired = () {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastQuizPush < 4000) return;
      if (!_isQuizScreenOpen &&
          _authState.isAuthenticated &&
          (_authState.currentUser?.isChild ?? false)) {
        lastQuizPush = now;
        _isQuizScreenOpen = true;
        navigatorKey.currentState?.pushNamed('/kids/quiz').then((_) {
          _isQuizScreenOpen = false;
        });
      }
    };

    ApiClient.onSessionExpired = () {
      if (_authState.isAuthenticated) {
        _authState.logout();
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    };

    _bootstrap();
  }

  void _bootstrap() {
    _authState.init().then((_) {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
        if (_authState.isAuthenticated) {
          UploadManager.instance.reconcilePendingUpload(_apiClient);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _authState,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'LittleNet',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          onGenerateRoute: _router.onGenerateRoute,
          initialRoute: _getInitialRoute(),
        );
      },
    );
  }

  String _getInitialRoute() {
    if (_authState.isAuthenticated) {
      final user = _authState.currentUser;
      if (user != null) {
        if (user.isChild) {
          if (user.quizRequired) return '/kids/quiz';
          return '/kids/home';
        }
        if (user.isParent) return '/parent/dashboard';
        if (user.isAdmin) return '/moderator/queue';
      }
    }
    return '/login';
  }
}
