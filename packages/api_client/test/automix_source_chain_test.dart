import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Automix (§9.7)', () {
    const mix = Automix();

    test('beat-matches close BPMs', () {
      final t = mix.plan(
        const TrackAnalysis(bpm: 120, energy: 0.5),
        const TrackAnalysis(bpm: 121, energy: 0.5),
      );
      expect(t.beatMatched, isTrue);
      expect(t.tempoFactor, inInclusiveRange(0.99, 1.01));
      expect(t.doubleTimeFold, isFalse);
    });

    test('folds half-time BPMs to match', () {
      final t = mix.plan(
        const TrackAnalysis(bpm: 120, energy: 0.3),
        const TrackAnalysis(bpm: 60, energy: 0.3),
      );
      expect(t.beatMatched, isTrue);
      expect(t.doubleTimeFold, isTrue);
    });

    test('no match when BPMs are far apart', () {
      final t = mix.plan(
        const TrackAnalysis(bpm: 90, energy: 0.2),
        const TrackAnalysis(bpm: 160, energy: 0.9),
      );
      expect(t.beatMatched, isFalse);
      expect(t.tempoFactor, 1.0);
    });

    test('transition length scales with energy', () {
      final low = mix.plan(
        const TrackAnalysis(bpm: 120, energy: 0.0),
        const TrackAnalysis(bpm: 120, energy: 0.0),
      );
      final high = mix.plan(
        const TrackAnalysis(bpm: 120, energy: 1.0),
        const TrackAnalysis(bpm: 120, energy: 1.0),
      );
      expect(high.transitionMs, greaterThan(low.transitionMs));
    });
  });

  group('Metadata SourceChain (§52.7)', () {
    test('searches each metadata adapter and deduplicates title and artist',
        () async {
      final primary = _StubSource('primary');
      final fallback = _StubSource('fallback');
      final chain = SourceChain([primary, fallback]);

      final results = await chain.searchAll('Nightcall');

      expect(primary.lastQuery, 'Nightcall');
      expect(fallback.lastQuery, 'Nightcall');
      expect(results, hasLength(1));
      expect(results.single.id, 'bz-1');
      expect(results.single.title, 'Nightcall');
      expect(results.single.artist, 'Kavinsky');
    });

    test('skips unsupported metadata adapters without failing the chain',
        () async {
      final unavailable = _StubSource(
        'unavailable',
        result: ProviderUnsupported('catalogue_unavailable'),
      );
      final available = _StubSource('available');
      final chain = SourceChain([unavailable, available]);

      final results = await chain.searchAll('Nightcall');

      expect(results, hasLength(1));
      expect(available.lastQuery, 'Nightcall');
    });
  });
}

class _StubSource implements ProviderAdapter {
  _StubSource(this.id, {this.result});

  final String id;
  final ProviderOp<List<ProviderTrack>>? result;
  String? lastQuery;

  @override
  String get providerId => id;

  @override
  String get adapterVersion => '1.0.0';

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    lastQuery = query;
    return result ??
        ProviderOk([
          ProviderTrack(
            breezzeTrackId: 'bz-1',
            providerTrackId: 'provider-track-1',
            title: 'Nightcall',
            artist: 'Kavinsky',
            duration: const Duration(seconds: 254),
          ),
        ]);
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    return ProviderUnsupported('not_implemented');
  }
}
