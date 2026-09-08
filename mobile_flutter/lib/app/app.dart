import 'package:flutter/material.dart';
import '../../api.dart';
import '../core/auth/auth_state.dart';
import 'router.dart';
import 'theme.dart';

class LittleNetAppV2 extends StatefulWidget {
  const LittleNetAppV2({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<LittleNetAppV2> createState() => _LittleNetAppV2State();
}

class _LittleNetAppV2State extends State<LittleNetAppV2> {
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
    _bootstrap();
  }

  void _bootstrap() {
    _authState.init().then((_) {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
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
        if (user.isChild) return '/kids/home';
        if (user.isParent) return '/parent/dashboard';
        if (user.isAdmin) return '/moderator/queue';
      }
    }
    return '/login';
  }
}
