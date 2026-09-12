import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets.dart';

class ParentShell extends StatefulWidget {
  const ParentShell({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  final ApiClient api;
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  State<ParentShell> createState() => _ParentShellState();
}

class _ParentShellState extends State<ParentShell> {
  int index = 0;
  int refresh = 0;

  void refreshAll() => setState(() => refresh++);

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ParentDashboard(
          api: widget.api, refreshToken: refresh, onRefreshAll: refreshAll),
      ParentSafety(
          api: widget.api, refreshToken: refresh, onChanged: refreshAll),
      ParentChildren(
          api: widget.api, refreshToken: refresh, onChanged: refreshAll),
      ParentActivity(api: widget.api, refreshToken: refresh),
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
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield_rounded),
              label: 'Safety'),
          NavigationDestination(
              icon: Icon(Icons.family_restroom_rounded), label: 'Children'),
          NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications_rounded),
              label: 'Activity'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings'),
        ],
      ),
    );
  }
}

class ParentDashboard extends StatefulWidget {
  const ParentDashboard(
      {super.key,
      required this.api,
      required this.refreshToken,
      required this.onRefreshAll});
  final ApiClient api;
  final int refreshToken;
  final VoidCallback onRefreshAll;

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ParentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/parent/dashboard');
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
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          final data = snapshot.data ?? const {};
          final kids = listMaps(data['children']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_rounded,
                        color: Color(0xFF7C3AED), size: 30),
                    SizedBox(width: 9),
                    Text('Parent Mode',
                        style: TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                    '${kids.length} linked child${kids.length == 1 ? '' : 'ren'} · ${data['unread'] ?? 0} unread alerts',
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 18),
                if (kids.isEmpty)
                  const Card(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Create a child account to begin Parent Mode supervision.'))),
                ...kids.map(
                  (child) => ChildDashboardCard(
                    api: widget.api,
                    child: child,
                    onChanged: () {
                      _load();
                      widget.onRefreshAll();
                    },
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

class ChildDashboardCard extends StatelessWidget {
  const ChildDashboardCard(
      {super.key,
      required this.api,
      required this.child,
      required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> child;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final limit = Map<String, dynamic>.from(child['limit'] as Map? ?? const {});
    final quiz =
        Map<String, dynamic>.from(child['quiz_7d'] as Map? ?? const {});
    final safety =
        Map<String, dynamic>.from(child['safety'] as Map? ?? const {});
    final used = asInt(child['minutes_today']);
    final max = asInt(limit['daily_limit_minutes'], 60);
    final progress = max <= 0 ? 0.0 : (used / max).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                    api: api, url: child['avatar_url']?.toString(), radius: 27),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child['full_name']?.toString() ?? 'Child',
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w900)),
                      const Text('LittleNet child',
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                if (asInt(child['open_reviews']) > 0)
                  Chip(label: Text('${child['open_reviews']} review')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Screen time  $used / $max min',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _Metric(
                        label: 'Quiz', value: '${quiz['accuracy'] ?? 0}%')),
                Expanded(
                    child: _Metric(
                        label: 'Reviews',
                        value: '${child['open_reviews'] ?? 0}')),
                Expanded(
                    child: _Metric(
                        label: 'Safety',
                        value: safety['safety_level']?.toString() ?? 'STRICT')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ChildControlsScreen(
                                api: api, child: child, onChanged: onChanged))),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Controls'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ScreenTimeScreen(
                                api: api, child: child, onChanged: onChanged))),
                    icon: const Icon(Icons.schedule_rounded),
                    label: const Text('Screen time'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

class ParentSafety extends StatefulWidget {
  const ParentSafety(
      {super.key,
      required this.api,
      required this.refreshToken,
      required this.onChanged});
  final ApiClient api;
  final int refreshToken;
  final VoidCallback onChanged;

  @override
  State<ParentSafety> createState() => _ParentSafetyState();
}

class _ParentSafetyState extends State<ParentSafety> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ParentSafety oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/parent/safety');
      });

  Future<void> _action(Map<String, dynamic> event, String action) async {
    try {
      await widget.api.postJson(
          '/api/mobile/v1/parent/safety/${event['event_id']}',
          {'action': action});
      if (mounted) toast(context, action == 'APPROVE' ? 'Approved' : 'Blocked');
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
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          final events = listMaps(snapshot.data?['events']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const Text('Safety Review',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text(
                    'Only content the safety system marked for review appears here.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 16),
                if (events.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.verified_user_rounded,
                          color: Colors.green),
                      title: Text('No open safety reviews'),
                      subtitle: Text(
                          'LittleNet will surface uncertain content here.'),
                    ),
                  ),
                ...events.map((event) => _ReviewCard(
                    api: widget.api, event: event, onAction: _action)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard(
      {required this.api, required this.event, required this.onAction});
  final ApiClient api;
  final Map<String, dynamic> event;
  final Future<void> Function(Map<String, dynamic>, String) onAction;

  @override
  Widget build(BuildContext context) {
    final preview =
        Map<String, dynamic>.from(event['preview'] as Map? ?? const {});
    final text = preview['message_text'] ??
        preview['comment_text'] ??
        preview['caption'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${event['full_name'] ?? 'Child'} · ${event['content_type'] ?? 'CONTENT'}',
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Chip(label: Text(event['decision']?.toString() ?? 'REVIEW')),
              ],
            ),
            if ((event['reason']?.toString() ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(event['reason'].toString())),
            if (text != null && text.toString().isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(text.toString())),
            if (preview['media_url'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: NativeMedia(
                      api: api,
                      url: preview['media_url'].toString(),
                      mediaType: preview['media_type']?.toString(),
                      autoPlay: false),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => onAction(event, 'BLOCK'),
                        icon: const Icon(Icons.block_rounded),
                        label: const Text('Block'))),
                const SizedBox(width: 8),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: () => onAction(event, 'APPROVE'),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Approve'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ParentChildren extends StatefulWidget {
  const ParentChildren(
      {super.key,
      required this.api,
      required this.refreshToken,
      required this.onChanged});
  final ApiClient api;
  final int refreshToken;
  final VoidCallback onChanged;

  @override
  State<ParentChildren> createState() => _ParentChildrenState();
}

class _ParentChildrenState extends State<ParentChildren> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ParentChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/parent/dashboard');
      });

  Future<void> _createChild() async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final school = TextEditingController();
    final klass = TextEditingController();
    int age = 10;
    int limit = 60;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Create child account'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: name,
                      decoration:
                          const InputDecoration(labelText: 'Child name')),
                  const SizedBox(height: 9),
                  TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Username')),
                  const SizedBox(height: 9),
                  TextField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Password (8+ characters)')),
                  const SizedBox(height: 9),
                  TextField(
                      controller: school,
                      decoration: const InputDecoration(labelText: 'School')),
                  const SizedBox(height: 9),
                  TextField(
                      controller: klass,
                      decoration: const InputDecoration(labelText: 'Class')),
                  const SizedBox(height: 9),
                  DropdownButtonFormField<int>(
                    initialValue: age,
                    decoration: const InputDecoration(labelText: 'Age'),
                    items: [
                      for (int i = 4; i <= 18; i++)
                        DropdownMenuItem(value: i, child: Text('$i years'))
                    ],
                    onChanged: (value) => setLocal(() => age = value ?? 10),
                  ),
                  const SizedBox(height: 9),
                  DropdownButtonFormField<int>(
                    initialValue: limit,
                    decoration: const InputDecoration(
                        labelText: 'Daily LittleNet time'),
                    items: const [30, 45, 60, 90, 120]
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text('$value minutes')))
                        .toList(),
                    onChanged: (value) => setLocal(() => limit = value ?? 60),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'full_name': name.text.trim(),
                'username': username.text.trim(),
                'password': password.text,
                'age': age,
                'school_name': school.text.trim(),
                'current_class': klass.text.trim(),
                'daily_limit': limit,
                'safety_level': 'STRICT',
                'allow_reels': '1',
                'allow_stories': '1',
                'allow_messaging': '1',
                'allow_posting': '1',
                'allow_discover': '1',
              }),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [name, username, password, school, klass]) {
      controller.dispose();
    }
    if (payload == null) return;
    try {
      await widget.api.postJson('/api/mobile/v1/parent/children', payload);
      if (mounted) {
        toast(context, 'Child created. Face setup and age quiz are next.');
      }
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
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          final kids = listMaps(snapshot.data?['children']);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Row(
                children: [
                  const Expanded(
                      child: Text('Children',
                          style: TextStyle(
                              fontSize: 27, fontWeight: FontWeight.w900))),
                  FilledButton.icon(
                      onPressed: _createChild,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Add child')),
                ],
              ),
              const SizedBox(height: 16),
              ...kids.map(
                (child) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: Avatar(
                        api: widget.api,
                        url: child['avatar_url']?.toString(),
                        radius: 27),
                    title: Text(child['full_name']?.toString() ?? 'Child',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(
                        '${child['minutes_today'] ?? 0} min today · ${child['open_reviews'] ?? 0} reviews'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChildControlsScreen(
                          api: widget.api,
                          child: child,
                          onChanged: () {
                            _load();
                            widget.onChanged();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ChildControlsScreen extends StatefulWidget {
  const ChildControlsScreen(
      {super.key,
      required this.api,
      required this.child,
      required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> child;
  final VoidCallback onChanged;

  @override
  State<ChildControlsScreen> createState() => _ChildControlsScreenState();
}

class _ChildControlsScreenState extends State<ChildControlsScreen> {
  Map<String, dynamic>? controls;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api
          .getJson('/api/mobile/v1/parent/controls/${widget.child['user_id']}');
      if (mounted) {
        setState(() => controls =
            Map<String, dynamic>.from(data['controls'] as Map? ?? const {}));
      }
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    }
  }

  Future<void> _save() async {
    if (controls == null) return;
    setState(() => saving = true);
    try {
      await widget.api.putJson(
          '/api/mobile/v1/parent/controls/${widget.child['user_id']}',
          controls!);
      if (mounted) toast(context, 'Controls updated');
      widget.onChanged();
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = controls;
    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.child['full_name'] ?? 'Child'} controls')),
      body: current == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Features',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ...{
                  'allow_reels': 'Reels',
                  'allow_stories': 'Stories',
                  'allow_messaging': 'Messaging',
                  'allow_posting': 'Posting',
                  'allow_discover': 'Discover',
                }.entries.map(
                      (entry) => SwitchListTile(
                        title: Text(entry.value),
                        value: current[entry.key] != false,
                        onChanged: (value) =>
                            setState(() => current[entry.key] = value),
                      ),
                    ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Education-only feed'),
                  value: current['educational_only_feed'] == true,
                  onChanged: (value) =>
                      setState(() => current['educational_only_feed'] = value),
                ),
                SwitchListTile(
                  title: const Text('Quiet hours'),
                  value: current['quiet_hours_enabled'] == true,
                  onChanged: (value) =>
                      setState(() => current['quiet_hours_enabled'] = value),
                ),
                if (current['quiet_hours_enabled'] == true)
                  Row(
                    children: [
                      Expanded(
                          child: TextFormField(
                              initialValue:
                                  current['quiet_start']?.toString() ?? '21:00',
                              decoration:
                                  const InputDecoration(labelText: 'Start'),
                              onChanged: (value) =>
                                  current['quiet_start'] = value)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextFormField(
                              initialValue:
                                  current['quiet_end']?.toString() ?? '07:00',
                              decoration:
                                  const InputDecoration(labelText: 'End'),
                              onChanged: (value) =>
                                  current['quiet_end'] = value)),
                    ],
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(saving ? 'Saving…' : 'Save controls')),
              ],
            ),
    );
  }
}

class ScreenTimeScreen extends StatefulWidget {
  const ScreenTimeScreen(
      {super.key,
      required this.api,
      required this.child,
      required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> child;
  final VoidCallback onChanged;

  @override
  State<ScreenTimeScreen> createState() => _ScreenTimeScreenState();
}

class _ScreenTimeScreenState extends State<ScreenTimeScreen> {
  late double minutes;
  bool strict = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final limit =
        Map<String, dynamic>.from(widget.child['limit'] as Map? ?? const {});
    minutes = asInt(limit['daily_limit_minutes'], 60).toDouble();
    strict = limit['strict_mode'] != false;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.api.putJson(
          '/api/mobile/v1/parent/time-limit/${widget.child['user_id']}', {
        'daily_limit_minutes': minutes.round(),
        'strict_mode': strict,
      });
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) toast(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen time')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${minutes.round()} minutes/day',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          Slider(
              value: minutes,
              min: 15,
              max: 240,
              divisions: 15,
              label: '${minutes.round()} min',
              onChanged: (value) => setState(() => minutes = value)),
          SwitchListTile(
              title: const Text('Strict limit'),
              subtitle: const Text(
                  'LittleNet locks when the daily limit is reached.'),
              value: strict,
              onChanged: (value) => setState(() => strict = value)),
          const SizedBox(height: 18),
          FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}

class ParentActivity extends StatefulWidget {
  const ParentActivity(
      {super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<ParentActivity> createState() => _ParentActivityState();
}

class _ParentActivityState extends State<ParentActivity> {
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ParentActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  void _load() => setState(() {
        future = widget.api.getJson('/api/mobile/v1/parent/notifications');
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
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          final rows = listMaps(snapshot.data?['notifications']);
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 110),
              children: [
                const Text('Parent Activity',
                    style:
                        TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Card(child: ListTile(title: Text('No new alerts'))),
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(row['notification_message']?.toString() ??
                          row['message']?.toString() ??
                          'LittleNet update'),
                      subtitle: Text(row['created_at']?.toString() ?? ''),
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

class ParentSettings extends StatelessWidget {
  const ParentSettings({super.key, required this.user, required this.onLogout});
  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Parent Settings',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(user['full_name']?.toString() ?? 'Parent'),
              subtitle: Text(user['email']?.toString() ?? ''),
            ),
          ),
          const SizedBox(height: 10),
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Privacy-first supervision'),
              subtitle: Text(
                  'LittleNet surfaces safety summaries and review items while keeping controls server-owned.'),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out')),
        ],
      ),
    );
  }
}
