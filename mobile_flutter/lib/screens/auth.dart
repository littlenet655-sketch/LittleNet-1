import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onSignedIn});
  final ApiClient api;
  final void Function(Map<String, dynamic> user) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  String mode = 'kids';
  bool busy = false;
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (busy) return;
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
      setState(() => error = friendlyError(e));
    } catch (_) {
      setState(() => error = 'Could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _faceLogin() async {
    final id = identifier.text.trim();
    if (id.isEmpty) {
      setState(() => error = 'Enter your username or email first.');
      return;
    }
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
      maxWidth: 1600,
    );
    if (file == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.faceLogin(
        identifier: id,
        mode: mode,
        photo: File(file.path),
      );
      widget.onSignedIn(
          Map<String, dynamic>.from(data['user'] as Map? ?? const {}));
    } on ApiException catch (e) {
      final reason = e.payload?['reason']?.toString();
      if (e.message == 'account_not_found') {
        setState(() => error =
            'Account not found. Create the account first or use password login.');
      } else if (reason != null && reason.isNotEmpty) {
        setState(() => error = reason.replaceAll('_', ' '));
      } else {
        setState(() => error = friendlyError(e));
      }
    } catch (_) {
      setState(
          () => error = 'Face verification could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
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
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const _LoginBrand(),
                      const SizedBox(height: 18),
                      const Text('LittleNet',
                          style: TextStyle(
                              fontSize: 31, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      const Text(
                        'A safe, AI-guided social world for children',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 22),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'kids',
                              label: Text('Kids Mode'),
                              icon: Icon(Icons.child_care_rounded)),
                          ButtonSegment(
                              value: 'parent',
                              label: Text('Parent Mode'),
                              icon: Icon(Icons.shield_outlined)),
                          ButtonSegment(
                              value: 'admin',
                              label: Text('Admin'),
                              icon: Icon(Icons.admin_panel_settings_outlined)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (value) => setState(() {
                          mode = value.first;
                          error = null;
                        }),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFFEEEE),
                              borderRadius: BorderRadius.circular(14)),
                          child: Text(error!,
                              style: const TextStyle(color: Color(0xFFB42318))),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: identifier,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: mode == 'kids'
                              ? 'Username or Child Email'
                              : 'Email or Username',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: password,
                        obscureText: hidePassword,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => hidePassword = !hidePassword),
                            icon: Icon(hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: busy ? null : _login,
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.login_rounded),
                          label: Text(busy ? 'Signing in…' : 'Log In'),
                        ),
                      ),
                      if (mode != 'admin') ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : _faceLogin,
                            icon: const Icon(
                                Icons.face_retouching_natural_rounded),
                            label: const Text('Face ID Login'),
                          ),
                        ),
                      ],
                      if (mode == 'parent') ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () async {
                            final signedIn = await Navigator.of(context)
                                .push<Map<String, dynamic>>(
                              MaterialPageRoute(
                                  builder: (_) => ParentRegistrationScreen(
                                      api: widget.api)),
                            );
                            if (signedIn != null) widget.onSignedIn(signedIn);
                          },
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Parent Sign Up'),
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

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
          color: const Color(0xFF0B0F19),
          borderRadius: BorderRadius.circular(22)),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.shield_rounded, color: Color(0xFF8B5CF6), size: 61),
          Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 27),
        ],
      ),
    );
  }
}

class ParentRegistrationScreen extends StatefulWidget {
  const ParentRegistrationScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ParentRegistrationScreen> createState() =>
      _ParentRegistrationScreenState();
}

