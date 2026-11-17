import 'package:flutter/material.dart';

/// Breezze SVG brand icons — the monochrome B-note mark and ribbon logo
/// as inline vector widgets so they inherit any token color (spec §21.8).
///
/// These are the source-asset versions; assets/icons/*.svg carry the
/// standalone files for store listings and native shells.
class BzBnoteMark extends StatelessWidget {
  final double size;
  final Color? color;

  const BzBnoteMark({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BnotePainter(c),
        size: Size.square(size),
      ),
    );
  }
}

class _BnotePainter extends CustomPainter {
  final Color color;
  _BnotePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final s = size.width / 512; // normalized to the 512 viewbox

    // stem
    canvas.drawLine(Offset(176 * s, 132 * s), Offset(176 * s, 380 * s), paint);

    // upper bowl
    final upper = Path()
      ..moveTo(176 * s, 132 * s)
      ..lineTo(300 * s, 132 * s)
      ..arcToPoint(Offset(300 * s, 240 * s), radius: Radius.circular(54 * s), clockwise: true)
      ..lineTo(176 * s, 240 * s);
    canvas.drawPath(upper, paint);

    // lower bowl
    final lower = Path()
      ..moveTo(176 * s, 240 * s)
      ..lineTo(316 * s, 240 * s)
      ..arcToPoint(Offset(316 * s, 352 * s), radius: Radius.circular(56 * s), clockwise: true)
      ..lineTo(176 * s, 352 * s);
    canvas.drawPath(lower, paint);

    // music-note flag
    final flag = Path()
      ..moveTo(316 * s, 352 * s)
      ..lineTo(336 * s, 352 * s)
      ..lineTo(336 * s, 258 * s);
    canvas.drawPath(flag, paint);

    final note = Path()
      ..moveTo(336 * s, 258 * s)
      ..arcToPoint(Offset(336 * s, 306 * s), radius: Radius.circular(26 * s), clockwise: false);
    canvas.drawPath(note, paint);
  }

  @override
  bool shouldRepaint(_BnotePainter old) => old.color != color;
}

/// The ribbon-B logo with sound-wave tail — used in headers and the
/// about screen (spec §21.8, §46-01).
class BzRibbonLogo extends StatelessWidget {
  final double width;
  final Color? color;

  const BzRibbonLogo({super.key, this.width = 120, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      height: width * 0.8,
      child: CustomPaint(
        painter: _RibbonPainter(c),
        size: Size(width, width * 0.8),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final Color color;
  _RibbonPainter(this.color);

  @svgpaint
  void paintPath(Canvas canvas, Path p) => canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round);

  @override
  void paint(Canvas canvas, Size size) {
    // The ribbon logo is complex; use a simplified flowing stroke set.
    final w = size.width;
    final h = size.height;

    // B vertical flow
    final stem = Path()..moveTo(w * 0.22, h * 0.23);
    stem.cubicTo(w * 0.22, h * 0.58, w * 0.22, h * 0.66, w * 0.22, h * 0.77);
    paintPath(canvas, stem);

    // upper bowl
    final upper = Path()
      ..moveTo(w * 0.22, h * 0.23)
      ..lineTo(w * 0.44, h * 0.23)
      ..arcToPoint(Offset(w * 0.44, h * 0.51), radius: Radius.circular(w * 0.10), clockwise: true)
      ..lineTo(w * 0.22, h * 0.51);
    paintPath(canvas, upper);

    // lower bowl
    final lower = Path()
      ..moveTo(w * 0.22, h *  + 0.51)
      ..lineTo(w * 0.49, h * 0.51)
      ..arcToPoint(Offset(w * 0.49, h * 0.69), radius: Radius.circular(w * 0.11), clockwise: true)
      ..lineTo(w * 0.22, h * 0.69);
    paintPath(canvas, lower);

    // sound-wave tail
    final wave1 = Path()
      ..moveTo(w * 0.60, h * 0.50)
      ..cubicTo(w * 0.64, h * 0.43, w * 0.68, h * 0.43, w * 0.72, h * 0.48);
    paintPath(canvas, wave1);
    final wave2 = Path()
      ..moveTo(w * 0.60, h * 0.58)
      ..cubicTo(w * 0.65, h * 0.66, w * 0.71, h * 0.67, w * 0.76, h * 0.62);
    paintPath(canvas, wave2);
    final wave3 = Path()
      ..moveTo(w * 0.60, h * 0.42)
      ..cubicTo(w * 0.64, h * 0.35, w * 0.69, h * 0.34, w * 0.73, h * 0.38);
    paintPath(canvas, wave3);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}
