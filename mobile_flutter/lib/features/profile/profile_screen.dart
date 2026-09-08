import 'package:flutter/material.dart';
import '../../api.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/gradient_scaffold.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.authState});

  final AuthState authState;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _counts;
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic>? _controls;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await widget.authState.apiClient.get(
        '/api/mobile/v1/kids/profile',
      );
      if (res['ok'] == true) {
        setState(() {
          _profile = res['profile'] as Map<String, dynamic>?;
          _counts = res['counts'] as Map<String, dynamic>?;
          _controls = res['controls'] as Map<String, dynamic>?;

          final list = (res['posts'] as List<dynamic>?) ?? [];
          _posts = list.whereType<Map<String, dynamic>>().toList();
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Unable to load profile.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('My Profile 👤'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).pushNamed('/kids/settings');
            },
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
            Text(_error!, style: AppTypography.bodyLarge),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: _loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final p = _profile ?? {};
    final name = p['full_name'] as String? ?? 'LittleNet Student';
    final bio = p['bio'] as String? ?? 'Excited to learn and create! 🌟';
    final avatarUrl = p['avatar_url'] as String?;
    final school = p['school_name'] as String?;
    final grade = p['current_class'] as String?;

    final postsCount = _counts?['posts'] ?? _posts.length;
    final followersCount = _counts?['followers'] ?? 0;
    final followingCount = _counts?['following'] ?? 0;

    final skills =
        (p['skills'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];
    final interests =
        (p['interests'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];
    final ambitions =
        (p['ambitions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            [];

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Profile Card
            Row(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: AppColors.kidsAccent.withValues(alpha: 0.2),
                  backgroundImage:
                      avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.kidsAccent,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statColumn('Posts', postsCount.toString()),
                      _statColumn('Friends', followersCount.toString()),
                      _statColumn('Following', followingCount.toString()),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Name & School Info
            Text(name, style: AppTypography.headlineMedium),
            if (school != null && school.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.school_outlined,
                      size: 14, color: AppColors.kidsAccent),
                  const SizedBox(width: 4),
                  Text(
                    grade != null && grade.isNotEmpty
                        ? '$school · $grade'
                        : school,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMutedDark),
                  ),
                ],
              ),
            ],
            if (_controls != null &&
                _controls!['educational_only_feed'] == true) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.school, size: 14, color: AppColors.kidsMint),
                  const SizedBox(width: 4),
                  Text('Educational Feed Focus',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.kidsMint)),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.sm),
            Text(bio, style: AppTypography.bodyMedium),

            const SizedBox(height: AppSpacing.md),

            // Edit Profile Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final updated = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(
                        authState: widget.authState,
                        currentProfile: p,
                      ),
                    ),
                  );
                  if (updated == true) {
                    _loadProfile();
                  }
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Skills & Interests & Ambitions Chips
            if (skills.isNotEmpty ||
                interests.isNotEmpty ||
                ambitions.isNotEmpty) ...[
              if (interests.isNotEmpty) ...[
                const Text('Interests', style: AppTypography.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: interests
                      .map((i) => _tagChip(i, AppColors.kidsAccent))
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (skills.isNotEmpty) ...[
                const Text('Skills', style: AppTypography.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skills
                      .map((s) => _tagChip(s, Colors.cyanAccent))
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (ambitions.isNotEmpty) ...[
                const Text('Ambitions', style: AppTypography.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: ambitions
                      .map((a) => _tagChip(a, Colors.orangeAccent))
                      .toList(),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const Divider(height: 32),
            ],

            // Posts Grid Section
            Row(
              children: [
                const Icon(Icons.grid_on_rounded,
                    size: 18, color: AppColors.kidsAccent),
                const SizedBox(width: AppSpacing.xs),
                const Text('My Creations', style: AppTypography.titleMedium),
                const Spacer(),
                Text('${_posts.length} posts',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMutedDark)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            if (_posts.isEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 36, color: Colors.white24),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('No posts yet', style: AppTypography.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Share your first art, coding, or learning creation!',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMutedDark),
                    ),
                  ],
                ),
              ),
            ] else ...[
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final item = _posts[index];
                  final mediaUrl = item['media_url'] as String?;
                  final isReel = item['is_reel'] == true;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (mediaUrl != null && mediaUrl.isNotEmpty)
                          Image.network(
                            mediaUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.image_not_supported_outlined,
                                  size: 24, color: Colors.white24),
                            ),
                          )
                        else
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Text(
                                item['caption']?.toString() ?? '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        if (isReel)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(Icons.movie_creation_outlined,
                                size: 14, color: Colors.white),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statColumn(String label, String value) {
    return Column(
      children: [
        Text(value,
            style:
                AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style:
                AppTypography.caption.copyWith(color: AppColors.textMutedDark)),
      ],
    );
  }

  Widget _tagChip(String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
