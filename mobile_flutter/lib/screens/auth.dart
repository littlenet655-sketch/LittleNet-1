import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';

typedef SignedInCallback = void Function(Map<String, dynamic> user);

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onSignedIn,
  });

  final ApiClient api;
  final SignedInCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  String mode = 'kids';
  bool busy = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (identifier.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your username/email and password.');
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
      final user = Map<String, dynamic>.from(data['user'] as Map? ?? const {});
      widget.onSignedIn(user);
    } on ApiException catch (e) {
      if (e.message == 'parent_verification_required' &&
          e.payload?['pending_token'] != null &&
          mounted) {
        final user = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (_) => ParentVerificationScreen(
              api: widget.api,
              pendingToken: e.payload!['pending_token'].toString(),
            ),
          ),
        );
        if (user != null) widget.onSignedIn(user);
      } else {
        setState(() => error = _friendlyError(e.message));
      }
    } catch (_) {
      setState(() => error = 'Could not connect to LittleNet. Check your internet connection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _faceLogin() async {
    if (identifier.text.trim().isEmpty) {
      setState(() => error = 'Enter your username/email first, then use Face ID.');
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 88,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.faceLogin(
        identifier: identifier.text.trim(),
        mode: mode,
        photo: File(picked.path),
      );
      widget.onSignedIn(
        Map<String, dynamic>.from(data['user'] as Map? ?? const {}),
      );
    } on ApiException catch (e) {
      setState(() => error = _friendlyError(e.message));
    } catch (_) {
      setState(() => error = 'Face ID could not connect. Use password login.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _friendlyError(String value) {
    switch (value) {
      case 'invalid_credentials':
        return 'Invalid username/email or password.';
      case 'wrong_mode':
        return 'This account belongs to a different mode.';
      case 'account_inactive':
        return 'This account is not active.';
      case 'face_login_failed':
        return 'Face ID did not match. Try again in good lighting.';
      case 'account_not_found':
        return 'Account not found or not active.';
      default:
        return value.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandHeader(),
                      const SizedBox(height: 24),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'kids',
                            icon: Icon(Icons.child_care_rounded),
                            label: Text('Kids Mode'),
                          ),
                          ButtonSegment(
                            value: 'parent',
                            icon: Icon(Icons.shield_outlined),
                            label: Text('Parent Mode'),
                          ),
                        ],
                        selected: {mode},
                        onSelectionChanged: busy
                            ? null
                            : (value) => setState(() {
                                  mode = value.first;
                                  error = null;
                                }),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Color(0xFF991B1B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        controller: identifier,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: mode == 'kids'
                              ? 'Username or Child Email'
                              : 'Parent Email or Username',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: obscure,
                        onSubmitted: (_) => busy ? null : _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: busy ? null : _login,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Log In'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _faceLogin,
                        icon: const Icon(Icons.face_retouching_natural_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Face ID Login'),
                        ),
                      ),
                      if (mode == 'parent') ...[
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final signedIn = await Navigator.of(context)
                                      .push<Map<String, dynamic>>(
                                    MaterialPageRoute(
                                      builder: (_) => ParentRegistrationScreen(api: widget.api),
                                    ),
                                  );
                                  if (signedIn != null) widget.onSignedIn(signedIn);
                                },
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Create Parent Account'),
                        ),
                      ],
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

class ParentRegistrationScreen extends StatefulWidget {
  const ParentRegistrationScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ParentRegistrationScreen> createState() => _ParentRegistrationScreenState();
}

class _ParentRegistrationScreenState extends State<ParentRegistrationScreen> {
  final username = TextEditingController();
  final fullName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    username.dispose();
    fullName.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.postJson('/api/mobile/v1/auth/parent/register', {
        'username': username.text.trim(),
        'full_name': fullName.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
      });
      if (!mounted) return;
      final signedIn = await Navigator.of(context).pushReplacement<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => ParentVerificationScreen(
            api: widget.api,
            pendingToken: data['pending_token'].toString(),
          ),
        ),
      );
      if (signedIn != null && mounted) Navigator.of(context).pop(signedIn);
    } on ApiException catch (e) {
      setState(() => error = e.message.replaceAll('_', ' '));
    } catch (_) {
      setState(() => error = 'Registration could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parent Sign Up')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Create the adult account first',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('Email verification and a live adult Face ID check are required before Parent Mode activates.'),
          const SizedBox(height: 22),
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          TextField(controller: fullName, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : _register,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(busy ? 'Creating...' : 'Continue to Verification'),
            ),
          ),
        ],
      ),
    );
  }
}

class ParentVerificationScreen extends StatefulWidget {
  const ParentVerificationScreen({
    super.key,
    required this.api,
    required this.pendingToken,
  });

  final ApiClient api;
  final String pendingToken;

  @override
  State<ParentVerificationScreen> createState() => _ParentVerificationScreenState();
}

class _ParentVerificationScreenState extends State<ParentVerificationScreen> {
  final otp = TextEditingController();
  late String pendingToken;
  bool emailVerified = false;
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    pendingToken = widget.pendingToken;
  }

  @override
  void dispose() {
    otp.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final data = await widget.api.postJson('/api/mobile/v1/auth/parent/verify-email', {
        'pending_token': pendingToken,
        'otp': otp.text.trim(),
      });
      pendingToken = data['pending_token'].toString();
      setState(() {
        emailVerified = true;
        message = 'Email verified. Complete the live adult Face ID check.';
      });
    } on ApiException catch (e) {
      setState(() => message = e.message.replaceAll('_', ' '));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await widget.api.postJson('/api/mobile/v1/auth/parent/resend-email', {
        'pending_token': pendingToken,
      });
      setState(() => message = 'A new code was sent.');
    } on ApiException catch (e) {
      setState(() => message = e.message.replaceAll('_', ' '));
    }
  }

  Future<void> _verifyFace() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
      maxWidth: 1280,
    );
    if (picked == null) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final data = await widget.api.multipart(
        '/api/mobile/v1/auth/parent/verify-liveness',
        fields: {'pending_token': pendingToken},
        file: File(picked.path),
        fileField: 'photo',
      );
      final token = data['token']?.toString();
      if (token != null) await widget.api.setToken(token);
      if (!mounted) return;
      Navigator.of(context).pop(
        Map<String, dynamic>.from(data['user'] as Map? ?? const {}),
      );
    } on ApiException catch (e) {
      setState(() => message = e.message.replaceAll('_', ' '));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Parent')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            emailVerified ? Icons.face_rounded : Icons.mark_email_read_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 18),
          Text(
            emailVerified ? 'Live adult verification' : 'Check your email',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            emailVerified
                ? 'Use the front camera. LittleNet verifies liveness/adult status and enrolls Parent Face ID.'
                : 'Enter the 6-digit verification code sent to your parent email.',
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 18),
            Text(message!, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          if (!emailVerified) ...[
            TextField(
              controller: otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Verification code'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: busy ? null : _verifyOtp, child: const Text('Verify Email')),
            TextButton(onPressed: busy ? null : _resend, child: const Text('Resend code')),
          ] else
            FilledButton.icon(
              onPressed: busy ? null : _verifyFace,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Start Live Camera Verification'),
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircleAvatar(
          radius: 38,
          backgroundColor: Color(0xFFE0F2FE),
          child: Icon(Icons.shield_rounded, size: 42, color: Color(0xFF2563EB)),
        ),
        SizedBox(height: 14),
        Text('LittleNet', style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900)),
        SizedBox(height: 4),
        Text('A safe, AI-guided social world for children', textAlign: TextAlign.center),
      ],
    );
  }
}
