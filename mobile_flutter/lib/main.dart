import 'package:flutter/material.dart';

import 'api.dart';
import 'app_theme.dart';
import 'screens/stitch_auth.dart';
import 'screens/stitch_kids_shell.dart';
import 'screens/stitch_shells.dart';
import 'stitch_design.dart';

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
              ? StitchLoginScreen(api: widget.api, onSignedIn: _signedIn)
              : _roleHome(),
    );
  }

  Widget _roleHome() {
    final role = user?['role']?.toString().toUpperCase();
    if (role == 'PARENT') {
      return StitchParentShell(api: widget.api, user: user!, onLogout: _logout);
    }
    if (role == 'ADMIN') {
      return StitchAdminShell(api: widget.api, user: user!, onLogout: _logout);
    }
    return StitchKidsShellV2(api: widget.api, user: user!, onLogout: _logout);
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Spacer(flex: 5),
            LittleNetWordmark(fontSize: 40, centered: true),
            SizedBox(height: 12),
            Text(
              'Safe • Supervised • Social',
              style: TextStyle(color: StitchTokens.muted, fontSize: 11),
            ),
            Spacer(flex: 5),
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: StitchTokens.blue),
            ),
            SizedBox(height: 34),
          ],
        ),
      ),
    );
  }
}
