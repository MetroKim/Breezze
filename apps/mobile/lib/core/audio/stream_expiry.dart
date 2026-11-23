DateTime streamExpiry(Uri uri) {
  final seconds = int.tryParse(uri.queryParameters['expire'] ?? '');
  return seconds != null && seconds > 0 && seconds < 10000000000
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      : DateTime.now().toUtc().add(const Duration(minutes: 5));
}
