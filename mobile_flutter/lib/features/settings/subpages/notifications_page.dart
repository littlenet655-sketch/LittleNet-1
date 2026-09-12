import 'package:flutter/material.dart';
import '../../../api.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/gradient_scaffold.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.authState});

  final AuthState authState;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/notifications',
      );
      final list = (res['notifications'] as List<dynamic>?) ?? [];
      setState(() {
        _notifications.clear();
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _notifications.add(item);
          }
        }
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load notifications.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Notifications 🔔'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadNotifications,
          ),
        ],
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
            ElevatedButton(
              onPressed: _loadNotifications,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 48, color: Colors.white24),
            const SizedBox(height: AppSpacing.md),
            const Text('All Caught Up!', style: AppTypography.titleMedium),
            const SizedBox(height: 4),
            Text(
              'No new alerts or activity notifications.',
              style: AppTypography.caption
                  .copyWith(color: AppColors.textMutedDark),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _notifications[index];
        final title = item['notification_type'] as String? ?? 'Notice';
        final message = item['message'] as String? ?? '';
        final avatar = item['actor_avatar_url'] as String?;

        return ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
            backgroundImage: avatar != null ? NetworkImage(avatar) : null,
            child: avatar == null
                ? const Icon(Icons.notifications,
                    color: AppColors.kidsAccent, size: 20)
                : null,
          ),
          title: Text(title, style: AppTypography.titleSmall),
          subtitle: Text(message, style: AppTypography.bodyMedium),
        );
      },
    );
  }
}
