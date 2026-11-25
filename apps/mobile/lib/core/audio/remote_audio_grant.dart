/// Defense in depth for server-issued native audio grants.
///
/// Search metadata, YouTube watch links and previews never confer a full-song
/// grant. This only validates the transport and remaining lifetime of an
/// already-authorized source; authorization remains the backend's job.
const minimumRemoteGrantRemaining = Duration(seconds: 15);

final _numericIpv4Host = RegExp(r'^[0-9]+(?:\.[0-9]+){3}$');

bool isUsableRemoteAudioGrant(
  String streamUrl,
  DateTime expiresAtUtc, {
  DateTime? nowUtc,
}) {
  final uri = Uri.tryParse(streamUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.contains(':') ||
      _numericIpv4Host.hasMatch(host)) {
    return false;
  }

  final now = (nowUtc ?? DateTime.now()).toUtc();
  return expiresAtUtc.toUtc().isAfter(now.add(minimumRemoteGrantRemaining));
}
