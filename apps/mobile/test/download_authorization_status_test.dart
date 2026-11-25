import 'package:breezze/app/downloads_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing licensed audio is not misrepresented as a network failure', () {
    expect(downloadDenialStatus('LICENSED_AUDIO_NOT_INGESTED'),
        'media_unavailable');
    expect(downloadDenialStatus('LICENSED_AUDIO_FORMAT_INVALID'),
        'media_unavailable');
  });

  test('missing offline rights and restricted codecs are actionable statuses', () {
    expect(downloadDenialStatus('NO_EXPLICIT_AUTHORIZATION'), 'not_licensed');
    expect(downloadDenialStatus('PROVIDER_DOWNLOAD_UNSUPPORTED'), 'not_licensed');
    expect(downloadDenialStatus('TAKEDOWN_ACTIVE'), 'not_licensed');
    expect(downloadDenialStatus('DOWNLOAD_RENDITION_UNSUPPORTED'),
        'format_unavailable');
  });

  test('unexpected provider errors remain retryable failures', () {
    expect(downloadDenialStatus('NETWORK_UNAVAILABLE'), 'failed');
    expect(downloadDenialStatus(null), 'failed');
  });
}
