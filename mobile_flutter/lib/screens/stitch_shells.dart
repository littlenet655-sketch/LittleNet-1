import 'package:flutter/material.dart';

import '../api.dart';
import '../stitch_design.dart';
import 'admin.dart';
import 'parent.dart';

class StitchParentShell extends StatefulWidget {
  const StitchParentShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<StitchParentShell> createState() => _StitchParentShellState();
}

class _StitchParentShellState extends State<StitchParentShell> {
  int index = 0;
  int refreshToken = 0;

  void refreshAll() => setState(() => refreshToken++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ParentDashboard(api: widget.api, refreshToken: refreshToken, onRefreshAll: refreshAll),
      ParentSafety(api: widget.api, refreshToken: refreshToken, onChanged: refreshAll),
      ParentChildren(api: widget.api, refreshToken: refreshToken, onChanged: refreshAll),
      ParentActivity(api: widget.api, refreshToken: refreshToken),
      ParentSettings(user: widget.user, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: StitchTokens.border, width: .7)),
        ),
        child: BottomNavigationBar(
          currentIndex: index,
          onTap: (value) => setState(() => index = value),
          selectedFontSize: 0,
          unselectedFontSize: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view_rounded), label: 'Overview'),
            BottomNavigationBarItem(icon: Icon(Icons.notifications_none_rounded), activeIcon: Icon(Icons.notifications_rounded), label: 'Alerts'),
            BottomNavigationBarItem(icon: Icon(Icons.lock_outline_rounded), activeIcon: Icon(Icons.lock_rounded), label: 'Controls'),
            BottomNavigationBarItem(icon: Icon(Icons.insights_outlined), activeIcon: Icon(Icons.insights_rounded), label: 'Activity'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

class StitchAdminShell extends StatefulWidget {
  const StitchAdminShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<StitchAdminShell> createState() => _StitchAdminShellState();
}

class _StitchAdminShellState extends State<StitchAdminShell> {
  int index = 0;
  int refreshToken = 0;

  void refreshAll() => setState(() => refreshToken++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      AdminDashboard(api: widget.api, refreshToken: refreshToken),
      AdminReviews(api: widget.api, refreshToken: refreshToken, onChanged: refreshAll),
      _AdminUsersReports(api: widget.api, refreshToken: refreshToken),
      _AdminBrandSettings(user: widget.user, onLogout: widget.onLogout),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: StitchTokens.border, width: .7)),
        ),
        child: BottomNavigationBar(
          currentIndex: index,
          onTap: (value) => setState(() => index = value),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.rule_folder_outlined), activeIcon: Icon(Icons.rule_folder_rounded), label: 'Moderation'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded), activeIcon: Icon(Icons.people_rounded), label: 'Users / Reports'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _AdminUsersReports extends StatefulWidget {
  const _AdminUsersReports({required this.api, required this.refreshToken});

  final ApiClient api;
  final int refreshToken;

  @override
  State<_AdminUsersReports> createState() => _AdminUsersReportsState();
}

class _AdminUsersReportsState extends State<_AdminUsersReports> {
  bool audit = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Text('Safety Operations', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => audit = !audit),
                  child: Text(audit ? 'Users' : 'Audit Log'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: audit
                ? AdminAudit(api: widget.api, refreshToken: widget.refreshToken)
                : AdminUsers(api: widget.api, refreshToken: widget.refreshToken),
          ),
        ],
      ),
    );
  }
}

class _AdminBrandSettings extends StatelessWidget {
  const _AdminBrandSettings({required this.user, required this.onLogout});

  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const LittleNetWordmark(fontSize: 29),
          const SizedBox(height: 6),
          const Text('Safety Operations', style: TextStyle(color: StitchTokens.muted, fontSize: 12)),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.admin_panel_settings_outlined)),
            title: Text(user['full_name']?.toString() ?? 'Moderator', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@${user['username'] ?? ''}'),
          ),
          const Divider(),
          const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.shield_outlined), title: Text('Classroom Sentinel AI'), subtitle: Text('Review and moderation controls are enforced server-side.')),
          const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.history_rounded), title: Text('Audit trail'), subtitle: Text('Moderator actions remain recorded and attributable.')),
          const SizedBox(height: 16),
          OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout_rounded), label: const Text('Log out')),
        ],
      ),
    );
  }
}
