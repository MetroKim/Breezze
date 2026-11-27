import 'package:breezze_audio_contracts/audio_contracts.dart';

/// Final transport boundary between backend playback authorization and the
/// platform audio decoder. The backend remains responsible for content rights;
/// a well-formed URL alone is never proof of those rights.
///
/// Keep signed URLs out of exceptions and logs. The native player must not
/// accept a stale grant, plaintext remote media or a mislabeled local source.
void validateNativeAudioSource(
  PlayableSource source, {
  DateTime? nowUtc,
  bool allowDevelopmentLoopback = false,
}) {
  final location = source.streamUrl;
  if (source.trackId.trim().isEmpty ||
      location.isEmpty ||
      location.trim() != location ||
      location.contains('\u0000')) {
    throw StateError('AUDIO_SOURCE_INVALID');
  }

  if (source.isLocal) {
    // Local paths are handled by the OS decoder; web and network URLs are not
    // local media, even if the provider incorrectly marks them isLocal.
    final posixPath = location.startsWith('/') && !location.startsWith('//');
    final windowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(location);
    if (posixPath || windowsPath) return;
    final contentUri = Uri.tryParse(location);
    if (contentUri?.scheme == 'content' &&
        contentUri!.hasAuthority &&
        contentUri.userInfo.isEmpty &&
        contentUri.path.isNotEmpty &&
        !contentUri.hasFragment) {
      return;
    }
    throw StateError('AUDIO_LOCAL_SOURCE_INVALID');
  }

  final current = (nowUtc ?? DateTime.now()).toUtc();
  if (!source.expiresAtUtc.toUtc().isAfter(current)) {
    throw StateError('AUDIO_SOURCE_EXPIRED');
  }

  final uri = Uri.tryParse(location);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    throw StateError('AUDIO_SOURCE_INVALID_URL');
  }
  if (uri.scheme == 'https') return;

  // Local development may run the media Worker emulator over HTTP. No other
  // plaintext stream is accepted, and release builds must pass false here.
  final loopback = uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '::1';
  if (allowDevelopmentLoopback && uri.scheme == 'http' && loopback) return;

  throw StateError('AUDIO_SOURCE_REQUIRES_HTTPS');
}
