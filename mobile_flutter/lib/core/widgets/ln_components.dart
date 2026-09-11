import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/typography.dart';

// ─────────────────────────────────────────────────────────────────
//  LnAvatar – consistent circular avatar with initials fallback
// ─────────────────────────────────────────────────────────────────
class LnAvatar extends StatelessWidget {
  const LnAvatar({
    super.key,
    this.url,
    this.name = '',
    this.radius = 20,
    this.borderColor,
    this.borderWidth = 0,
    this.backgroundColor,
  });

  final String? url;
  final String name;
  final double radius;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary.withValues(alpha: 0.12);
    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: url != null && url!.isNotEmpty ? NetworkImage(url!) : null,
      child: url == null || url!.isEmpty
          ? Text(
              _initials,
              style: TextStyle(
                fontSize: radius * 0.55,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            )
          : null,
    );

    if (borderColor != null && borderWidth > 0) {
      avatar = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor!, width: borderWidth),
        ),
        child: Padding(
          padding: EdgeInsets.all(borderWidth * 0.5),
          child: avatar,
        ),
      );
    }
    return avatar;
  }
}

// ─────────────────────────────────────────────────────────────────
//  LnStoryRing – gradient ring for unread stories (Instagram style)
// ─────────────────────────────────────────────────────────────────
class LnStoryRing extends StatelessWidget {
  const LnStoryRing({
    super.key,
    required this.child,
    this.seen = false,
    this.size = 64,
  });

  final Widget child;
  final bool seen;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 4,
      height: size + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: seen
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF6B6B),
                  Color(0xFFFFD93D),
                  Color(0xFF6BCB77),
                ],
              ),
        color: seen ? const Color(0xFFDBDBDB) : null,
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(2),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  LnPostCard – clean media-first post card (Instagram-ish)
// ─────────────────────────────────────────────────────────────────
class LnPostCard extends StatefulWidget {
  const LnPostCard({
    super.key,
    required this.item,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onMore,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  State<LnPostCard> createState() => _LnPostCardState();
}

class _LnPostCardState extends State<LnPostCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likeCount;
  late AnimationController _heartCtrl;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _liked = widget.item['is_liked'] == true;
    _likeCount = widget.item['likes'] as int? ??
        widget.item['like_count'] as int? ?? 0;
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    super.dispose();
  }

  void _toggleLike() {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    _heartCtrl.forward().then((_) => _heartCtrl.reverse());
    widget.onLike?.call();
  }

  @override
  Widget build(BuildContext context) {
    final authorName = widget.item['full_name']?.toString() ??
        widget.item['author_name']?.toString() ?? 'LittleNet Student';
    final avatarUrl = widget.item['avatar_url']?.toString();
    final caption = widget.item['caption']?.toString() ?? '';
    final mediaUrl = widget.item['media_url']?.toString();
    final category = widget.item['content_category']?.toString() ?? 'Learning';
    final locationName = widget.item['location_name']?.toString();
    final commentCount = widget.item['comments'] as int? ??
        widget.item['comment_count'] as int? ?? 0;
    final createdAtStr = widget.item['created_at']?.toString();
    final timeAgo = _formatRelativeTime(createdAtStr);
    final rawTags = widget.item['tags'];
    final List<String> tags = rawTags is List
        ? rawTags.map((e) => e.toString()).toList()
        : [];

    final subtitleParts = [
      if (locationName != null && locationName.trim().isNotEmpty) '📍 ${locationName.trim()}',
      category,
      if (timeAgo.isNotEmpty) timeAgo,
    ];

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                LnAvatar(url: avatarUrl, name: authorName, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorName,
                          style: AppTypography.labelLarge
                              .copyWith(fontSize: 13, color: const Color(0xFF262626))),
                      Text(subtitleParts.join(' · '),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF8E8E8E))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_horiz, color: Color(0xFF262626), size: 20),
                  onPressed: widget.onMore,
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // ── Media ───────────────────────────────────
          if (mediaUrl != null && mediaUrl.isNotEmpty)
            GestureDetector(
              onDoubleTap: _toggleLike,
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFF0F0F0),
                    child: const Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 40, color: Color(0xFFBBBBBB)),
                    ),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: const Color(0xFFF0F0F0),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              ),
            )
          else if (caption.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: const Color(0xFFF8F9FE),
              child: Text(
                caption,
                style: AppTypography.bodyLarge
                    .copyWith(fontSize: 16, color: const Color(0xFF262626)),
              ),
            ),

          // ── Action Row ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                ScaleTransition(
                  scale: _heartScale,
                  child: IconButton(
                    icon: Icon(
                      _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _liked ? const Color(0xFFED4956) : const Color(0xFF262626),
                      size: 26,
                    ),
                    onPressed: _toggleLike,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Color(0xFF262626), size: 24),
                  onPressed: widget.onComment,
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Color(0xFF262626), size: 23),
                  onPressed: widget.onShare,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.bookmark_border_rounded,
                      color: Color(0xFF262626), size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // ── Like count + caption + hashtags ───────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_likeCount > 0) ...[
                  Text(
                    '$_likeCount ${_likeCount == 1 ? 'like' : 'likes'}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF262626)),
                  ),
                  const SizedBox(height: 4),
                ],
                if (caption.isNotEmpty && mediaUrl != null) ...[
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: authorName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF262626)),
                        ),
                        const TextSpan(text: '  '),
                        TextSpan(
                          text: caption,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF262626)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (tags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: tags.map((t) {
                      final tagStr = t.startsWith('#') ? t : '#$t';
                      return Text(
                        tagStr,
                        style: const TextStyle(
                          color: Color(0xFF3897F0),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                ],
                if (commentCount > 0)
                  Text(
                    'View all $commentCount comments',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF8E8E8E)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Divider ─────────────────────────────────
          const Divider(height: 1, thickness: 0.4, color: Color(0xFFDBDBDB)),
        ],
      ),
    );
  }
}

String _formatRelativeTime(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  try {
    final dt = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  } catch (_) {
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────
//  LnSafetyBadge – small badge indicating AI moderation status
// ─────────────────────────────────────────────────────────────────
class LnSafetyBadge extends StatelessWidget {
  const LnSafetyBadge({super.key, required this.status});

  final String status; // 'approved', 'review', 'pending'

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (status) {
      case 'approved':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        icon = Icons.verified_rounded;
        label = 'AI Safe';
        break;
      case 'review':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFFF57F17);
        icon = Icons.warning_amber_rounded;
        label = 'In Review';
        break;
      default:
        bg = const Color(0xFFEFEFEF);
        fg = const Color(0xFF757575);
        icon = Icons.hourglass_top_rounded;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  LnEmptyState – consistent empty / error state widget
// ─────────────────────────────────────────────────────────────────
class LnEmptyState extends StatelessWidget {
  const LnEmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
  });

  final String emoji;
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF262626)),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style:
                    const TextStyle(fontSize: 14, color: Color(0xFF8E8E8E)),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                ),
                child: Text(actionLabel!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  LnStatColumn – used in Profile header (posts / friends / following)
// ─────────────────────────────────────────────────────────────────
class LnStatColumn extends StatelessWidget {
  const LnStatColumn({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF262626))),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E8E))),
        ],
      ),
    );
  }
}
