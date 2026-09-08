import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int index = 0;
  int refresh = 0;

  void refreshAll() => setState(() => refresh++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      AdminDashboard(api: widget.api, refreshToken: refresh),
      AdminReviews(api: widget.api, refreshToken: refresh, onChanged: refreshAll),
      AdminUsers(api: widget.api, refreshToken: refresh),
      AdminAudit(api: widget.api, refreshToken: refresh),
      _AdminSettings(user: widget.user, onLogout: widget.onLogout),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.rule_folder_outlined), selectedIcon: Icon(Icons.rule_folder_rounded), label: 'Queue'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Users'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Audit'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/admin/dashboard');
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
          final counts = Map<String, dynamic>.from(snapshot.data?['counts'] as Map? ?? const {});
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF7C3AED), size: 32),
                    SizedBox(width: 10),
                    Expanded(child: Text('Moderator Console', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Human review for content the safety system could not confidently decide.', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.55,
                  children: [
                    _Stat(label: 'All users', value: counts['users'], icon: Icons.people_alt_outlined),
                    _Stat(label: 'Children', value: counts['children'], icon: Icons.child_care_rounded),
                    _Stat(label: 'Parents', value: counts['parents'], icon: Icons.family_restroom_rounded),
                    _Stat(label: 'Open reviews', value: counts['open_reviews'], icon: Icons.gpp_maybe_outlined),
                  ],
                ),
                const SizedBox(height: 18),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('Moderator decisions are server-side'),
                    subtitle: Text('Approve, Block and Escalate actions are recorded in the moderation review trail.'),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label;
  final dynamic value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${value ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminReviews extends StatefulWidget {
  const AdminReviews({super.key, required this.api, required this.refreshToken, required this.onChanged});
  final ApiClient api;
  final int refreshToken;
  final VoidCallback onChanged;

  @override
  State<AdminReviews> createState() => _AdminReviewsState();
}

class _AdminReviewsState extends State<AdminReviews> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminReviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/admin/reviews');
      });

  Future<void> _action(Map<String, dynamic> event, String action) async {
    try {
      await widget.api.postJson('/api/mobile/v1/admin/reviews/${event['event_id']}', {'action': action});
      if (mounted) toast(context, action == 'ESCALATE' ? 'Escalated for further review' : action.toLowerCase());
      _load();
      widget.onChanged();
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
          final events = listMaps(snapshot.data?['events']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 110),
              children: [
                const Text('Moderation Queue', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (events.isEmpty)
                  const Card(child: ListTile(leading: Icon(Icons.verified_rounded, color: Colors.green), title: Text('Queue is clear'))),
                ...events.map(
                  (event) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(child: Text((event['content_type']?.toString() ?? '?').substring(0, 1))),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(event['full_name']?.toString() ?? 'Child', style: const TextStyle(fontWeight: FontWeight.w900)),
                                    Text('@${event['username'] ?? ''} · ${event['content_type'] ?? 'CONTENT'}'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(event['reason']?.toString() ?? 'Safety review required'),
                          const SizedBox(height: 5),
                          Text('Risk: ${event['risk_score'] ?? event['risk'] ?? '—'}', style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: OutlinedButton(onPressed: () => _action(event, 'BLOCK'), child: const Text('Block'))),
                              const SizedBox(width: 7),
                              Expanded(child: OutlinedButton(onPressed: () => _action(event, 'ESCALATE'), child: const Text('Escalate'))),
                              const SizedBox(width: 7),
                              Expanded(child: FilledButton(onPressed: () => _action(event, 'APPROVE'), child: const Text('Approve'))),
                            ],
                          ),
                        ],
                      ),
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

class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  final search = TextEditingController();
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminUsers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/admin/users', query: {'q': search.text.trim()});
      });

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Users',
                hintText: 'Search name, username or email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(onPressed: _load, icon: const Icon(Icons.arrow_forward_rounded)),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
                final users = listMaps(snapshot.data?['users']);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 110),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final user = users[i];
                    final role = user['role']?.toString();
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(role == 'CHILD' ? Icons.child_care_rounded : role == 'PARENT' ? Icons.family_restroom_rounded : Icons.admin_panel_settings_rounded),
                      ),
                      title: Text(user['full_name']?.toString() ?? user['username']?.toString() ?? 'User', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('$role · ${user['account_status'] ?? ''}\n${user['email'] ?? ''}'),
                      isThreeLine: true,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AdminAudit extends StatefulWidget {
  const AdminAudit({super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<AdminAudit> createState() => _AdminAuditState();
}

class _AdminAuditState extends State<AdminAudit> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminAudit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/admin/audit');
      });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text(friendlyError(snapshot.error!)));
          final events = listMaps(snapshot.data?['events']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 110),
              children: [
                const Text('Audit Trail', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                ...events.map(
                  (event) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(event['activity_type']?.toString() ?? 'Activity', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${event['created_at'] ?? ''}\nChild/User: ${event['child_id'] ?? '—'}'),
                      isThreeLine: true,
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

class _AdminSettings extends StatelessWidget {
  const _AdminSettings({required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Moderator Settings', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings_rounded)),
              title: Text(user['full_name']?.toString() ?? 'Administrator'),
              subtitle: Text(user['email']?.toString() ?? ''),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout_rounded), label: const Text('Log out')),
        ],
      ),
    );
  }
}
