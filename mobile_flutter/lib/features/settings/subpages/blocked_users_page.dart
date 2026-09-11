import 'package:flutter/material.dart';
import '../../../api.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key, required this.authState});

  final AuthState authState;

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final List<Map<String, dynamic>> _blocked = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/blocked-users',
      );
      final list = (res['blocked_users'] as List<dynamic>?) ?? [];
      setState(() {
        _blocked.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _blocked.add(item);
          }
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load blocked users list.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _unblockUser(int userId, String name) async {
    try {
      await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/block/$userId',
        body: {'action': 'unblock'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unblocked $name')),
      );
      _loadBlocked();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to unblock: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Blocked Users'),
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
            ElevatedButton(onPressed: _loadBlocked, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_blocked.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block_outlined, size: 48, color: Colors.white24),
              const SizedBox(height: AppSpacing.md),
              const Text('No Blocked Users', style: AppTypography.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Users you block will not be able to interact with you, search your profile, or send messages.',
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
      itemCount: _blocked.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final u = _blocked[index];
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
            onPressed: () => _unblockUser(uid, name),
            child: const Text('Unblock'),
          ),
        );
      },
    );
  }
}
