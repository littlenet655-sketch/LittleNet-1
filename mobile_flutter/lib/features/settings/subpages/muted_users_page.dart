import 'package:flutter/material.dart';
import '../../../api.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class MutedUsersPage extends StatefulWidget {
  const MutedUsersPage({super.key, required this.authState});

  final AuthState authState;

  @override
  State<MutedUsersPage> createState() => _MutedUsersPageState();
}

class _MutedUsersPageState extends State<MutedUsersPage> {
  final List<Map<String, dynamic>> _muted = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMuted();
  }

  Future<void> _loadMuted() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/muted-users',
      );
      final list = (res['muted_users'] as List<dynamic>?) ?? [];
      setState(() {
        _muted.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _muted.add(item);
          }
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load muted users.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unmuteUser(int userId, String name) async {
    try {
      await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/mute/$userId',
        body: {'action': 'unmute'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unmuted $name')),
      );
      _loadMuted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unmute: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Muted Users'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: AppTypography.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(onPressed: _loadMuted, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_muted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.volume_off_outlined,
                  size: 48, color: Colors.white24),
              const SizedBox(height: AppSpacing.md),
              const Text('No Muted Users', style: AppTypography.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Posts from muted users are hidden from your feed without letting them know.',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textMutedDark),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _muted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final u = _muted[index];
        final uid = u['user_id'] as int? ?? 0;
        final name =
            u['full_name'] as String? ?? u['username'] as String? ?? 'User';
        final username = u['username'] as String? ?? '';
        final avatar = u['avatar_url'] as String?;

        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white10,
            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
            child: avatar == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                : null,
          ),
          title: Text(name, style: AppTypography.titleSmall),
          subtitle: Text('@$username',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textMutedDark)),
          trailing: TextButton(
            onPressed: () => _unmuteUser(uid, name),
            child: const Text('Unmute'),
          ),
        );
      },
    );
  }
}
