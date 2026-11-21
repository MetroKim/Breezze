import 'package:material_ui/material_ui.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _name = TextEditingController();
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _email;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      final results = await Future.wait([api.profile(), api.sessions()]);
      if (!mounted) return;
      final profile = results[0] as Map<String, dynamic>;
      setState(() {
        _name.text = profile['displayName'] as String? ?? '';
        _email = profile['email'] as String?;
        _sessions = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Account details could not be loaded. Check your connection and retry.';
      });
    }
  }

  Future<void> _saveProfile() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = 'Display name must be between 1 and 80 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).api.updateProfile(displayName: name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Profile could not be saved. Please retry.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revoke(String id) async {
    try {
      await ref.read(authSessionProvider.notifier).api.revokeSession(id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session revoked')),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'That session could not be revoked.');
    }
  }

  Future<void> _deleteAccount() async {
    final password = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This permanently deletes your Breezze account and associated server data. This action cannot be undone.'),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm with your password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete account')),
        ],
      ),
    );
    final value = password.text;
    password.dispose();
    if (confirmed != true || value.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).api.deleteAccount(password: value);
      await ref.read(authSessionProvider.notifier).signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => _error = 'Account deletion failed. Check your password and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        leading: IconButton(
          icon: BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                Center(child: BzSkeleton(width: 96, height: 96, radius: 48, circle: true)),
                SizedBox(height: 24),
                BzSkeleton(width: 180, height: 14, radius: 5),
                SizedBox(height: 14),
                BzSkeleton(width: double.infinity, height: 52, radius: 10),
                SizedBox(height: 28),
                BzSkeletonTrackRow(),
                SizedBox(height: 14),
                BzSkeletonTrackRow(),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: theme.bzSurface1,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.bzSeparator),
                        ),
                        alignment: Alignment.center,
                        child: BzBnoteMark(size: 42, color: theme.bzText2),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Profile photo',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        'Photo editing will be available when profile media support is connected.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(_email ?? '', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: Text(_saving ? 'Saving…' : 'Save profile'),
                ),
                const SizedBox(height: 28),
                Text('ACTIVE SESSIONS', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (_sessions.isEmpty)
                  const ListTile(title: Text('No active sessions found'))
                else
                  for (final session in _sessions)
                    ListTile(
                      leading: const BzSvgIcon(name: 'smartphone'),
                      title: Text('Session ${(session['id'] as String? ?? '').substring(0, (session['id'] as String? ?? '').length.clamp(0, 8).toInt())}'),
                      subtitle: Text('Created ${session['createdAt'] ?? 'Unknown'} · Expires ${session['expiresAt'] ?? 'Unknown'}'),
                      trailing: TextButton(
                        onPressed: _saving ? null : () => _revoke(session['id'] as String),
                        child: const Text('Revoke'),
                      ),
                    ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: _saving ? null : _deleteAccount,
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  child: const Text('Delete account'),
                ),
              ],
            ),
    );
  }
}
