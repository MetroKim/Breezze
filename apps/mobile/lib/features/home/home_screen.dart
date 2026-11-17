import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/bz_brand_icons.dart';

/// Listen Now home — greeting + content rails (§03).
///
/// P0 scaffold: personalization rails fill when the catalog backend
/// lands; cards play through the global player when tapped.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 220),
        children: [
          Row(
            children: [
              BzRibbonLogo(width: 96, color: theme.bzText1),
            ],
          ),
          const SizedBox(height: 24),
          Text('Listen Now', style: theme.textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('Your music. Every platform. One line.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          _Rail(title: 'Top Picks'),
          const SizedBox(height: 24),
          _Rail(title: 'Recently Played'),
          const SizedBox(height: 24),
          _Rail(title: 'Made For You'),
          const SizedBox(height: 24),
          _Rail(title: 'Heavy Rotation'),
        ],
      ),
    );
  }
}

/// Horizontal content rail (§3.2).
class _Rail extends StatelessWidget {
  final String title;

  const _Rail({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title,
              style: TextStyle(
                  fontSize: BzType.title3,
                  fontWeight: FontWeight.w600,
                  color: theme.bzText1)),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              return _AlbumCard(index: i);
            },
          ),
        ),
      ],
    );
  }
}

/// Album card — square artwork (§21.9), token radius (§21.6).
class _AlbumCard extends StatefulWidget {
  final int index;

  const _AlbumCard({required this.index});

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: BzMotion.fastMs),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: theme.bzSurface2,
                borderRadius: BorderRadius.circular(BzRadius.artwork),
                border: Border.all(color: theme.bzSeparator),
              ),
              child: Center(
                child: BzBnoteMark(size: 48, color: theme.bzText2),
              ),
            ),
            const SizedBox(height: 8),
            Text('Album ${widget.index + 1}',
                style: TextStyle(
                    fontSize: BzType.headline,
                    fontWeight: FontWeight.w600,
                    color: theme.bzText1)),
            Text('Artist · Album',
                style:
                    TextStyle(fontSize: BzType.footnote, color: theme.bzText2)),
          ],
        ),
      ),
    );
  }
}
