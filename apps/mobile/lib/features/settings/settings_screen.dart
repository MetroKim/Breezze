import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/bz_brand_icons.dart';

/// Settings — audio quality, downloads, membership (§19.2–19.4, §18).
///
/// Spotify/Apple Music-style sections. Premium-gated toggles are
/// presentation hints; the server remains the entitlement authority
/// (§18.4).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 220),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 24),
          _SettingsSection(
            title: 'Audio Quality',
            children: [
              _QualityTile(
                title: 'Streaming Quality',
                options: const ['Low · AAC 96', 'Normal · AAC 160', 'High · AAC 256', 'Lossless · FLAC', 'Hi-Res Lossless'],
                initial: 'High · AAC 256',
                premiumOnly: const {'Lossless · FLAC', 'Hi-Res Lossless'},
              ),
              _QualityTile(
                title: 'Download Quality',
                options: const ['Normal', 'High', 'Lossless', 'Hi-Res'],
                initial: 'Lossless',
                premiumOnly: const {'Lossless', 'Hi-Res'},
              ),
            ],
          ),
          _SettingsSection(
            title: 'Playback',
            children: [
              _SwitchTile(
                title: 'Gapless Playback',
                initial: true,
                subtitle: 'Seamless transitions with no silence between tracks',
              ),
              _SwitchTile(
                title: 'AutoMix',
                initial: false,
                subtitle: 'DJ-style transitions with beat matching (Premium)',
                premium: true,
              ),
              _SwitchTile(
                title: 'Sound Check',
                initial: false,
                subtitle: 'Play all songs at the same volume level',
              ),
            ],
          ),
          _SettingsSection(
            title: 'Downloads',
            children: [
              _SwitchTile(
                title: 'Download over Wi-Fi only',
                initial: true,
              ),
              _SwitchTile(
                title: 'Remove finished downloads after 30 days',
                initial: false,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Membership',
            children: [
              _MembershipTile(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Section container — Apple-style grouped list (§21.1 tokens only).
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      2      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: BzType.footnote,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: theme.bzText2)),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.bzSurface1,
            borderRadius: BorderRadius.circular(BzRadius.card),
            border: Border.all(color: theme.bzSeparator),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Quality picker with premium-gated options (§19.2, §18.4).
class _QualityTile extends StatefulWidget {
  final String title;
  final List<String> options;
  final String initial;
  final Set<String> premiumOnly;

  const _QualityTile({
    required this.title,
    options  required this.options,
    required this.initial,
    this.premiumOnly = const {},
  });

  @override
  State<_QualityTile> createState() => _QualityTileState();
}

class _QualityTileState extends State<_QualityTile> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  UIWidget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: theme.textTheme.titleMedium),
              ),
              Text(_selected,
                  style: TextStyle(fontSize: BzType.subheadline, color: theme.bzText2)),
            ],
          ),
        ),
        for (final option in widget.options)
          RadioListTile<String>(
            value: option,
            groupValue: _selected,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selected = v);
            },
            title: Text(option),
            subtitle: widget.premiumOnly.contains(option)
                ? Text('Premium', style: TextStyle(fontSize: BzType.caption, color: theme.bzAccent))
                : null,
            dense: true,
            controlAffinity: ListTileControlAffinity.trailing,
          ),
      ],
    );
  }
}

/// Switch row with optional premium lock icon.
class _SwitchTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool initial;
  final bool premium;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.initial,
    this.premium = false,
  });

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late bool _value;

  @2 override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      value: _value,
      onChanged: (v) => setState(() => _value = v),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title),
          if (widget.premium) ...[
            const SizedBox(width: 6),
            Icon(Icons.workspace_premium, size: 16, color: theme.bzAccent),
          ],
        ],
      ),
      subtitle: widget.subtitle != null
          ? Text(widget.subtitle!, style: theme.textTheme.bodySmall)
          : null,
      dense: true,
    );
  }
}

/// Membership upsell / status tile (§18.1).
class _MembershipTile extends StatelessWidget {
  final MembershipTier tier;

  _MembershipTile({this.tier = MembershipTier.free});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: BzBnoteMark(size: 28, color: theme.bzAccent),
      title: Text(tier == MembershipTier.premium ? 'Breezze Premium' : 'Upgrade to Premium'),
      subtitle: Text(
        tier == MembershipTier.premium
            ? 'Lossless, Hi-Res, downloads and AutoMix included'
            : 'Unlock lossless audio, Hi-Res, downloads and AutoMix',
        style: theme.textTheme.bodySmall,
      ),
      trailing: tier == MembershipTier.premium
          ? const Icon(Icons.check_circle, size: 20)
          : ElevatedButton(onPressed: () {}, child: const Text('Upgrade')),
    );
  }
}
