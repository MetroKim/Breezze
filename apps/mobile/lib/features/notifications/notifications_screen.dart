import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _marking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ref.read(authSessionProvider.notifier).api.notifications();
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Notifications could not be loaded. Check your connection and retry.';
      });
    }
  }

  Future<void> _markRead(String id) async {
    if (_marking.contains(id)) return;
    setState(() => _marking.add(id));
    try {
      await ref.read(authSessionProvider.notifier).api.markNotificationRead(id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items)
            if (item['id'] == id)
              {...item, 'readAt': DateTime.now().toUtc().toIso8601String()}
            else
              item,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not mark notification as read.')),
        );
      }
    } finally {
      if (mounted) setState(() => _marking.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = _items.where((item) => item['readAt'] == null).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(unread == 0 ? 'Notifications' : 'Notifications ($unread)'),
        leading: IconButton(
          icon: BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [IconButton(onPressed: _load, icon: const BzSvgIcon(name: 'refresh'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('You are all caught up.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => Divider(color: theme.dividerColor),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final id = item['id'] as String? ?? '';
                        final isRead = item['readAt'] != null;
                        return ListTile(
                          leading: Icon(
                            isRead ? Icons.notifications_none : Icons.notifications_active,
                            color: isRead ? theme.disabledColor : theme.colorScheme.primary,
                          ),
                          title: Text(item['title'] as String? ?? 'Breezze update'),
                          subtitle: Text(item['body'] as String? ?? ''),
                          isThreeLine: true,
                          trailing: isRead
                              ? null
                              : TextButton(
                                  onPressed: _marking.contains(id) ? null : () => _markRead(id),
                                  child: Text(_marking.contains(id) ? 'Saving…' : 'Mark read'),
                                ),
                        );
                      },
                    ),
    );
  }
}
