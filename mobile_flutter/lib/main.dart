import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'screens/auth.dart';
import 'screens/stitch_shells.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  await api.restore();
  runApp(LittleNetApp(api: api));
}

class LittleNetApp extends StatefulWidget {
  const LittleNetApp({super.key, required this.api});

  final ApiClient api;

  @override
  State<LittleNetApp> createState() => _LittleNetAppState();
}

class _LittleNetAppState extends State<LittleNetApp> {
  Map<String, dynamic>? user;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    if (!widget.api.hasToken) {
      setState(() => loading = false);
      return;
    }
    try {
      final data = await widget.api.getJson('/api/mobile/v1/me');
      if (mounted) {
        setState(() {
          user = Map<String, dynamic>.from(data['user'] as Map? ?? const {});
          loading = false;
        });
      }
    } catch (_) {
      await widget.api.clearToken();
      if (mounted) setState(() => loading = false);
    }
  }

  void _signedIn(Map<String, dynamic> signedInUser) {
    setState(() => user = signedInUser);
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LittleNet',
      theme: LittleNetTheme.light(),
      home: loading
          ? const _LaunchScreen()
          : user == null
              ? LoginScreen(api: widget.api, onSignedIn: _signedIn)
              : _roleHome(),
    );
  }

  Widget _roleHome() {
    final role = user?['role']?.toString().toUpperCase();
    if (role == 'PARENT') {
      return StitchParentShell(
        api: widget.api,
        user: user!,
        onLogout: _logout,
      );
    }
    if (role == 'ADMIN') {
      return StitchAdminShell(
        api: widget.api,
        user: user!,
        onLogout: _logout,
      );
    }
    return StitchKidsShell(api: widget.api, user: user!, onLogout: _logout);
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(size: 88),
            SizedBox(height: 18),
            Text(
              'LittleNet',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 18),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: LittleNetTheme.ink,
        borderRadius: BorderRadius.circular(size * .28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220095F6),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.shield_rounded,
        color: LittleNetTheme.primary,
        size: size * .58,
      ),
    );
  }
}
