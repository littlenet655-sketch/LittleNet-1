import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class LearningScreen extends StatefulWidget {
  const LearningScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/learning');
      });

  Future<void> _answer(Map<String, dynamic> challenge) async {
    final controller = TextEditingController();
    final response = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(challenge['title']?.toString() ?? 'Learning challenge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(challenge['prompt']?.toString() ??
                challenge['description']?.toString() ??
                'Complete this challenge.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Your answer'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (response == null) return;
    try {
      final data = await widget.api.postJson(
        '/api/mobile/v1/kids/learning/${challenge['challenge_id']}',
        {'response': response},
      );
      if (!mounted) return;
      toast(
        context,
        data['correct'] == true
            ? 'Great work! +${data['points_awarded'] ?? 0} points'
            : 'Not quite yet. Try again!',
      );
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learning')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(friendlyError(snapshot.error!)),
              ),
            );
          }
          final data = snapshot.data ?? const {};
          final challenges = listMaps(data['challenges']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.auto_awesome_rounded),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Learning points',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              Text('${data['points'] ?? 0}',
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Challenges',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (challenges.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                        child: Text('No learning challenge is due right now.')),
                  ),
                ...challenges.map(
                  (challenge) => Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        child: Icon(challenge['completed'] == true
                            ? Icons.check_rounded
                            : Icons.school_rounded),
                      ),
                      title: Text(challenge['title']?.toString() ?? 'Challenge',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          challenge['description']?.toString() ??
                              challenge['prompt']?.toString() ??
                              '${challenge['points'] ?? 0} points',
                        ),
                      ),
                      trailing: challenge['completed'] == true
                          ? const Icon(Icons.verified_rounded,
                              color: Colors.green)
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: challenge['completed'] == true
                          ? null
                          : () => _answer(challenge),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/kids/notifications');
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            );
          }
          final items = listMaps(snapshot.data?['notifications']);
          if (items.isEmpty) {
            return const Center(child: Text('No new activity yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = items[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  leading: Avatar(
                    api: widget.api,
                    url: item['actor_avatar_url']?.toString(),
                    radius: 22,
                  ),
                  title:
                      Text(item['message']?.toString() ?? 'LittleNet activity'),
                  subtitle: Text(item['created_at']?.toString() ?? ''),
                  trailing: item['is_read'] == false
                      ? const Icon(Icons.circle,
                          size: 10, color: Color(0xFF2563EB))
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
