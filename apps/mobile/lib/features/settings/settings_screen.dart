import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/download_preferences.dart';
import '../../core/auth/auth_session.dart';
import 'account_screen.dart';
import 'artist_portal_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../widgets/bz_brand_icons.dart';

/// Settings — audio quality, playback, downloads, account (§19).
/// Breezze is fully free: no membership or upgrade UI anywhere.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _store = DownloadPreferencesStore();
  DownloadPreferences _downloads = const DownloadPreferences();
  var _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadPreferences();
  }

  Future<void> _loadDownloadPreferences() async {
    final value = await _store.load();
    if (!mounted) return;
    setState(() {
      _downloads = value;
      _preferencesLoaded = true;
    });
  }

  Future<void> _saveDownloadPreferences(DownloadPreferences value) async {
    setState(() => _downloads = value);
    await _store.save(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authSessionProvider);
    final email = auth is AuthSignedIn ? auth.email : null;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 220),
        children: [
          Text('Settings', style: theme.textTheme.displayMedium),
          const SizedBox(height: 16),
          _section(theme, 'Account', [
            ListTile(
              leading: BzBnoteMark(size: 28, color: theme.bzText1),
              title: Text(email ?? 'Not signed in'),
              subtitle: Text('Breezze — free for everyone',
                  style: theme.textTheme.bodySmall),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              ),
            ),
            ListTile(
              leading: BzSvgIcon(name: 'user-round'),
              title: const Text('Account details and sessions'),
              trailing: BzSvgIcon(name: 'chevron-right', color: theme.bzText2),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              ),
            ),
            ListTile(
              leading: BzSvgIcon(name: 'bell'),
              title: const Text('Notifications'),
              trailing: BzSvgIcon(name: 'chevron-right', color: theme.bzText2),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
            ListTile(
              leading: BzSvgIcon(name: 'mic'),
              title: const Text('Artist Portal'),
              trailing: BzSvgIcon(name: 'chevron-right', color: theme.bzText2),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArtistPortalScreen()),
              ),
            ),
            ListTile(
              leading: BzSvgIcon(name: 'logout'),
              title: const Text('Sign out'),
              onTap: () {
                ref.read(authSessionProvider.notifier).signOut();
              },
            ),
          ]),
          _section(theme, 'Audio Quality', [
            if (!_preferencesLoaded)
              const ListTile(title: Text('Loading audio preferences…'))
            else ...[
              ListTile(
                title: const Text('Streaming quality'),
                trailing: DropdownButton<String>(
                  value: _downloads.streamingQuality,
                  items: const [
                    DropdownMenuItem(value: 'AAC_128', child: Text('Standard')),
                    DropdownMenuItem(value: 'AAC_256', child: Text('High')),
                    DropdownMenuItem(value: 'LOSSLESS', child: Text('Lossless')),
                    DropdownMenuItem(value: 'HI_RES', child: Text('Hi-Res')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _saveDownloadPreferences(_downloads.copyWith(streamingQuality: value));
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('Offline download quality'),
                trailing: DropdownButton<String>(
                  value: _downloads.quality,
                  items: const [
                    DropdownMenuItem(value: 'standard', child: Text('Standard')),
                    DropdownMenuItem(value: 'lossless', child: Text('Lossless')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _saveDownloadPreferences(_downloads.copyWith(quality: value));
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'The backend selects only a format your territory and provider rights allow. Offline quality is a preference, not a guarantee of an available lossless file.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                ),
              ),
            ],
          ]),
          _section(theme, 'Downloads', [
            if (!_preferencesLoaded)
              const ListTile(
                title: Text('Loading download preferences…'),
                trailing: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              SwitchListTile(
                value: _downloads.wifiOnly,
                onChanged: (value) => _saveDownloadPreferences(
                  _downloads.copyWith(
                    wifiOnly: value,
                    allowCellular: value ? false : _downloads.allowCellular,
                  ),
                ),
                title: const Text('Download over Wi-Fi only'),
                dense: true,
              ),
              SwitchListTile(
                value: _downloads.allowCellular,
                onChanged: (value) => _saveDownloadPreferences(
                  _downloads.copyWith(
                    allowCellular: value,
                    wifiOnly: value ? false : _downloads.wifiOnly,
                  ),
                ),
                title: const Text('Allow cellular downloads'),
                dense: true,
              ),
              SwitchListTile(
                value: _downloads.autoCleanup,
                onChanged: (value) => _saveDownloadPreferences(
                  _downloads.copyWith(autoCleanup: value),
                ),
                title: const Text('Automatic storage cleanup'),
                dense: true,
              ),
              ListTile(
                title: const Text('Minimum free storage'),
                trailing: DropdownButton<int>(
                  value: _downloads.minimumFreeSpaceGb,
                  items: const [1, 2, 5, 10]
                      .map((gb) => DropdownMenuItem(
                            value: gb,
                            child: Text('$gb GB'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _saveDownloadPreferences(
                        _downloads.copyWith(minimumFreeSpaceGb: value),
                      );
                    }
                  },
                ),
              ),
              ListTile(
                title: const Text('Offline download quality'),
                trailing: DropdownButton<String>(
                  value: _downloads.quality,
                  items: const [
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('Standard'),
                    ),
                    DropdownMenuItem(
                      value: 'lossless',
                      child: Text('Lossless'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _saveDownloadPreferences(
                        _downloads.copyWith(quality: value),
                      );
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Quality options depend on the audio rights and formats '
                  'available from the authorized provider.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.bzText2,
                  ),
                ),
              ),
            ],
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
}
