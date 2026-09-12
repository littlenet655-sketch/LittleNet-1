import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_scaffold.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.authState,
    required this.currentProfile,
  });

  final AuthState authState;
  final Map<String, dynamic> currentProfile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _schoolController;
  late final TextEditingController _classController;
  late final TextEditingController _locationController;
  late final TextEditingController _skillsController;
  late final TextEditingController _interestsController;
  late final TextEditingController _ambitionsController;

  bool _isSaving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    final p = widget.currentProfile;
    _nameController =
        TextEditingController(text: p['full_name']?.toString() ?? '');
    _bioController = TextEditingController(text: p['bio']?.toString() ?? '');
    _schoolController =
        TextEditingController(text: p['school_name']?.toString() ?? '');
    _classController =
        TextEditingController(text: p['current_class']?.toString() ?? '');
    _locationController =
        TextEditingController(text: p['location']?.toString() ?? '');

    final skills = (p['skills'] as List<dynamic>?)?.join(', ') ?? '';
    final interests = (p['interests'] as List<dynamic>?)?.join(', ') ?? '';
    final ambitions = (p['ambitions'] as List<dynamic>?)?.join(', ') ?? '';

    _skillsController = TextEditingController(text: skills);
    _interestsController = TextEditingController(text: interests);
    _ambitionsController = TextEditingController(text: ambitions);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _schoolController.dispose();
    _classController.dispose();
    _locationController.dispose();
    _skillsController.dispose();
    _interestsController.dispose();
    _ambitionsController.dispose();
    super.dispose();
  }

  List<String> _splitTags(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _error = null;
      _success = null;
    });

    try {
      final res = await widget.authState.apiClient.putJson(
        '/api/mobile/v1/kids/profile',
        {
          'full_name': _nameController.text.trim(),
          'bio': _bioController.text.trim(),
          'school_name': _schoolController.text.trim(),
          'current_class': _classController.text.trim(),
          'location': _locationController.text.trim(),
          'skills': _splitTags(_skillsController.text),
          'interests': _splitTags(_interestsController.text),
          'ambitions': _splitTags(_ambitionsController.text),
        },
      );

      if (res['ok'] == true) {
        setState(() {
          _success =
              'Profile updated successfully! Any new tags have been sent for parental notification.';
        });
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (e.message.contains('pii')) {
        setState(() => _error =
            'For your safety, phone numbers, home addresses, or private details cannot be included in your profile.');
      } else if (e.message.contains('safety')) {
        setState(() => _error =
            'Your profile text could not be approved under LittleNet safety standards.');
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error = 'Network error while saving profile.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(_error!,
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.error)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_success != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.success),
                  ),
                  child: Text(_success!,
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.success)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                label: 'Full Name',
                hint: 'Your display name',
                controller: _nameController,
                prefixIcon: Icons.person_outline,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Bio',
                hint: 'Share what you enjoy learning or building...',
                controller: _bioController,
                maxLines: 3,
                prefixIcon: Icons.edit_outlined,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'School / Academy',
                hint: 'e.g. Oakridge International',
                controller: _schoolController,
                prefixIcon: Icons.school_outlined,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Grade / Class',
                      hint: 'e.g. Grade 5',
                      controller: _classController,
                      prefixIcon: Icons.grade_outlined,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      label: 'City / Region',
                      hint: 'e.g. Bengaluru',
                      controller: _locationController,
                      prefixIcon: Icons.location_on_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Tags (comma separated)',
                  style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                label: 'Interests',
                hint: 'Astronomy, Robotics, Painting',
                controller: _interestsController,
                prefixIcon: Icons.interests_outlined,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Skills',
                hint: 'Python, Chess, Violin',
                controller: _skillsController,
                prefixIcon: Icons.auto_awesome_outlined,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Ambitions',
                hint: 'Scientist, Game Designer, Author',
                controller: _ambitionsController,
                prefixIcon: Icons.flag_outlined,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                text: 'Save Profile Changes',
                icon: Icons.save_rounded,
                isLoading: _isSaving,
                onPressed: _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
