import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Breezze icon primitive. Every interface glyph is rendered from SVG;
/// product marks are kept separate from the icon set.
class BzSvgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const BzSvgIcon({
    super.key,
    required this.name,
    this.size = 22,
    this.color,
  });

  static const _paths = <String, String>{
    'wifi-off': '<path d="M3 3 21 21M8.5 8.5A12 12 0 0 1 21 12M5 12a12 12 0 0 1 2.2-1.2M2 8a16 16 0 0 1 3.2-2M12 20h.01" />',
    'music-note': '<path d="M14.5 4.25v11.2a3.1 3.1 0 1 1-1.8-2.82V7.1l7-1.55v8.4a3.1 3.1 0 1 1-1.8-2.82V3.6l-3.4.65Z" />',
    'download': '<path d="M12 3.75v10.5m-4-4 4 4 4-4M4.5 16.5v2A1.75 1.75 0 0 0 6.25 20.25h11.5a1.75 1.75 0 0 0 1.75-1.75v-2" />',
    'radio': '<rect x="3.5" y="8" width="17" height="12" rx="2"/><path d="m7 8 9-4M7.5 12.5h.01M11 12.5h.01M7 16h4m3.5-3.5h3"/>',
    'chevron-right': '<path d="m9 18 6-6-6-6"/>',
    'search': '<circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 4.25 4.25"/>',
    'close': '<path d="m6 6 12 12M18 6 6 18"/>',
    'history': '<path d="M3 12a9 9 0 1 0 2.6-6.3L3 8"/><path d="M3 3v5h5m4-1v5l3 2"/>',
    'chevron-down': '<path d="m6 9 6 6 6-6"/>',
    'more-vertical': '<circle cx="12" cy="5" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="19" r="1" fill="currentColor"/>',
    'shuffle': '<path d="m16 3 5 5-5 5M3 7h2.5a5 5 0 0 1 4 2l5 6a5 5 0 0 0 4 2H21M16 21l5-5-5-5M3 17h2.5a5 5 0 0 0 3.3-1.25"/>',
    'skip-previous': '<path d="M5 5v14M19 5.5 8 12l11 6.5v-13Z"/>',
    'skip-next': '<path d="M19 5v14M5 5.5 16 12 5 18.5v-13Z"/>',
    'repeat': '<path d="m17 2 4 4-4 4M3 11V8a2 2 0 0 1 2-2h16M7 22l-4-4 4-4m14-1v3a2 2 0 0 1-2 2H3"/>',
    'pause': '<path d="M7 5.5A1.5 1.5 0 0 1 8.5 4h1A1.5 1.5 0 0 1 11 5.5v13a1.5 1.5 0 0 1-1.5 1.5h-1A1.5 1.5 0 0 1 7 18.5v-13Zm6 0A1.5 1.5 0 0 1 14.5 4h1A1.5 1.5 0 0 1 17 5.5v13a1.5 1.5 0 0 1-1.5 1.5h-1a1.5 1.5 0 0 1-1.5-1.5v-13Z"/>',
    'play': '<path d="M7.5 4.8a1 1 0 0 1 1.5-.86l10.1 7.06a1.2 1.2 0 0 1 0 2l-10.1 7.06a1 1 0 0 1-1.5-.86V4.8Z" fill="currentColor" stroke="none"/>',
    'favorite': '<path d="M20.5 8.8c0 4.5-8.5 10-8.5 10s-8.5-5.5-8.5-10A4.3 4.3 0 0 1 12 6.2a4.3 4.3 0 0 1 8.5 2.6Z"/>',
    'refresh': '<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.5 9A7 7 0 0 1 18 6l2 1M4 17l2-1a7 7 0 0 0 12.5-3"/>',
    'trash': '<path d="M4 7h16M10 11v6m4-6v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    'download-done': '<path d="M12 3.5v10m-4-4 4 4 4-4M5 17v2.5h14V17M8.5 17l2 2 5-5"/>',
    'logout': '<path d="M10 4H5.5A1.5 1.5 0 0 0 4 5.5v13A1.5 1.5 0 0 0 5.5 20H10M15 16l4-4-4-4m4 4H9"/>',
    'lyrics': '<path d="M7 11h4v6H5v-6l3-5h3m6 5h4v6h-6v-6l3-5h3"/>',
    'share': '<path d="M12 15V3m-4 4 4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
    'queue': '<path d="M4 5h16M4 10h16M4 15h10M4 20h7m5-5 4 4 3-4"/>',
    'star-filled': '<path d="M12 3.25 14.7 8.73l6.05.88-4.38 4.27 1.03 6.03L12 17.06l-5.4 2.85 1.03-6.03-4.38-4.27 6.05-.88L12 3.25Z" fill="currentColor" stroke="none"/>',
    'star': '<path d="m12 3.25 2.7 5.48 6.05.88-4.38 4.27 1.03 6.03L12 17.06l-5.4 2.85 1.03-6.03L3.25 9.61l6.05-.88L12 3.25Z"/>',
  };

  @override
  Widget build(BuildContext context) {
    final stroke = color ?? Theme.of(context).colorScheme.onSurface;
    final path = _paths[name];
    if (path == null) {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(child: SizedBox(width: 4, height: 4)),
      );
    }
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">$path</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(stroke, BlendMode.srcIn),
    );
  }
}

/// Breezze app mark rendered from its SVG source.
class BzBnoteMark extends StatelessWidget {
  final double size;
  final Color? color;

  const BzBnoteMark({super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/b-note-mark.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}

/// Ribbon wordmark. Kept as a brand illustration, not an interface icon.
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
      child: CustomPaint(painter: _RibbonPainter(c)),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final Color color;
  _RibbonPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = size.width * 0.03
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    final stem = Path()
      ..moveTo(w * 0.22, h * 0.23)
      ..lineTo(w * 0.22, h * 0.77);
    canvas.drawPath(stem, paint);

    final upper = Path()
      ..moveTo(w * 0.22, h * 0.23)
      ..lineTo(w * 0.44, h * 0.23)
      ..arcToPoint(Offset(w * 0.44, h * 0.51),
          radius: Radius.circular(w * 0.14), clockwise: true)
      ..lineTo(w * 0.22, h * 0.51);
    canvas.drawPath(upper, paint);

    final lower = Path()
      ..moveTo(w * 0.22, h * 0.51)
      ..lineTo(w * 0.49, h * 0.51)
      ..arcToPoint(Offset(w * 0.49, h * 0.69),
          radius: Radius.circular(w * 0.16), clockwise: true)
      ..lineTo(w * 0.22, h * 0.69);
    canvas.drawPath(lower, paint);

    final wave1 = Path()
      ..moveTo(w * 0.60, h * 0.50)
      ..cubicTo(w * 0.64, h * 0.43, w * 0.68, h * 0.43, w * 0.72, h * 0.48);
    canvas.drawPath(wave1, paint);

    final wave2 = Path()
      ..moveTo(w * 0.60, h * 0.58)
      ..cubicTo(w * 0.65, h * 0.66, w * 0.71, h * 0.67, w * 0.76, h * 0.62);
    canvas.drawPath(wave2, paint);

    final wave3 = Path()
      ..moveTo(w * 0.60, h * 0.42)
      ..cubicTo(w * 0.64, h * 0.35, w * 0.69, h * 0.34, w * 0.73, h * 0.38);
    canvas.drawPath(wave3, paint);
  }

  @override
  bool shouldRepaint(_RibbonPainter oldDelegate) => oldDelegate.color != color;
}
