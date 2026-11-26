import 'dart:convert';
import 'dart:typed_data';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import 'bz_brand_icons.dart';

/// Source-owned, 2x2 playlist artwork. Real saved-track covers only:
/// no invented artists, synthetic album names, or repeated fake thumbnails.
/// A future user-selected cover may override the generated composition.
class BzPlaylistArtwork extends StatelessWidget {
  const BzPlaylistArtwork({
    super.key,
    required this.artworkUrls,
    this.customArtworkUrl,
    this.customArtworkBase64,
    this.size = 56,
  });

  final List<String?> artworkUrls;
  final String? customArtworkUrl;
  /// Listener-selected local PNG thumbnail, never a provider download URL.
  final String? customArtworkBase64;
  final double size;

  Uint8List? get _localCover {
    final raw = customArtworkBase64;
    if (raw == null || raw.length > 750000) return null;
    try {
      final bytes = base64Decode(raw);
      return bytes.isNotEmpty && bytes.length <= 560000 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localCover = _localCover;
    final art = artworkUrls
        .whereType<String>()
        .where((url) {
          final uri = Uri.tryParse(url);
          return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
        })
        .toSet()
        .take(4)
        .toList();

    Widget tile(int index) {
      if (index >= art.length) {
        return ColoredBox(
          color: index.isEven ? theme.bzSurface1 : theme.bzSurface2,
          child: Center(
            child: BzBnoteMark(
              size: size / 5,
              color: theme.bzText2,
            ),
          ),
        );
      }
      return Image.network(
        art[index],
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => ColoredBox(
          color: theme.bzSurface2,
          child: Center(
            child: BzBnoteMark(
              size: size / 5,
              color: theme.bzText2,
            ),
          ),
        ),
      );
    }

    return Semantics(
      image: true,
      label: localCover == null && customArtworkUrl == null
          ? 'Playlist cover made from saved song artwork'
          : 'User-selected playlist cover',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BzRadius.artwork),
          child: SizedBox.square(
            dimension: size,
            child: localCover != null
                ? Image.memory(
                    localCover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => tile(0),
                  )
                : customArtworkUrl != null &&
                    Uri.tryParse(customArtworkUrl!)?.scheme == 'https'
                ? Image.network(
                    customArtworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => tile(0),
                  )
                : art.length == 1
                    ? tile(0)
                    : GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 1,
                          crossAxisSpacing: 1,
                        ),
                        itemCount: 4,
                        itemBuilder: (_, index) => tile(index),
                      ),
          ),
        ),
      ),
    );
  }
}
