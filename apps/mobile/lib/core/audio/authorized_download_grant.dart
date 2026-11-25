/// Validates backend-issued download grants before the client starts I/O.
///
/// Discovery metadata, preview URLs and missing/expired offline leases are
/// never sufficient to authorize a persistent audio file.
class AuthorizedDownloadGrant {
  const AuthorizedDownloadGrant({
    required this.downloadUrl,
    required this.offlineLeaseExpiresAtUtc,
    required this.assetVariant,
    this.assetVersion,
  });

  final Uri downloadUrl;
  final DateTime offlineLeaseExpiresAtUtc;
  final String assetVariant;

  /// Stable, server-issued version of the *exact encoded media asset*.
  /// Null means a partial download cannot be safely resumed.
  final String? assetVersion;

  static AuthorizedDownloadGrant? fromResponse(
    Map<String, dynamic> response, {
    DateTime? nowUtc,
  }) {
    if (response['allowed'] != true || response['previewOnly'] == true) {
      return null;
    }

    final urlText = response['url'];
    if (urlText is! String) return null;
    final url = Uri.tryParse(urlText);
    if (url == null || url.scheme != 'https' || url.host.isEmpty ||
        url.userInfo.isNotEmpty || url.fragment.isNotEmpty) {
      return null;
    }
    // The CDN path and MIME must describe the exact AAC object signed for
    // offline transfer; a stream URL, preview URL, or metadata link is not
    // proof of download entitlement.
    final variant = response['assetVariant'];
    if ((variant != 'AAC_128' && variant != 'AAC_256') ||
        response['mimeType'] != 'audio/mp4' ||
        url.pathSegments.length != 3 ||
        url.pathSegments[0] != 'audio' ||
        url.pathSegments[2] != variant ||
        url.queryParameters['mode'] != 'download' ||
        url.queryParameters['s']?.isNotEmpty != true) {
      return null;
    }

    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    DateTime? parseExpiry(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;

    final lease = parseExpiry(response['offlineLeaseExpiresAt']);
    if (lease == null || !lease.isAfter(now)) return null;

    // The API intentionally issues at most a 72h offline lease. A longer
    // client-side lease is not proof of authority and must fail closed.
    if (lease.isAfter(now.add(const Duration(hours: 72, seconds: 30)))) {
      return null;
    }

    final signedUrlExpiryValue = response['expiresAt'];
    if (signedUrlExpiryValue == null) return null;
    final signedUrlExpiry = parseExpiry(signedUrlExpiryValue);
    if (signedUrlExpiry == null || !signedUrlExpiry.isAfter(now) ||
        signedUrlExpiry.millisecondsSinceEpoch.toString() !=
            url.queryParameters['e']) {
      return null;
    }

    final rightsExpiryValue = response['rightsExpiresAt'];
    if (rightsExpiryValue != null) {
      final rightsExpiry = parseExpiry(rightsExpiryValue);
      if (rightsExpiry == null ||
          !rightsExpiry.isAfter(now) ||
          lease.isAfter(rightsExpiry)) {
        return null;
      }
    }

    final version = response['assetVersion'];
    // Version identifiers are metadata, never raw URLs, tokens, or cookies.
    final assetVersion = version is String &&
            RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(version)
        ? version
        : null;

    return AuthorizedDownloadGrant(
      downloadUrl: url,
      offlineLeaseExpiresAtUtc: lease,
      assetVariant: variant as String,
      assetVersion: assetVersion,
    );
  }
}
