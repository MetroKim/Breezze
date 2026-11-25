import 'package:material_ui/material_ui.dart';

import 'bz_theme.dart';
import 'tokens.dart';

/// Consistent, keyboard-accessible category/scope filter across Breezze.
/// The 48dp hit target stays usable at larger text scales and the motion
/// respects the device's reduced-animation accessibility preference.
class BzFilterPill extends StatelessWidget {
  const BzFilterPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(BzRadius.capsule),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: BzMotion.fastMs),
              curve: Curves.easeOutCubic,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: active ? theme.bzText1 : theme.bzSurface2,
                borderRadius: BorderRadius.circular(BzRadius.capsule),
              ),
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: BzType.subheadline,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? theme.bzBackground : theme.bzText2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
