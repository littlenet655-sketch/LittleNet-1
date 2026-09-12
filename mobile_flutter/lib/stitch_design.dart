import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual primitives ported from the uploaded Google Stitch LittleNet set.
///
/// The Stitch HTML remains a design reference only. The production app stays
/// 100% native Flutter and does not embed a WebView.
abstract final class StitchTokens {
  static const blue = Color(0xFF0095F6);
  static const bluePressed = Color(0xFF1877F2);
  static const canvas = Color(0xFFFFFFFF);
  static const softCanvas = Color(0xFFFAFAFA);
  static const border = Color(0xFFDBDBDB);
  static const ink = Color(0xFF262626);
  static const muted = Color(0xFF8E8E8E);
  static const link = Color(0xFF00376B);
  static const heart = Color(0xFFED4956);
  static const safe = Color(0xFF00BA88);
  static const review = Color(0xFFFF9500);
  static const blocked = Color(0xFFFF3B30);
  static const classroom = Color(0xFFE8F3FF);
}

class LittleNetWordmark extends StatelessWidget {
  const LittleNetWordmark({
    super.key,
    this.fontSize = 27,
    this.color = StitchTokens.ink,
    this.centered = false,
  });

  final double fontSize;
  final Color color;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'LittleNet',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            height: 1,
            letterSpacing: -0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(width: fontSize * .16),
        SizedBox(
          width: fontSize * 1.14,
          height: fontSize * .8,
          child: const CustomPaint(painter: _LittleNetFacePainter()),
        ),
      ],
    );
    return centered ? Center(child: row) : row;
  }
}

class LittleNetFaceMark extends StatelessWidget {
  const LittleNetFaceMark({super.key, this.size = 48, this.background});

  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .24),
      ),
      padding: EdgeInsets.all(size * .13),
      child: const CustomPaint(painter: _LittleNetFacePainter()),
    );
  }
}

class _LittleNetFacePainter extends CustomPainter {
  const _LittleNetFacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StitchTokens.blue
      ..style = PaintingStyle.fill;
    final radius = math.min(size.width, size.height) * .13;
    canvas.drawCircle(Offset(size.width * .26, size.height * .27), radius, paint);

    final smile = Paint()
      ..color = StitchTokens.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, size.height * .11)
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(
      size.width * .43,
      size.height * .37,
      size.width * .42,
      size.height * .40,
    );
    canvas.drawArc(rect, math.pi * 1.12, math.pi * .76, false, smile);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StitchStoryRing extends StatelessWidget {
  const StitchStoryRing({
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
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: seen ? const Color(0xFFC7C7C7) : null,
        gradient: seen
            ? null
            : const LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [
                  Color(0xFFF09433),
                  Color(0xFFE6683C),
                  Color(0xFFDC2743),
                  Color(0xFFCC2366),
                  Color(0xFFBC1888),
                ],
              ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: ClipOval(child: child),
      ),
    );
  }
}

class SentinelSafeBadge extends StatelessWidget {
  const SentinelSafeBadge({super.key, this.label = 'Sentinel Safe • Approved'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_rounded, size: 14, color: Color(0xFF34D399)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StitchHairline extends StatelessWidget {
  const StitchHairline({super.key});

  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: .6);
}

class StitchSectionTitle extends StatelessWidget {
  const StitchSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class StitchStatusPill extends StatelessWidget {
  const StitchStatusPill({
    super.key,
    required this.text,
    this.tone = StitchTokens.classroom,
    this.foreground = StitchTokens.link,
    this.icon,
  });

  final String text;
  final Color tone;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(color: foreground, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class DoubleTapLikeOverlay extends StatefulWidget {
  const DoubleTapLikeOverlay({
    super.key,
    required this.child,
    required this.onLike,
  });

  final Widget child;
  final VoidCallback onLike;

  @override
  State<DoubleTapLikeOverlay> createState() => _DoubleTapLikeOverlayState();
}

class _DoubleTapLikeOverlayState extends State<DoubleTapLikeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final Animation<double> scale = CurvedAnimation(
    parent: controller,
    curve: Curves.elasticOut,
  );
  bool showHeart = false;

  void trigger() {
    widget.onLike();
    setState(() => showHeart = true);
    controller.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => showHeart = false);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: trigger,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (showHeart)
            ScaleTransition(
              scale: scale,
              child: const Icon(
                Icons.favorite_rounded,
                size: 94,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black38, blurRadius: 22)],
              ),
            ),
        ],
      ),
    );
  }
}