class _ParentRegistrationScreenState extends State<ParentRegistrationScreen> {
  final username = TextEditingController();
  final fullName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final dob = TextEditingController();
  bool guardianDeclaration = false;
  bool busy = false;
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    username.dispose();
    fullName.dispose();
    email.dispose();
    password.dispose();
    dob.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Parent / guardian date of birth',
    );
    if (picked != null) {
      dob.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _register() async {
    if (busy) return;
    if (dob.text.isEmpty) {
      setState(() => error = 'Select the parent or guardian date of birth.');
      return;
    }
    if (!guardianDeclaration) {
      setState(
          () => error = 'Confirm that you are the adult parent or guardian.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data =
          await widget.api.postJson('/api/mobile/v1/auth/parent/register', {
        'username': username.text.trim(),
        'full_name': fullName.text.trim(),
        'email': email.text.trim(),
        'password': password.text,
        'dob': dob.text,
        'guardian_declaration': '1',
      });
      if (!mounted) return;
      final signedIn = await Navigator.of(context)
          .pushReplacement<Map<String, dynamic>, Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => ParentVerificationScreen(
            api: widget.api,
            pendingToken: data['pending_token'].toString(),
            initialEmailSent: data['email_sent'] == true,
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
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Create the verified adult account first.',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
              'Email ownership and a live adult camera check are required before Parent Mode activates.'),
          const SizedBox(height: 14),
          if (error != null)
            Card(
              color: const Color(0xFFFFEEEE),
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(error!)),
            ),
          TextField(
              controller: fullName,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          TextField(
              controller: username,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 10),
          TextField(
              controller: email,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 10),
          TextField(
            controller: password,
            obscureText: hidePassword,
            decoration: InputDecoration(
              labelText: 'Password (minimum 8 characters)',
              suffixIcon: IconButton(
                onPressed: () => setState(() => hidePassword = !hidePassword),
                icon: Icon(hidePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: dob,
            readOnly: true,
            onTap: _pickDob,
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              hintText: 'YYYY-MM-DD',
              prefixIcon: Icon(Icons.cake_outlined),
              suffixIcon: Icon(Icons.calendar_month_rounded),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: guardianDeclaration,
            onChanged: (value) =>
                setState(() => guardianDeclaration = value ?? false),
            title:
                const Text('I confirm that I am an adult parent or guardian.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : _register,
            child: Text(busy ? 'Creating…' : 'Continue to email verification'),
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
    required this.initialEmailSent,
  });
  final ApiClient api;
  final String pendingToken;
  final bool initialEmailSent;

  @override
  State<ParentVerificationScreen> createState() =>
      _ParentVerificationScreenState();
}

class _ParentVerificationScreenState extends State<ParentVerificationScreen> {
  final otp = TextEditingController();
  String? pendingToken;
  bool otpVerified = false;
  bool busy = false;
  late bool emailSent;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    pendingToken = widget.pendingToken;
    emailSent = widget.initialEmailSent;
    if (!emailSent) {
      error =
          'The verification email was not delivered. Tap Resend code after the LittleNet mail service is available.';
    }
  }

  @override
  void dispose() {
    otp.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final data =
          await widget.api.postJson('/api/mobile/v1/auth/parent/verify-email', {
        'pending_token': pendingToken,
        'otp': otp.text.trim(),
      });
      setState(() {
        pendingToken = data['pending_token']?.toString() ?? pendingToken;
        otpVerified = true;
      });
    } on ApiException catch (e) {
      setState(() => error = friendlyError(e));
    } catch (_) {
      setState(
          () => error = 'Email verification could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resendOtp() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final data =
          await widget.api.postJson('/api/mobile/v1/auth/parent/resend-email', {
        'pending_token': pendingToken,
      });
      if (data['ok'] == true) {
        setState(() {
          emailSent = true;
          notice =
              'A new 6-digit verification code was sent. Check your inbox and spam folder.';
        });
      } else {
        setState(() => error = data['error']?.toString() ??
            'The verification email could not be sent.');
      }
    } on ApiException catch (e) {
      setState(() => error = friendlyError(e));
    } catch (_) {
      setState(() => error = 'Could not resend the verification email.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _liveness() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 92,
      maxWidth: 1800,
    );
    if (photo == null) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final data = await widget.api.multipart(
        '/api/mobile/v1/auth/parent/verify-liveness',
        fields: {'pending_token': pendingToken ?? ''},
        file: File(photo.path),
        fileField: 'photo',
      );
      final token = data['token']?.toString();
      if (token != null) await widget.api.setToken(token);
      if (!mounted) return;
      Navigator.of(context)
          .pop(Map<String, dynamic>.from(data['user'] as Map? ?? const {}));
    } on ApiException catch (e) {
      setState(() => error =
          e.payload?['reason']?.toString().replaceAll('_', ' ') ??
              friendlyError(e));
    } catch (_) {
      setState(() =>
          error = 'Live adult verification could not connect to LittleNet.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Parent')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (notice != null)
            Card(
              color: const Color(0xFFEFFCF6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(notice!,
                    style: const TextStyle(color: Color(0xFF067647))),
              ),
            ),
          if (error != null)
            Card(
              color: const Color(0xFFFFEEEE),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!,
                    style: const TextStyle(color: Color(0xFFB42318))),
              ),
            ),
          if (!otpVerified) ...[
            Row(
              children: [
                Icon(
                    emailSent
                        ? Icons.mark_email_read_rounded
                        : Icons.mark_email_unread_rounded,
                    color: emailSent ? Colors.green : Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    emailSent
                        ? 'Verification email sent.'
                        : 'Verification email is waiting to be sent.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('Enter the 6-digit code from your email.',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Email OTP'),
            ),
            FilledButton(
                onPressed: busy ? null : _verifyOtp,
                child: Text(busy ? 'Checking…' : 'Verify email')),
            TextButton.icon(
              onPressed: busy ? null : _resendOtp,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Resend code'),
            ),
          ] else ...[
            const Icon(Icons.face_retouching_natural_rounded,
                size: 82, color: Color(0xFF7C3AED)),
            const SizedBox(height: 14),
            const Text('Adult guardian camera check',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text(
              'Use the live front camera in good light. LittleNet verifies adult/liveness before Parent Mode activates.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: busy ? null : _liveness,
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text(busy ? 'Verifying…' : 'Open camera & verify'),
            ),
          ],
        ],
      ),
    );
  }
}
