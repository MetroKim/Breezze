/// The video player accepts only explicitly configured Breezze media origins
/// and fresh server-signed stream grants. Never treat a valid URL shape from
/// another host as evidence that Breezze owns or can stream that recording.
const defaultBreezzeVideoCdnOrigin = 'https://media.breezze.app';

const configuredBreezzeVideoCdnOrigin = String.fromEnvironment(
  'BREEZZE_VIDEO_CDN_ORIGIN',
  defaultValue: defaultBreezzeVideoCdnOrigin,
);

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _base64UrlSha256 = RegExp(r'^[A-Za-z0-9_-]{43}$');
final RegExp _integer = RegExp(r'^[0-9]{13}$');

/// Validates transport and origin only: the media Worker still verifies the
/// HMAC and asset rights. A client-side URL check cannot replace that proof.
bool isValidBreezzeVideoStreamUrl(
  Uri url, {
  required Uri trustedOrigin,
  DateTime? nowUtc,
}) {
  if (trustedOrigin.scheme != 'https' ||
      trustedOrigin.host.isEmpty ||
      trustedOrigin.path != '/' ||
      trustedOrigin.hasQuery ||
      trustedOrigin.hasFragment ||
      trustedOrigin.userInfo.isNotEmpty ||
      trustedOrigin.hasPort) {
    return false;
  }
  if (url.scheme != 'https' ||
      url.origin != trustedOrigin.origin ||
      url.userInfo.isNotEmpty ||
      url.hasFragment ||
      url.pathSegments.length != 3 ||
      url.pathSegments[0] != 'video' ||
      !_uuid.hasMatch(url.pathSegments[1]) ||
      url.pathSegments[2] != 'stream') {
    return false;
  }

  final params = url.queryParametersAll;
  if (params.length != 2 ||
      params['e']?.length != 1 ||
      params['s']?.length != 1) {
    return false;
  }
  final expirationText = params['e']!.single;
  final signature = params['s']!.single;
  if (!_integer.hasMatch(expirationText) ||
      !_base64UrlSha256.hasMatch(signature)) {
    return false;
  }
  final expiresMs = int.tryParse(expirationText);
  if (expiresMs == null) return false;
  final now = (nowUtc ?? DateTime.now().toUtc()).millisecondsSinceEpoch;

  // Signed stream grants from the API are bounded to two hours.
  return expiresMs > now && expiresMs <= now + 2 * 60 * 60 * 1000 + 60 * 1000;
}

/// Seek for fixed-step controls. Never request time outside the recording.
Duration videoSeekTarget(Duration position, Duration delta, Duration duration) {
  if (duration <= Duration.zero) return Duration.zero;
  final desired = position.inMilliseconds + delta.inMilliseconds;
  return Duration(
    milliseconds: desired.clamp(0, duration.inMilliseconds),
  );
}

/// Stable, compact, accessible player time without external dependencies.
String videoClock(Duration value) {
  final seconds = value.isNegative ? 0 : value.inSeconds;
  final minutes = seconds ~/ 60;
  final remaining = (seconds % 60).toString().padLeft(2, '0');
  if (minutes < 60) return '$minutes:$remaining';
  final hours = minutes ~/ 60;
  final minuteRemainder = (minutes % 60).toString().padLeft(2, '0');
  return '$hours:$minuteRemainder:$remaining';
}
