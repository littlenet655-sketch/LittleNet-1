import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';

class ParentControlsScreen extends StatefulWidget {
  const ParentControlsScreen({
    super.key,
    required this.authState,
    required this.childId,
  });

  final AuthState authState;
  final int childId;

  @override
  State<ParentControlsScreen> createState() => _ParentControlsScreenState();
}

class _ParentControlsScreenState extends State<ParentControlsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _successMessage;

  // Feature Toggles
  bool _allowReels = true;
  bool _allowStories = true;
  bool _allowMessaging = true;
  bool _allowPosting = true;
  bool _allowDiscover = true;
  bool _educationalOnlyFeed = false;

  // Quiet Hours
  bool _quietHoursEnabled = false;
  String _quietStart = '21:00';
  String _quietEnd = '07:00';

  // Categories
  List<String> _availableCategories = [];
  Set<String> _selectedCategories = {};

  // Screen Time
  int _dailyLimitMinutes = 60;
  bool _strictMode = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/parent/controls/${widget.childId}',
      );
      if (res['ok'] == true) {
        final ctrl = res['controls'] as Map<String, dynamic>? ?? {};
        final cats = (res['categories'] as List<dynamic>?) ?? [];

        setState(() {
          _allowReels = ctrl['allow_reels'] == true;
          _allowStories = ctrl['allow_stories'] == true;
          _allowMessaging = ctrl['allow_messaging'] == true;
          _allowPosting = ctrl['allow_posting'] == true;
          _allowDiscover = ctrl['allow_discover'] == true;
          _educationalOnlyFeed = ctrl['educational_only_feed'] == true;

          _quietHoursEnabled = ctrl['quiet_hours_enabled'] == true;
          _quietStart = (ctrl['quiet_start'] as String?) ?? '21:00';
          _quietEnd = (ctrl['quiet_end'] as String?) ?? '07:00';

          _availableCategories = cats.map((e) => e.toString()).toList();
          final selected = (ctrl['allowed_categories'] as List<dynamic>?) ?? [];
          _selectedCategories = selected.map((e) => e.toString()).toSet();
          if (_selectedCategories.isEmpty && _availableCategories.isNotEmpty) {
            _selectedCategories = _availableCategories.toSet();
          }

          if (res['time_limit'] != null) {
            final t = res['time_limit'] as Map<String, dynamic>;
            final m = t['daily_limit_minutes'] as int?;
            if (m != null && m >= 15 && m <= 300) {
              _dailyLimitMinutes = m;
            }
            if (t['strict_mode'] != null) {
              _strictMode = t['strict_mode'] == true;
            }
          }
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load controls.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAll() async {
    setState(() {
      _isSaving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      // 1. Save Controls
      final controlsPayload = {
        'allow_reels': _allowReels,
        'allow_stories': _allowStories,
        'allow_messaging': _allowMessaging,
        'allow_posting': _allowPosting,
        'allow_discover': _allowDiscover,
        'educational_only_feed': _educationalOnlyFeed,
        'quiet_hours_enabled': _quietHoursEnabled,
        'quiet_start': _quietStart,
        'quiet_end': _quietEnd,
        'allowed_categories': _selectedCategories.toList(),
      };

      await widget.authState.apiClient.put(
        '/api/mobile/v1/parent/controls/${widget.childId}',
        body: controlsPayload,
      );

      // 2. Save Screen Time Limit
      final limitPayload = {
        'daily_limit_minutes': _dailyLimitMinutes,
        'strict_mode': _strictMode,
      };

      await widget.authState.apiClient.put(
        '/api/mobile/v1/parent/time-limit/${widget.childId}',
        body: limitPayload,
      );

      setState(() {
        _successMessage =
            'Safety controls and time limit updated successfully.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Failed to save parent controls.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final currentStr = isStart ? _quietStart : _quietEnd;
    final parts = currentStr.split(':');
    final initialHour = int.tryParse(parts.first) ?? (isStart ? 21 : 7);
    final initialMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _quietStart = formatted;
        } else {
          _quietEnd = formatted;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: Text('Child Controls (#${widget.childId})'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Text(
                      _error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _successMessage!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildSectionCard(
                  title: 'Daily Screen Time Limit',
                  icon: Icons.hourglass_top,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Allowed Screen Time',
                              style: AppTypography.bodyMedium),
                          Text(
                            '$_dailyLimitMinutes minutes',
                            style: AppTypography.headingMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _dailyLimitMinutes.toDouble(),
                        min: 15,
                        max: 240,
                        divisions: 15,
                        activeColor: AppColors.primary,
                        label: '$_dailyLimitMinutes min',
                        onChanged: (val) {
                          setState(() => _dailyLimitMinutes = val.round());
                        },
                      ),
                      SwitchListTile(
                        title: Text('Strict Lock Mode',
                            style: AppTypography.bodyMedium),
                        subtitle: Text(
                          'Immediately lock app features once limit is reached.',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        value: _strictMode,
                        activeThumbColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) => setState(() => _strictMode = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildSectionCard(
                  title: 'Feature Access Toggles',
                  icon: Icons.toggle_on_outlined,
                  child: Column(
                    children: [
                      _buildToggle(
                        title: 'Allow Reels / Short Videos',
                        subtitle: 'Access to short vertical video feed',
                        value: _allowReels,
                        onChanged: (val) => setState(() => _allowReels = val),
                      ),
                      const Divider(color: AppColors.surfaceLight),
                      _buildToggle(
                        title: 'Allow Stories',
                        subtitle: 'Ephemeral stories viewing and sharing',
                        value: _allowStories,
                        onChanged: (val) => setState(() => _allowStories = val),
                      ),
                      const Divider(color: AppColors.surfaceLight),
                      _buildToggle(
                        title: 'Allow Direct Messaging',
                        subtitle: 'Approved connections chat permission',
                        value: _allowMessaging,
                        onChanged: (val) =>
                            setState(() => _allowMessaging = val),
                      ),
                      const Divider(color: AppColors.surfaceLight),
                      _buildToggle(
                        title: 'Allow Post Creation',
                        subtitle: 'Publishing images, videos, and texts',
                        value: _allowPosting,
                        onChanged: (val) => setState(() => _allowPosting = val),
                      ),
                      const Divider(color: AppColors.surfaceLight),
                      _buildToggle(
                        title: 'Allow Safe Discovery',
                        subtitle: 'Searching and discovering eligible peers',
                        value: _allowDiscover,
                        onChanged: (val) =>
                            setState(() => _allowDiscover = val),
                      ),
                      const Divider(color: AppColors.surfaceLight),
                      _buildToggle(
                        title: 'Educational-Only Feed',
                        subtitle:
                            'Limit feed strictly to verified educational materials',
                        value: _educationalOnlyFeed,
                        onChanged: (val) =>
                            setState(() => _educationalOnlyFeed = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildSectionCard(
                  title: 'Bedtime & Quiet Hours',
                  icon: Icons.nightlight_round,
                  child: Column(
                    children: [
                      _buildToggle(
                        title: 'Quiet Hours Active',
                        subtitle:
                            'Disable app usage during scheduled sleep hours',
                        value: _quietHoursEnabled,
                        onChanged: (val) =>
                            setState(() => _quietHoursEnabled = val),
                      ),
                      if (_quietHoursEnabled) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: const BorderSide(
                                      color: AppColors.surfaceLight),
                                ),
                                onPressed: () => _selectTime(true),
                                icon: const Icon(Icons.bedtime, size: 18),
                                label: Text('Starts: $_quietStart'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  side: const BorderSide(
                                      color: AppColors.surfaceLight),
                                ),
                                onPressed: () => _selectTime(false),
                                icon: const Icon(Icons.wb_sunny, size: 18),
                                label: Text('Ends: $_quietEnd'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _buildSectionCard(
                  title: 'Allowed Content Categories',
                  icon: Icons.category_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select which topics are permitted in your child’s curated feed:',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableCategories.map((cat) {
                          final isSelected = _selectedCategories.contains(cat);
                          return FilterChip(
                            label: Text(cat.toUpperCase()),
                            selected: isSelected,
                            selectedColor:
                                AppColors.primary.withValues(alpha: 0.2),
                            checkmarkColor: AppColors.primary,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            backgroundColor:
                                AppColors.surfaceLight.withValues(alpha: 0.1),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCategories.add(cat);
                                } else {
                                  if (_selectedCategories.length > 1) {
                                    _selectedCategories.remove(cat);
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveAll,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    _isSaving
                        ? 'Saving Controls...'
                        : 'Save All Guardian Controls',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _showResetChildPasswordDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.lock_reset_rounded),
                  label: const Text(
                    'Change / Reset Child Password',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _unlinkChild,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text(
                    'Remove / Unlink Child Account',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border:
              Border.all(color: AppColors.surfaceLight.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(title, style: AppTypography.headingMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: AppTypography.bodyMedium),
      subtitle: Text(
        subtitle,
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      value: value,
      activeThumbColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }

  Future<void> _showResetChildPasswordDialog() async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? dialogError;
    bool isUpdating = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_reset_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Reset Child Password'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Set a new password for this child account. The child can immediately use this new password to sign in.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      hintText: 'At least 8 characters',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      hintText: 'Re-enter new password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUpdating ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isUpdating
                    ? null
                    : () async {
                        final pwd = passwordController.text.trim();
                        final confirm = confirmController.text.trim();
                        if (pwd.length < 8) {
                          setDialogState(() => dialogError = 'Password must be at least 8 characters.');
                          return;
                        }
                        if (pwd != confirm) {
                          setDialogState(() => dialogError = 'Passwords do not match.');
                          return;
                        }

                        setDialogState(() {
                          isUpdating = true;
                          dialogError = null;
                        });

                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final res = await widget.authState.apiClient.post(
                            '/api/mobile/v1/parent/child/${widget.childId}/reset-password',
                            body: {'new_password': pwd},
                          );
                          if (res['ok'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Child password has been reset successfully.')),
                            );
                          } else {
                            setDialogState(() {
                              isUpdating = false;
                              dialogError = res['error']?.toString() ?? 'Failed to update password.';
                            });
                          }
                        } catch (e) {
                          setDialogState(() {
                            isUpdating = false;
                            dialogError = 'Failed to reset password. Check connection.';
                          });
                        }
                      },
                child: isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Update Password'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _unlinkChild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Child Account?'),
        content: const Text(
          'Are you sure you want to remove this child from your parent dashboard? Their account access will be deactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove Child'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final res = await widget.authState.apiClient.delete(
        '/api/mobile/v1/parent/child/${widget.childId}',
      );
      if (res['ok'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Child account successfully unlinked.')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to unlink child account.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
