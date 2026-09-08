import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/kids.dart';
import 'screens/parent.dart';

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
      theme: _theme(),
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
      return ParentShell(api: widget.api, user: user!, onLogout: _logout);
    }
    if (role == 'ADMIN') {
      return AdminShell(api: widget.api, user: user!, onLogout: _logout);
    }
    return KidsShell(api: widget.api, user: user!, onLogout: _logout);
  }
}

ThemeData _theme() {
  const seed = Color(0xFF2563EB);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
    surface: const Color(0xFFFFFBF7),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFFFBF7),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE8EDF5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7F9FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: seed, width: 1.6),
      ),
    ),
  );
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
            Text('LittleNet',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x332563EB), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Icon(Icons.shield_rounded, color: Colors.white, size: size * .56),
    );
  }
}
