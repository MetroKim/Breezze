import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/bz_brand_icons.dart';

/// In-app help that explains current product behavior without promising
/// integrations or support channels that have not been configured.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _topics = <_HelpTopic>[
    _HelpTopic(
      'Why can I find a song but not play it?',
      'Search results are metadata, not proof that Breezze has streaming rights. '
          'Playback starts only after the backend confirms that the track is available '
          'for your account and territory. If a track cannot be authorized, it stays unavailable.',
    ),
    _HelpTopic(
      'Why are some Browse collections empty?',
      'Charts, regional rankings, new-release feeds, music videos and concert listings '
          'need verified catalog or event providers. Breezze does not turn ordinary search '
          'results into official charts or invent editorial data.',
    ),
    _HelpTopic(
      'How do playlists work?',
      'You can create and manage playlists in your Library. Playlist changes are stored '
          'locally when offline. Cross-device synchronization and collaborative editing '
          'depend on the account service and are not implied by a local playlist.',
    ),
    _HelpTopic(
      'Why is a download unavailable?',
      'Offline availability depends on the track rights, territory, account status, '
          'available storage and provider support. Your download-quality setting is a preference, '
          'not a guarantee that a particular format is available.',
    ),
    _HelpTopic(
      'Where are my downloaded songs?',
      'Open Library and choose Downloaded. Downloads are stored in app-private storage '
          'scoped to the signed-in account on this device.',
    ),
    _HelpTopic(
      'How do I manage my account?',
      'Open Settings, then Account details and sessions. You can update your display name, '
          'review active sessions, revoke a session, or request account deletion.',
    ),
    _HelpTopic(
      'Is Breezze free?',
      'Yes. Breezze is designed as a free listening app. There are no subscriptions, '
          'memberships, upgrade screens or paywalls in this product.',
    ),
    _HelpTopic(
      'What data does Breezze show?',
      'Track metadata comes from connected discovery/catalog sources. Playback and downloads '
          'are separately checked by Breezze services. Editorial rankings, artist biographies, '
          'credits and event details appear only when verified data is available.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.bzSurface1,
                    borderRadius: BorderRadius.circular(BzRadius.card),
                    border: Border.all(color: theme.bzSeparator),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BzBnoteMark(size: 34, color: theme.bzAccent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('How can we help?', style: theme.textTheme.titleLarge),
                            const SizedBox(height: 6),
                            Text(
                              'Quick answers about listening, discovery, downloads and your account.',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('FREQUENTLY ASKED QUESTIONS',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.bzText2,
                      letterSpacing: 0.8,
                    )),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: theme.bzSurface1,
                    borderRadius: BorderRadius.circular(BzRadius.card),
                    border: Border.all(color: theme.bzSeparator),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _topics.length; i++) ...[
                        ExpansionTile(
                          key: PageStorageKey<String>(_topics[i].question),
                          title: Text(_topics[i].question,
                              style: theme.textTheme.titleSmall),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_topics[i].answer,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.bzText2,
                                  height: 1.5,
                                )),
                          ],
                        ),
                        if (i != _topics.length - 1)
                          Divider(height: 1, color: theme.bzSeparator),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Need account help? Open Settings → Account details and sessions to review your profile and active sessions.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpTopic {
  final String question;
  final String answer;

  const _HelpTopic(this.question, this.answer);
}
