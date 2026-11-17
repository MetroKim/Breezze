import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/bz_brand_icons.dart';

/// Settings — audio quality, playback, downloads, membership (§19, §18).
/// Premium-gated toggles are hints; the server is the entitlement
/// authority (§18.4).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 220),
        children: [
          Text('Settings', style: theme.textTheme.displayMedium),
          const SizedBox(height: 16),
          _section(theme, 'Audio Quality', [
            _qualityPicker(theme, 'Streaming Quality'),
            _qualityPicker(theme, 'Download Quality'),
          ]),
          _section(theme, 'Playback', [
            _switchTile(theme, 'Gapless Playback', true),
            _switchTile(theme, 'AutoMix (Premium)', false),
            _switchTile(theme, 'Sound Check', false),
          ]),
          _section(theme, 'Downloads', [
            _switchTile(theme, 'Download over Wi-Fi only', true),
          ]),
          _section(theme, 'Membership', [
            _membershipTile(theme),
          ]),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

  Widget _qualityPicker(ThemeData theme, String title) {
    return ListTile(
      title: Text(title),
      trailing: const Text('High'),
      onTap: () {},
    );
  }

  Widget _switchTile(ThemeData theme, String title, bool initial) {
    return _SwitchRow(title: title, initial: initial);
  }

  Widget _membershipTile(ThemeData theme) {
    return ListTile(
      leading: BzBnoteMark(size: 28, color: theme.bzAccent),
      title: const Text('Upgrade to Premium'),
      subtitle: Text(
          'Unlock lossless audio, Hi-Res, downloads and AutoMix',
          style: theme.textTheme.bodySmall),
      trailing: ElevatedButton(
        onPressed: () {},
        child: const Text('Upgrade'),
      ),
    );
  }
}

class _SwitchRow extends StatefulWidget {
  final String title;
  final bool initial;

  const _SwitchRow({required this.title, required this.initial});

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  late bool _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _value,
      onChanged: (v) => setState(() => _value = v),
      title: Text(widget.title),
      dense: true,
    );
  }
}
