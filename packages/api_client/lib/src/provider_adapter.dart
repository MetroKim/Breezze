/// Client-side contract for metadata catalogue adapters only.
///
/// Playback resolution, provider selection, rights checks and stream URLs
/// belong exclusively to Breezze's backend. Flutter must never resolve
/// third-party media URLs or decide whether a provider is licensed.
library;

class ProviderTrack {
  final String breezzeTrackId;
  final String providerTrackId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final Duration duration;

  ProviderTrack({
    required this.breezzeTrackId,
    required this.providerTrackId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    required this.duration,
  });
}

sealed class ProviderOp<T> {}

class ProviderOk<T> extends ProviderOp<T> {
  final T value;
  ProviderOk(this.value);
}

class ProviderUnsupported<T> extends ProviderOp<T> {
  final String reason;
  ProviderUnsupported(this.reason);
}

class ProviderError<T> extends ProviderOp<T> {
  final String code;
  ProviderError(this.code);
}

/// A metadata adapter may call Breezze's own API; it must not call
/// third-party music endpoints directly from the Flutter client.
abstract interface class ProviderAdapter {
  String get providerId;
  String get adapterVersion;

  Future<ProviderOp<List<ProviderTrack>>> search(String query);

  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId);
}
