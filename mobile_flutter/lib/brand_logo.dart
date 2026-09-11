import 'package:flutter/material.dart';

/// Official LittleNet Brand Wordmark as defined in Stitch UI specification.
/// Features clean bold typography with the signature bright blue accent dot and curve.
class LittleNetWordmark extends StatelessWidget {
  const LittleNetWordmark({
    super.key,
    this.fontSize = 26,
    this.color = const Color(0xFF1A1C1C),
    this.accentColor = const Color(0xFF0095F6),
  });

  final double fontSize;
  final Color color;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'LittleNet',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
        const SizedBox(width: 3),
        CustomPaint(
          size: Size(fontSize * 0.7, fontSize * 0.7),
          painter: _WordmarkSparklePainter(color: accentColor),
        ),
      ],
    );
  }
}

class _WordmarkSparklePainter extends CustomPainter {
  const _WordmarkSparklePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Signature accent dot
    final dotCenter = Offset(size.width * 0.28, size.height * 0.35);
    canvas.drawCircle(dotCenter, size.width * 0.16, dotPaint);

    // Signature smile arc
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.55, size.height * 0.65);
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.45,
      size.width * 0.95,
      size.height * 0.65,
    );
    canvas.drawPath(path, arcPaint);
  }

  @override
  bool shouldRepaint(_WordmarkSparklePainter oldDelegate) => oldDelegate.color != color;
}

/// Official LittleNet Brand Logo.
/// Displays the official vibrant LittleNet squircle emblem with interlocking safety rings and camera core.
class LittleNetAppLogo extends StatelessWidget {
  const LittleNetAppLogo({
    super.key,
    this.size = 64,
    this.elevation = 8,
  });

  final double size;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: const Color(0x330095F6),
                  blurRadius: elevation * 1.5,
                  offset: Offset(0, elevation * 0.5),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/icons/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF0B0F19),
            padding: EdgeInsets.all(size * 0.14),
            child: CustomPaint(
              size: Size(size, size),
              painter: const _ShieldLogoPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldLogoPainter extends CustomPainter {
  const _ShieldLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Outer Shield
    final outerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final outerPath = Path();
    outerPath.moveTo(w * 0.5, h * 0.05);
    outerPath.cubicTo(w * 0.85, h * 0.05, w * 0.96, h * 0.22, w * 0.96, h * 0.42);
    outerPath.cubicTo(w * 0.96, h * 0.72, w * 0.72, h * 0.88, w * 0.5, h * 0.98);
    outerPath.cubicTo(w * 0.28, h * 0.88, w * 0.04, h * 0.72, w * 0.04, h * 0.42);
    outerPath.cubicTo(w * 0.04, h * 0.22, w * 0.15, h * 0.05, w * 0.5, h * 0.05);
    outerPath.close();
    canvas.drawPath(outerPath, outerPaint);

    // Inner Deep Shield
    final innerPaint = Paint()
      ..color = const Color(0xFF1E1B4B)
      ..style = PaintingStyle.fill;

    final innerPath = Path();
    innerPath.moveTo(w * 0.5, h * 0.16);
    innerPath.cubicTo(w * 0.78, h * 0.16, w * 0.85, h * 0.28, w * 0.85, h * 0.44);
    innerPath.cubicTo(w * 0.85, h * 0.68, w * 0.68, h * 0.80, w * 0.5, h * 0.88);
    innerPath.cubicTo(w * 0.32, h * 0.80, w * 0.15, h * 0.68, w * 0.15, h * 0.44);
    innerPath.cubicTo(w * 0.15, h * 0.28, w * 0.22, h * 0.16, w * 0.5, h * 0.16);
    innerPath.close();
    canvas.drawPath(innerPath, innerPaint);

    // Center Star Sparkle
    final starPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final starPath = Path();
    starPath.moveTo(w * 0.5, h * 0.28);
    starPath.lineTo(w * 0.56, h * 0.44);
    starPath.lineTo(w * 0.74, h * 0.50);
    starPath.lineTo(w * 0.56, h * 0.56);
    starPath.lineTo(w * 0.5, h * 0.72);
    starPath.lineTo(w * 0.44, h * 0.56);
    starPath.lineTo(w * 0.26, h * 0.50);
    starPath.lineTo(w * 0.44, h * 0.44);
    starPath.close();
    canvas.drawPath(starPath, starPaint);

    // Center Pink Core Dot
    final corePaint = Paint()
      ..color = const Color(0xFFEC4899)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.5, h * 0.50), w * 0.08, corePaint);
  }

  @override
  bool shouldRepaint(_ShieldLogoPainter oldDelegate) => false;
}
