import 'dart:convert';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/auth/youtube_music_session.dart';

const _musicOrigin = 'https://music.youtube.com';
const _loginUrl =
    'https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&prompt=select_account&continue=https%3A%2F%2Fmusic.youtube.com%2F';

bool get supportsYouTubeMusicWebSession =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<void> clearYouTubeMusicWebSession() async {
  if (!supportsYouTubeMusicWebSession) return;
  await WebViewCookieManager().clearCookies();
}

class YouTubeMusicConnectScreen extends ConsumerStatefulWidget {
  const YouTubeMusicConnectScreen({super.key});

  @override
  ConsumerState<YouTubeMusicConnectScreen> createState() =>
      _YouTubeMusicConnectScreenState();
}

class _YouTubeMusicConnectScreenState
    extends ConsumerState<YouTubeMusicConnectScreen> {
  WebViewController? _webView;
  WebViewCookieManager? _cookieManager;
  bool _pageReady = false;
  bool _saving = false;
  String? _error;

  bool get _supported => supportsYouTubeMusicWebSession;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    _cookieManager = WebViewCookieManager();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _pageReady = false);
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() {
            _pageReady = url.startsWith(_musicOrigin);
            _error = null;
          });
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame == false) return;
          setState(() => _error = 'The sign-in page could not be loaded.');
        },
      ))
      ..loadRequest(Uri.parse(_loginUrl));
  }

  Future<void> _connect() async {
    final webView = _webView;
    if (webView == null || !_pageReady || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rawConfig = await webView.runJavaScriptReturningResult('''
JSON.stringify({
  loggedIn: !!(window.ytcfg && (window.ytcfg.get('LOGGED_IN') === true || window.ytcfg.get('LOGGED_IN') === 'true')),
  authUser: window.ytcfg && window.ytcfg.get('SESSION_INDEX'),
  clientVersion: window.ytcfg && window.ytcfg.get('INNERTUBE_CONTEXT_CLIENT_VERSION')
})
''');
      final config = _decodeJavaScriptObject(rawConfig);
      if (config['loggedIn'] != true) {
        throw const YouTubeMusicSessionException(
          'YTMUSIC_NOT_SIGNED_IN',
          'Finish signing in and wait for YouTube Music to open.',
        );
      }

      final cookies = await _cookieManager!.getCookies(
        domain: Uri.parse(_musicOrigin),
      );
      await ref.read(youtubeMusicSessionProvider.notifier).connect(
        cookies: {
          for (final cookie in cookies) cookie.name: cookie.value,
        },
        authUser: config['authUser']?.toString(),
        clientVersion: config['clientVersion']?.toString(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on YouTubeMusicSessionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The YouTube Music session could not be verified.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _decodeJavaScriptObject(Object raw) {
    Object? value = raw;
    for (var attempt = 0; attempt < 2 && value is String; attempt++) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        break;
      }
    }
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_supported || _webView == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connect YouTube Music')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'YouTube Music account connection is available on Android, iPhone and macOS.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Connect YouTube Music')),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _webView!)),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: theme.bzSurface1,
                border: Border(top: BorderSide(color: theme.bzSeparator)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _pageReady && !_saving ? _connect : null,
                    child: Text(_saving ? 'Verifying…' : 'Use this account'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The session stays encrypted on this device and is used only for direct YouTube Music requests.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
