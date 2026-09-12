import 'package:flutter/foundation.dart';
import '../../api.dart';
import '../models/user.dart';

enum AuthStatus {
  uninitialized,
  unauthenticated,
  pendingVerification,
  authenticated,
}

class AuthState extends ChangeNotifier {
  AuthState({required this.apiClient});

  final ApiClient apiClient;

  AuthStatus _status = AuthStatus.uninitialized;
  User? _currentUser;
  String? _pendingToken;
  String? _errorMessage;

  AuthStatus get status => _status;
  User? get currentUser => _currentUser;
  String? get pendingToken => _pendingToken;
  String? get errorMessage => _errorMessage;

  bool get isAuthenticated =>
      _status == AuthStatus.authenticated && _currentUser != null;
  bool get isPendingVerification => _status == AuthStatus.pendingVerification;

  Future<void> init() async {
    await apiClient.restore();
    if (apiClient.hasToken) {
      try {
        final res = await apiClient.get('/api/mobile/v1/me');
        if (res['ok'] == true && res['user'] != null) {
          _currentUser = User.fromJson(res['user'] as Map<String, dynamic>);
          _status = AuthStatus.authenticated;
          notifyListeners();
          return;
        }
      } catch (_) {
        // Token invalid or expired, clear and continue
        await apiClient.clear();
      }
    }
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void setAuthenticated(User user, String token) {
    _currentUser = user;
    _status = AuthStatus.authenticated;
    _pendingToken = null;
    _errorMessage = null;
    apiClient.setToken(token);
    notifyListeners();
  }

  void setPendingVerification(String pendingToken) {
    _pendingToken = pendingToken;
    _status = AuthStatus.pendingVerification;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (apiClient.hasToken) {
        await apiClient.post('/api/mobile/v1/auth/logout');
      }
    } catch (_) {}
    await apiClient.clear();
    _currentUser = null;
    _pendingToken = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }
}
