import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';
import '../profile/requests_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = true;
  String? _error;
  bool _piiWarning = false;

  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _children = [];
  List<Map<String, dynamic>> _curated = [];

  static const List<String> _categories = [
    '✨ All',
    '🚀 Science',
    '🎨 Art',
    '💻 Coding',
    '📐 Math',
    '🌿 Nature',
    '🎵 Music',
    '📖 Books',
  ];
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchExplore();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchExplore([String? query]) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _piiWarning = false;
    });

    try {
      final q = query?.trim() ?? '';
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v2/kids/discover',
        query: q.isNotEmpty ? {'q': q} : null,
      );

      if (res['ok'] == true && mounted) {
        setState(() {
          _piiWarning = res['pii_warning'] == true;
          _children = ((res['children'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          _posts = ((res['posts'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
          _curated = ((res['curated'] as List<dynamic>?) ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load explore right now.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleConnection(Map<String, dynamic> child) async {
    final childId = child['user_id'] as int?;
    if (childId == null) return;

    try {
      final res = await widget.authState.apiClient.postJson(
        '/api/mobile/v1/kids/follow/$childId',
        const {},
      );
      if (res['ok'] == true && mounted) {
        final status = res['status'] as String?;
        setState(() {
          if (status == 'pending') {
            child['is_pending'] = true;
            child['is_following'] = false;
          } else if (status == 'removed') {
            child['is_pending'] = false;
            child['is_following'] = false;
          }
        });
        HapticFeedback.selectionClick();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update connection under safety rules.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top Bar: Search + Quick Shortcuts ─────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _focusNode,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText:
                                'Search topics, classmates, #science...',
                            hintStyle: const TextStyle(
                                fontSize: 13.5, color: Color(0xFF8E8E8E)),
                            prefixIcon: const Icon(Icons.search_rounded,
                                color: Color(0xFF8E8E8E), size: 20),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18, color: Color(0xFF8E8E8E)),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _fetchExplore();
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onSubmitted: (val) => _fetchExplore(val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Requests Icon Badge
                    IconButton(
                      icon: const Icon(Icons.person_add_outlined,
                          color: Color(0xFF262626), size: 24),
                      tooltip: 'Connection Requests',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RequestsScreen(authState: widget.authState),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Category Chips ───────────────────────
              SizedBox(
                height: 42,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedCategoryIndex = i);
                        final cat = _categories[i].split(' ').last;
                        if (i == 0) {
                          _fetchExplore();
                        } else {
                          _fetchExplore('#$cat');
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedCategoryIndex == i
                              ? const Color(0xFF262626)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            _categories[i],
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _selectedCategoryIndex == i
                                  ? Colors.white
                                  : const Color(0xFF262626),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── PII Warning Banner ───────────────────
              if (_piiWarning)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFC107)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFF59F00), size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Personal contact info cannot be searched for child privacy.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF664D00)),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Social Explore Tabs ──────────────────
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF262626),
                unselectedLabelColor: const Color(0xFF8E8E8E),
                indicatorColor: const Color(0xFF262626),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorWeight: 1.5,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'Top'),
                  Tab(text: 'Posts'),
                  Tab(text: 'People'),
                  Tab(text: 'Learning'),
                ],
              ),
              const Divider(height: 1, thickness: 0.5, color: Color(0xFFDBDBDB)),

              // ── Content View ─────────────────────────
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? LnEmptyState(
                            emoji: '🛡️',
                            title: 'Explore unavailable',
                            subtitle: _error,
                            action: _fetchExplore,
                            actionLabel: 'Try Again',
                          )
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              _buildMediaGrid(isTop: true),
                              _buildMediaGrid(isTop: false),
                              _buildPeopleList(),
                              _buildLearningTab(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 1 & 2: Media Grid ───────────────────────────
  Widget _buildMediaGrid({required bool isTop}) {
    if (_posts.isEmpty) {
      return const LnEmptyState(
        emoji: '📸',
        title: 'No explore posts yet',
        subtitle: 'Classmate creative projects and stories will appear here.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 1.0,
      ),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        final mediaUrl = post['media_url'] as String?;
        final isVideo = post['kind'] == 'reel' || post['is_video'] == true;
        final likes = post['likes'] as int? ?? 0;

        return GestureDetector(
          onTap: () {
            // View post modal / detail
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.8,
                maxChildSize: 0.95,
                minChildSize: 0.5,
                expand: false,
                builder: (_, scrollCtrl) => SingleChildScrollView(
                  controller: scrollCtrl,
                  child: LnPostCard(item: post),
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              mediaUrl != null && mediaUrl.isNotEmpty
                  ? Image.network(
                      mediaUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: const Color(0xFFEEEEEE)),
                    )
                  : Container(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      child: Center(
                        child: Text(
                          post['content_category']?.toString() ?? '🌱',
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
              if (isVideo)
                const Positioned(
                  top: 6,
                  right: 6,
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white, size: 20),
                ),
              if (likes > 0)
                Positioned(
                  bottom: 4,
                  left: 6,
                  child: Row(
                    children: [
                      const Icon(Icons.favorite_rounded,
                          color: Colors.white, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '$likes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(blurRadius: 3, color: Colors.black54),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 3: People ───────────────────────────────────
  Widget _buildPeopleList() {
    if (_children.isEmpty) {
      return const LnEmptyState(
        emoji: '👥',
        title: 'No classmates found',
        subtitle: 'Try searching by a school subject or username.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _children.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        thickness: 0.4,
        indent: 72,
        endIndent: 16,
        color: Color(0xFFEEEEEE),
      ),
      itemBuilder: (context, index) {
        final c = _children[index];
        final name = c['full_name'] as String? ?? 'LittleNet Student';
        final username = c['username'] as String? ?? 'student';
        final avatar = c['avatar_url'] as String?;
        final school = c['school_name'] as String?;
        final reason = c['recommendation_reason'] as String?;
        final isFollowing = c['is_following'] == true;
        final isPending = c['is_pending'] == true;

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: LnAvatar(url: avatar, name: name, radius: 24),
          title: Text(name,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF262626))),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                school != null && school.isNotEmpty
                    ? '@$username · $school'
                    : '@$username',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E8E)),
              ),
              if (reason != null && reason.isNotEmpty)
                Text(
                  reason,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500),
                ),
            ],
          ),
          trailing: isFollowing
              ? OutlinedButton(
                  onPressed: () => _toggleConnection(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF262626),
                    side: const BorderSide(color: Color(0xFFDBDBDB)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: const Size(76, 30),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Following',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                )
              : isPending
                  ? OutlinedButton(
                      onPressed: () => _toggleConnection(c),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59F00),
                        side: const BorderSide(color: Color(0xFFFFC107)),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(76, 30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Requested',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    )
                  : FilledButton(
                      onPressed: () => _toggleConnection(c),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        minimumSize: const Size(76, 30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Connect',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
        );
      },
    );
  }

  // ── Tab 4: Learning ─────────────────────────────────
  Widget _buildLearningTab() {
    if (_curated.isEmpty && _posts.isEmpty) {
      return const LnEmptyState(
        emoji: '📚',
        title: 'No learning stories yet',
        subtitle: 'Curated science, art, and reading stories will appear here.',
      );
    }

    final items = _curated.isNotEmpty ? _curated : _posts;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final title = item['title'] as String? ??
            item['caption'] as String? ??
            'Learning Adventure';
        final topic = item['topic'] as String? ??
            item['content_category'] as String? ??
            'Education';
        final mediaUrl = item['poster_url'] as String? ??
            item['media_url'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: mediaUrl != null
                      ? Image.network(mediaUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              child: const Icon(Icons.menu_book_rounded,
                                  color: AppColors.primary)))
                      : Container(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          child: const Icon(Icons.school_rounded,
                              color: AppColors.primary),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.kidsMint.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          topic.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2E7D32),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF262626),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF8E8E8E), size: 20),
              ),
            ],
          ),
        );
      },
    );
  }
}
