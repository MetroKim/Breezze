import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app/bootstrap.dart';
import 'core/auth/auth_session.dart';
import 'core/database/database_providers.dart';
import 'features/player/player_controller.dart';
import 'widgets/breezze_app_root.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the just_audio Linux/Windows implementations before the
  // global AudioPlayer is constructed by BreezzeAppRoot.
  JustAudioMediaKit.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: [
        playbackResolverProvider.overrideWith(
          (ref) => ref.watch(liveResolverProvider),
        ),
        playHistoryReporterProvider.overrideWith((ref) {
          return (track) async {
            final auth = ref.read(authSessionProvider);
            if (auth is! AuthSignedIn) return;

            var catalogTrackId = track.id;
            if (catalogTrackId.startsWith('bz:')) {
              final mapped = await ref
                  .read(catalogIdMapDaoProvider)
                  .lookup(catalogTrackId);
              if (mapped == null) return;
              catalogTrackId = mapped;
            }

            await ref
                .read(authSessionProvider.notifier)
                .api
                .recordPlay(catalogTrackId);
          };
        }),
      ],
      child: const BreezzeAppRoot(),
    ),
  );
}
