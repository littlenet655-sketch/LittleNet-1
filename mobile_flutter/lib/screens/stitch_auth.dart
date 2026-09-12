import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../stitch_design.dart';
import '../widgets.dart';
import 'auth.dart' show ParentRegistrationScreen;

class StitchLoginScreen extends StatefulWidget {
  const StitchLoginScreen({super.key, required this.api, required this.onSignedIn});

  final ApiClient api;
  final void Function(Map<String, dynamic> user) onSignedIn;

  @override
  State<StitchLoginScreen> createState() => _StitchLoginScreenState();
}

class _StitchLoginScreenState extends State<StitchLoginScreen> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  String mode = 'kids';
  bool busy = false;
  bool hidePassword = true;
  String? error;

  bool get isParent => mode == 'parent';
  bool get isAdmin => mode == 'admin';

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (busy) return;
    if (identifier.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your account and passcode.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.login(
        identifier: identifier.text.trim(),
        password: password.text,
        mode: mode,
      );
      widget.onSignedIn(Map<String, dynamic>.from(data['user'] as Map? ?? const {}));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } catch (_) {
      if (mounted) setState(() => error = 'Could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _faceLogin() async {
    if (identifier.text.trim().isEmpty) {
      setState(() => error = 'Enter your school handle, nickname, or email first.');
      return;
    }
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (photo == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.faceLogin(
        identifier: identifier.text.trim(),
        mode: mode,
        photo: File(photo.path),
      );
      widget.onSignedIn(Map<String, dynamic>.from(data['user'] as Map? ?? const {}));
    } on ApiException catch (e) {
      final reason = e.payload?['reason']?.toString();
      if (mounted) {
        setState(() => error = reason?.replaceAll('_', ' ') ?? friendlyError(e));
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Face verification could not connect.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _parentSignup() async {
    final signedIn = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => ParentRegistrationScreen(api: widget.api)),
    );
    if (signedIn != null) widget.onSignedIn(signedIn);
  }

  void _setMode(String value) {
    setState(() {
      mode = value;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 46),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: 'English (US)',
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                            style: const TextStyle(color: StitchTokens.ink, fontSize: 12),
                            items: const [
                              DropdownMenuItem(value: 'English (US)', child: Text('English (US)')),
                            ],
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      const LittleNetWordmark(fontSize: 34, centered: true),
                      const SizedBox(height: 9),
                      const Text(
                        'Safe & Supervised Social Space',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: StitchTokens.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 28),
                      if (!isAdmin)
                        Container(
                          height: 36,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F3F3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ModeButton(
                                  selected: mode == 'kids',
                                  icon: Icons.face_rounded,
                                  label: 'Child Login',
                                  onTap: () => _setMode('kids'),
                                ),
                              ),
                              Expanded(
                                child: _ModeButton(
                                  selected: mode == 'parent',
                                  icon: Icons.family_restroom_rounded,
                                  label: 'Parent Login',
                                  onTap: () => _setMode('parent'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (isAdmin)
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _setMode('kids'),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const Expanded(
                              child: Text(
                                'Admin / Moderator Login',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 48),
                          ],
                        ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: identifier,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          hintText: mode == 'kids'
                              ? 'School handle, nickname, or email'
                              : 'Email or username',
                          prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        ),
                      ),
                      const SizedBox(height: 9),
                      TextField(
                        controller: password,
                        obscureText: hidePassword,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          hintText: mode == 'kids' ? 'Passcode or kid secret word' : 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => hidePassword = !hidePassword),
                            icon: Icon(
                              hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 19,
                            ),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF0F0),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Color(0xFFB42318), fontSize: 12),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: busy ? null : _login,
                        child: busy
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Log In'),
                      ),
                      const SizedBox(height: 11),
                      TextButton(
                        onPressed: () {},
                        child: Text(isParent ? 'Forgot password?' : 'Forgot password or need Parent Help?'),
                      ),
                      if (!isAdmin) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 11),
                          child: Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR', style: TextStyle(color: StitchTokens.muted, fontSize: 11)),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: busy ? null : _faceLogin,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF6F6F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const LittleNetFaceMark(size: 36, background: Color(0xFFFFE8E8)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
                                          Text('Instant Face Login', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                                          SizedBox(width: 7),
                                          StitchStatusPill(
                                            text: 'SPEEDY',
                                            tone: StitchTokens.classroom,
                                            foreground: StitchTokens.link,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        mode == 'kids'
                                            ? 'Quick camera recognition for your class'
                                            : 'Quick camera recognition for Parent Mode',
                                        style: const TextStyle(color: StitchTokens.muted, fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (isParent)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Don't have an account?", style: TextStyle(color: StitchTokens.muted, fontSize: 12)),
                            TextButton(onPressed: _parentSignup, child: const Text('Sign up')),
                          ],
                        ),
                      if (mode == 'kids')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Need Parent Mode?', style: TextStyle(color: StitchTokens.muted, fontSize: 12)),
                            TextButton(onPressed: () => _setMode('parent'), child: const Text('Parent Login')),
                          ],
                        ),
                      if (!isAdmin)
                        Center(
                          child: TextButton.icon(
                            onPressed: () => _setMode('admin'),
                            icon: const Icon(Icons.admin_panel_settings_outlined, size: 15),
                            label: const Text('Admin / Moderator'),
                          ),
                        ),
                      const SizedBox(height: 34),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 14, color: StitchTokens.muted),
                          SizedBox(width: 5),
                          Text(
                            'Guardian Shield • School Verified Safe',
                            style: TextStyle(color: StitchTokens.muted, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? StitchTokens.blue : StitchTokens.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? StitchTokens.blue : StitchTokens.ink,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
