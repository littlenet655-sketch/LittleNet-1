import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/ln_components.dart';

/// LittleNet V2 – Search / Discover screen.
///
/// Visual language:
/// - White background, grey filled pill search bar (Instagram / TikTok style)
/// - Category suggestion chips scroll below search bar
/// - Results → flat ListTile rows with LnAvatar (no Card wrapping)
/// - Connect state: Indigo "Connect" → amber "Requested ⏳" → grey "Connected ✓"
/// - PII warning as a small inline banner (not an alert dialog)
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  List<Map<String, dynamic>> _children = [];
  bool _isLoading = true;
  String? _error;
  bool _piiWarning = false;

  final List<String> _chips = [
    '🔥 Trending',
    '🔬 Science',
    '🎨 Art',
    '💻 Coding',
    '📚 Reading',
    '🌿 Nature',
    '🎵 Music',
  ];
  int _selectedChip = 0;

  @override
  void initState() {
    super.initState();
    _loadDiscover();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDiscover([String? query]) async {
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

      if (res['ok'] == true) {
        setState(() {
          _piiWarning = res['pii_warning'] == true;
          final list = (res['children'] as List<dynamic>?) ?? [];
          _children = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 403
          ? 'Discovery is restricted by your parent safety settings.'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Unable to connect. Check your internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleConnection(Map<String, dynamic> child) async {
    final childId = child['user_id'] as int?;
    if (childId == null) return;
    final isFollowing = child['is_following'] == true;
    final isPending = child['is_pending'] == true;

    HapticFeedback.selectionClick();

    try {
      final res = await widget.authState.apiClient.post(
        '/api/mobile/v1/kids/follow/$childId',
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
        if (status == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Connection request sent! 🛡️'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFollowing || isPending
                ? 'Could not cancel request.'
                : 'Connection could not be sent under safety rules.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFE53935),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // ── Top area: title + search bar ──────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        const Text(
                          'Search',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF262626),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.tune_rounded,
                              color: Color(0xFF262626)),
                          onPressed: () =>
                              _loadDiscover(_searchController.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Search pill
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText:
                              'Search students, topics, #science…',
                          hintStyle: const TextStyle(
                              fontSize: 14, color: Color(0xFF8E8E8E)),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Color(0xFF8E8E8E), size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18, color: Color(0xFF8E8E8E)),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadDiscover();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onSubmitted: (val) => _loadDiscover(val),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Category chips ─────────────────────────
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _chips.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedChip = i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedChip == i
                              ? const Color(0xFF262626)
                              : const Color(0xFFF0F0F0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _chips[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _selectedChip == i
                                ? Colors.white
                                : const Color(0xFF262626),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── PII warning ────────────────────────────
              if (_piiWarning)
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
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
                          'Personal contact info cannot be searched for privacy.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF664D00)),
                        ),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 1, thickness: 0.5, color: Color(0xFFDBDBDB)),

              // ── Results ────────────────────────────────
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(6, (_) => const _SearchSkeleton()),
      );
    }

    if (_error != null) {
      return LnEmptyState(
        emoji: '🛡️',
        title: 'Search unavailable',
        subtitle: _error,
        action: () => _loadDiscover(_searchController.text),
        actionLabel: 'Try Again',
      );
    }

    if (_children.isEmpty) {
      return LnEmptyState(
        emoji: '🔎',
        title: 'No students found',
        subtitle: 'Try a different username, school, or interest tag.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _children.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, thickness: 0.4, indent: 72, endIndent: 16, color: Color(0xFFEEEEEE)),
      itemBuilder: (context, index) {
        final c = _children[index];
        final name = c['full_name'] as String? ?? 'LittleNet Student';
        final username = c['username'] as String? ?? 'student';
        final avatar = c['avatar_url'] as String?;
        final school = c['school_name'] as String?;
        final isFollowing = c['is_following'] == true;
        final isPending = c['is_pending'] == true;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              LnAvatar(url: avatar, name: name, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF262626))),
                    Text(
                      school != null && school.isNotEmpty
                          ? '@$username · $school'
                          : '@$username',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E8E8E)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _connectButton(c, isFollowing, isPending),
            ],
          ),
        );
      },
    );
  }

  Widget _connectButton(
      Map<String, dynamic> child, bool isFollowing, bool isPending) {
    if (isFollowing) {
      return OutlinedButton(
        onPressed: () => _toggleConnection(child),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF262626),
          side: const BorderSide(color: Color(0xFFDBDBDB)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(80, 30),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('Connected ✓'),
      );
    }

    if (isPending) {
      return OutlinedButton(
        onPressed: () => _toggleConnection(child),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF59F00),
          side: const BorderSide(color: Color(0xFFFFC107)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(80, 30),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: const Text('Requested ⏳'),
      );
    }

    return FilledButton(
      onPressed: () => _toggleConnection(child),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: const Size(80, 30),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: const Text('Connect'),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Row skeleton for loading state
// ─────────────────────────────────────────────────────────
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  Widget _box(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const CircleAvatar(radius: 24, backgroundColor: Color(0xFFEEEEEE)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(130, 13),
                const SizedBox(height: 5),
                _box(90, 10),
              ],
            ),
          ),
          _box(70, 30),
        ],
      ),
    );
  }
}
