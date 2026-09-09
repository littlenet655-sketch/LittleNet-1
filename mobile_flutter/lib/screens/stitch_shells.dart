import 'package:flutter/material.dart';

import '../api.dart';
import 'admin.dart';
import 'kids.dart';
import 'kids_feed.dart';
import 'kids_learning.dart';
import 'parent.dart';

class StitchKidsShell extends StatefulWidget {
  const StitchKidsShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<StitchKidsShell> createState() => _StitchKidsShellState();
}

class _StitchKidsShellState extends State<StitchKidsShell> {
  int index = 0;
  int refreshToken = 0;

  void refreshAll() => setState(() => refreshToken++);

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverPage(api: widget.api, refreshToken: refreshToken),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationsScreen(api: widget.api)),
    );
  }

  void _openMessages() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MessagesPage(api: widget.api)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      KidsHomePage(
        api: widget.api,
        refreshToken: refreshToken,
        onRefreshAll: refreshAll,
      ),
      ReelsPage(api: widget.api, refreshToken: refreshToken),
      CreatePostPage(
        api: widget.api,
        onCreated: () {
          refreshAll();
          setState(() => index = 0);
        },
      ),
      LearningScreen(api: widget.api),
      ProfilePage(
        api: widget.api,
        user: widget.user,
        onLogout: widget.onLogout,
        refreshToken: refreshToken,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: IndexedStack(index: index, children: pages)),
          if (index == 0)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              right: 6,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Search',
                    onPressed: _openSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: _openNotifications,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  IconButton(
                    tooltip: 'Messages',
                    onPressed: _openMessages,
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_display_outlined),
            selectedIcon: Icon(Icons.smart_display_rounded),
            label: 'Reels',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box_rounded),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

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
      ParentDashboard(
        api: widget.api,
        refreshToken: refreshToken,
        onRefreshAll: refreshAll,
      ),
      ParentSafety(
        api: widget.api,
        refreshToken: refreshToken,
        onChanged: refreshAll,
      ),
      ParentChildren(
        api: widget.api,
        refreshToken: refreshToken,
        onChanged: refreshAll,
      ),
      ParentActivity(api: widget.api, refreshToken: refreshToken),
      ParentSettings(user: widget.user, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Controls',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Account',
          ),
        ],
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
      AdminReviews(
        api: widget.api,
        refreshToken: refreshToken,
        onChanged: refreshAll,
      ),
      _AdminUsersReports(api: widget.api, refreshToken: refreshToken),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.rule_folder_outlined),
            selectedIcon: Icon(Icons.rule_folder_rounded),
            label: 'Moderation',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Users / Reports',
          ),
        ],
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
  int segment = 0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Users')),
                ButtonSegment(value: 1, label: Text('Reports / Audit')),
              ],
              selected: {segment},
              onSelectionChanged: (value) => setState(() => segment = value.first),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: segment,
              children: [
                AdminUsers(api: widget.api, refreshToken: widget.refreshToken),
                AdminAudit(api: widget.api, refreshToken: widget.refreshToken),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
