import 'package:flutter/material.dart';
import '../api.dart';
import '../widgets.dart';
import 'kids_feed.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api, required this.refreshToken});
  final ApiClient api;
  final int refreshToken;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final queryCtrl = TextEditingController();
  final List<String> recentSearches = ['Science', 'Coding', 'Math', 'Space', 'Art'];

  static const categories = [
    {'title': 'Science', 'icon': Icons.science_outlined, 'desc': 'Experiments & space'},
    {'title': 'Math', 'icon': Icons.calculate_outlined, 'desc': 'Puzzles & logic'},
    {'title': 'Coding', 'icon': Icons.terminal_rounded, 'desc': 'Apps & games'},
    {'title': 'Art', 'icon': Icons.palette_outlined, 'desc': 'Drawing & crafts'},
    {'title': 'Sports', 'icon': Icons.sports_soccer_rounded, 'desc': 'Fitness & games'},
    {'title': 'Nature', 'icon': Icons.eco_outlined, 'desc': 'Animals & plants'},
  ];

  void _submit(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          api: widget.api,
          initialQuery: clean,
          refreshToken: widget.refreshToken,
        ),
      ),
    );
  }

  @override
  void dispose() {
    queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search LittleNet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: queryCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Search safe network, friends or topics...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _submit(queryCtrl.text),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.blue.shade50,
              elevation: 0,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'LittleNet protects your privacy. Personal contact information is shielded.',
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Recent Topics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recentSearches.map((term) {
                return ActionChip(
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  label: Text(term),
                  onPressed: () => _submit(term),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              'Explore Categories',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final cat = categories[index];
                return InkWell(
                  onTap: () => _submit(cat['title'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(cat['icon'] as IconData, size: 28, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(cat['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              Text(cat['desc'] as String, style: const TextStyle(fontSize: 11, color: Colors.black54), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({
    super.key,
    required this.api,
    required this.initialQuery,
    required this.refreshToken,
  });

  final ApiClient api;
  final String initialQuery;
  final int refreshToken;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> with SingleTickerProviderStateMixin {
  late final TextEditingController searchCtrl;
  late final TabController tabController;
  Future<Map<String, dynamic>>? future;

  @override
  void initState() {
    super.initState();
    searchCtrl = TextEditingController(text: widget.initialQuery);
    tabController = TabController(length: 2, vsync: this);
    _load();
  }

  void _load() {
    setState(() {
      future = widget.api.getJson(
        '/api/mobile/v1/kids/discover',
        query: {'q': searchCtrl.text.trim()},
      );
    });
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: searchCtrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: const InputDecoration(
            hintText: 'Search...',
            border: InputBorder.none,
            suffixIcon: Icon(Icons.search_rounded),
          ),
        ),
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(text: 'People'),
            Tab(text: 'Safe Posts'),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(friendlyError(snapshot.error!)));
          }
          final data = snapshot.data ?? const {};
          if (data['pii_warning'] == true) {
            return BlockedSearchScreen(
              query: searchCtrl.text.trim(),
              onReset: () {
                searchCtrl.clear();
                _load();
              },
            );
          }
          final kids = listMaps(data['children']);
          final posts = listMaps(data['posts']);

          return TabBarView(
            controller: tabController,
            children: [
              RefreshIndicator(
                onRefresh: () async => _load(),
                child: kids.isEmpty
                    ? const Center(child: Text('No approved children found matching your search.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: kids.length,
                        itemBuilder: (context, index) {
                          return _SearchKidTile(
                            api: widget.api,
                            kid: kids[index],
                            onChanged: _load,
                          );
                        },
                      ),
              ),
              RefreshIndicator(
                onRefresh: () async => _load(),
                child: posts.isEmpty
                    ? const Center(child: Text('No safe posts found matching your search.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: posts.length,
                        itemBuilder: (context, index) {
                          return PostCard(
                            api: widget.api,
                            post: posts[index],
                            onChanged: _load,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchKidTile extends StatelessWidget {
  const _SearchKidTile({required this.api, required this.kid, required this.onChanged});
  final ApiClient api;
  final Map<String, dynamic> kid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final isFollowing = kid['is_following'] == true;
    final isPending = kid['is_pending'] == true;

    return ListTile(
      leading: Avatar(api: api, url: kid['avatar_url']?.toString(), radius: 24),
      title: Text(
        kid['full_name']?.toString() ?? 'LittleNet Friend',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        kid['school_name'] != null ? ' • Class ' : 'Approved network',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: FilledButton.tonal(
        onPressed: () async {
          final id = asInt(kid['user_id']);
          if (id == 0) return;
          try {
            await api.postJson('/api/mobile/v1/kids/follow/', {});
            onChanged();
          } catch (e) {
            if (context.mounted) toast(context, friendlyError(e));
          }
        },
        child: Text(isFollowing ? 'Friends' : isPending ? 'Pending' : 'Connect'),
      ),
    );
  }
}

class BlockedSearchScreen extends StatelessWidget {
  const BlockedSearchScreen({super.key, required this.query, required this.onReset});
  final String query;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_outlined, size: 56, color: Colors.amber.shade800),
            ),
            const SizedBox(height: 20),
            const Text(
              'Search Protected',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'To protect your privacy and security, personal phone numbers, addresses, emails and unverified keywords cannot be searched on LittleNet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Search Safe Topics'),
            ),
          ],
        ),
      ),
    );
  }
}
