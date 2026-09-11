import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_scaffold.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/biometrics/face_biometrics.dart';

class ChildEnrollmentScreen extends StatefulWidget {
  const ChildEnrollmentScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ChildEnrollmentScreen> createState() => _ChildEnrollmentScreenState();
}

class _ChildEnrollmentScreenState extends State<ChildEnrollmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _ageController = TextEditingController();
  final _passwordController = TextEditingController();

  String _safetyLevel = 'STRICT';
  int _dailyLimit = 60;
  bool _allowReels = true;
  bool _allowStories = true;
  bool _allowMessaging = true;
  bool _educationalOnly = false;

  bool _isLoading = false;
  String? _error;
  int? _createdChildId;
  String? _successMessage;

  // Face enrollment step
  final ImagePicker _picker = ImagePicker();
  bool _isFaceEnrolling = false;
  String? _faceStatus;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _ageController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateChild() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/parent/children',
        body: {
          'full_name': _nameController.text.trim(),
          'username': _usernameController.text.trim().toLowerCase(),
          'age': int.parse(_ageController.text.trim()),
          'password': _passwordController.text,
          'safety_level': _safetyLevel,
          'daily_limit': _dailyLimit,
          'allow_reels': _allowReels,
          'allow_stories': _allowStories,
          'allow_messaging': _allowMessaging,
          'educational_only_feed': _educationalOnly,
        },
      );

      if (res['ok'] == true && res['child_id'] != null) {
        setState(() {
          _createdChildId = res['child_id'] as int;
          _successMessage =
              'Child account created! Now capture a reference photo for facial security login.';
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = _formatError(e.message));
    } catch (_) {
      setState(() => _error =
          'Failed to create child account. Please check your network.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleEnrollChildFace() async {
    if (_createdChildId == null) return;
    setState(() {
      _isFaceEnrolling = true;
      _error = null;
      _faceStatus = null;
    });

    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 85,
      );
      if (photo == null) {
        setState(() => _isFaceEnrolling = false);
        return;
      }

      final bytes = await photo.readAsBytes();
      final photoB64 = base64Encode(bytes);

      // Parent-assisted child face enrollment
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/parent/children/$_createdChildId/face/enroll',
        body: {'photo_b64': photoB64},
      );

      if (res['ok'] == true && _createdChildId != null) {
        try {
          final inputImage = InputImage.fromFilePath(photo.path);
          final detector = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true));
          final faces = await detector.processImage(inputImage);
          if (faces.isNotEmpty) {
            final neural = await LocalFaceBiometrics.extractNeuralEmbedding(bytes, faces.first);
            await LocalFaceBiometrics.saveTemplate(_createdChildId!, neural);
          }
          detector.close();
          if (res['biometric_key'] != null) {
            await LocalFaceBiometrics.saveBiometricKey(_createdChildId!, res['biometric_key'].toString());
          }
        } catch (_) {}
      }

      final quizRequired = res['quiz_required'] == true;
      setState(() {
        _faceStatus = quizRequired
            ? 'Face enrolled successfully! Onboarding quiz will welcome your child on their first sign in.'
            : 'Face enrolled successfully! Your child is ready to sign in.';
      });
    } on ApiException catch (e) {
      setState(() {
        _faceStatus =
            'Face enrollment failed: ${e.message}. You can retry or complete it later.';
      });
    } catch (_) {
      setState(() {
        _faceStatus =
            'Child profile created! Facial setup can also be completed when the child signs in.';
      });
    } finally {
      if (mounted) setState(() => _isFaceEnrolling = false);
    }
  }

  String _formatError(String code) {
    if (code.contains('already exists') ||
        code.contains('duplicate') ||
        code.contains('already taken') ||
        code.contains('username_taken')) {
      return 'This username is already taken. Please choose another.';
    }
    if (code.contains('safe characters')) {
      return 'Username must be 3-30 safe letters, numbers, or underscores.';
    }
    if (code.contains('valid child name')) {
      return 'Please enter a valid full name for your child (letters only).';
    }
    if (code.contains('between 4 and 18')) {
      return 'LittleNet is designed for children aged 4 to 18.';
    }
    if (code.contains('at least 8 characters')) {
      return 'Password must be at least 8 characters long.';
    }
    if (code.contains('safety rules')) {
      return 'Profile text could not be accepted under child-safety rules.';
    }
    if (code.contains('verified active Parent')) {
      return 'Parent verification is required before creating a child account.';
    }
    if (code.contains('child_creation_failed')) {
      return 'Unable to create child account. The username may already be taken, or required fields are invalid.';
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Add Child Profile'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.kidsAccent.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.child_care_rounded,
                              size: 32,
                              color: AppColors.kidsAccent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Create Child Account',
                                    style: AppTypography.titleLarge),
                                Text(
                                  'Protected by LittleNet Parent Safety Controls',
                                  style: AppTypography.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.error),
                          ),
                          child: Text(
                            _error!,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.error),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      if (_successMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.success),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _successMessage!,
                                style: AppTypography.bodyMedium
                                    .copyWith(color: AppColors.success),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AppButton(
                                text: 'Enroll Child Face ID (Optional)',
                                icon: Icons.face_rounded,
                                isLoading: _isFaceEnrolling,
                                onPressed: _handleEnrollChildFace,
                              ),
                              if (_faceStatus != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  _faceStatus!,
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.success),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),
                              AppButton(
                                text: 'Done / Return to Dashboard',
                                variant: ButtonVariant.secondary,
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Child Profile Inputs
                        AppTextField(
                          label: 'Child Full Name',
                          hint: 'e.g. Maya Sharma',
                          controller: _nameController,
                          prefixIcon: Icons.person_outline,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter child\'s full name'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),

                        AppTextField(
                          label: 'Username',
                          hint: 'e.g. maya_explorer',
                          controller: _usernameController,
                          prefixIcon: Icons.alternate_email,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter a username';
                            }
                            if (v.trim().length < 3) {
                              return 'At least 3 characters required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: AppTextField(
                                label: 'Age (4-18)',
                                hint: 'e.g. 10',
                                controller: _ageController,
                                keyboardType: TextInputType.number,
                                prefixIcon: Icons.cake_outlined,
                                validator: (v) {
                                  final n = int.tryParse(v ?? '');
                                  if (n == null || n < 4 || n > 18) {
                                    return 'Age 4-18';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              flex: 2,
                              child: AppTextField(
                                label: 'Initial Password',
                                hint: 'Min 8 characters',
                                controller: _passwordController,
                                isPassword: true,
                                prefixIcon: Icons.lock_outline,
                                validator: (v) => (v == null || v.length < 8)
                                    ? 'Min 8 characters'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Safety Presets
                        const Text('Parent Safety Level',
                            style: AppTypography.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        DropdownButtonFormField<String>(
                          initialValue: _safetyLevel,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'STRICT',
                              child: Text('Strict (Under 13)',
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'VERY_STRICT',
                              child: Text('Very Strict (Educational only)',
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'STANDARD',
                              child: Text('Standard (13+ with oversight)',
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _safetyLevel = v ?? 'STRICT'),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Screen Time Limit
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text('Daily Screen Time Limit',
                                  style: AppTypography.titleMedium,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text('$_dailyLimit min',
                                style: AppTypography.labelLarge),
                          ],
                        ),
                        Slider(
                          value: _dailyLimit.toDouble(),
                          min: 15,
                          max: 240,
                          divisions: 15,
                          label: '$_dailyLimit min',
                          onChanged: (v) =>
                              setState(() => _dailyLimit = v.round()),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Feature Toggles
                        SwitchListTile(
                          title: const Text('Allow Short Videos (Reels)'),
                          subtitle:
                              const Text('Curated and parent-approved only'),
                          value: _allowReels,
                          onChanged: (v) => setState(() => _allowReels = v),
                        ),
                        SwitchListTile(
                          title: const Text('Allow Safe Stories'),
                          subtitle:
                              const Text('24-hour photo and video moments'),
                          value: _allowStories,
                          onChanged: (v) => setState(() => _allowStories = v),
                        ),
                        SwitchListTile(
                          title: const Text('Allow Safe Messaging'),
                          subtitle: const Text(
                              'Only with parent-approved classmates'),
                          value: _allowMessaging,
                          onChanged: (v) => setState(() => _allowMessaging = v),
                        ),
                        SwitchListTile(
                          title: const Text('Educational-Only Feed'),
                          subtitle:
                              const Text('Prioritize STEM, reading, and arts'),
                          value: _educationalOnly,
                          onChanged: (v) =>
                              setState(() => _educationalOnly = v),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        AppButton(
                          text: 'Submit Registration',
                          isLoading: _isLoading,
                          onPressed: _handleCreateChild,
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
