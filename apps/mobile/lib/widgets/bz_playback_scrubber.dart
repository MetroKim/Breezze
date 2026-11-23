import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Shared mini-player seek control. Taps and drags must both commit a seek;
/// accessibility increment/decrement actions work without pointer gestures.
class BzPlaybackScrubber extends StatefulWidget {
  const BzPlaybackScrubber({
    super.key,
    required this.progress,
    required this.enabled,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<BzPlaybackScrubber> createState() => _BzPlaybackScrubberState();
}

class _BzPlaybackScrubberState extends State<BzPlaybackScrubber> {
  double? _dragValue;
  bool _dragging = false;

  double get _value =>
      (_dragging && _dragValue != null ? _dragValue! : widget.progress)
          .clamp(0.0, 1.0);

  void _update(Offset local, double width) {
    if (!widget.enabled || width <= 0) return;
    setState(() => _dragValue = (local.dx / width).clamp(0.0, 1.0));
  }

  void _finish() {
    if (!widget.enabled) return;
    final value = _dragValue;
    setState(() {
      _dragging = false;
      _dragValue = null;
    });
    if (value != null) widget.onSeek(value);
  }

  void _cancel() {
    if (!_dragging && _dragValue == null) return;
    setState(() {
      _dragging = false;
      _dragValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value;
    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: 'Playback position',
      value: '${(value * 100).round()}%',
      increasedValue: '${((value + 0.05).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue: '${((value - 0.05).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: widget.enabled
          ? () => widget.onSeek((value + 0.05).clamp(0.0, 1.0))
          : null,
      onDecrease: widget.enabled
          ? () => widget.onSeek((value - 0.05).clamp(0.0, 1.0))
          : null,
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _update(details.localPosition, width),
              onTapUp: (details) {
                if (!widget.enabled) return;
                _update(details.localPosition, width);
                _finish();
              },
              onTapCancel: _cancel,
              onHorizontalDragStart: (details) {
                if (!widget.enabled) return;
                _dragging = true;
                _update(details.localPosition, width);
              },
              onHorizontalDragUpdate: (details) =>
                  _update(details.localPosition, width),
              onHorizontalDragEnd: (_) => _finish(),
              onHorizontalDragCancel: _cancel,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    width: double.infinity,
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: theme.bzSeparator,
                      color: theme.bzAccent,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
