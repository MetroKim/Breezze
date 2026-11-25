# Breezze: complete cleaned `main` source tree

**Branch:** `main`  
**Baseline cleanup commit:** `52e1c7277b9c1aa5d4091dc2faa34271cf069a6b`  
**Files listed:** 424 (including this document)

This is the **actual tracked source tree**, not a proposed ideal structure. Generated Flutter platform runners/build outputs are not committed and are created by `apps/mobile/tool/generate_platform_targets.sh`. A file appearing here does not mean its feature has passed end-to-end verification.

- Primary client: `apps/mobile/` (Flutter; Home/Browse/Library/Search; account/settings, player and downloads).
- Shared Dart libraries: `packages/` (design, audio contracts and client).
- API: `backend/api/` (NestJS, Prisma migrations, provider/rights, personalization, and currently live legacy auth).
- Discovery: `backend/ytmusicapi/`.
- Edge and deployment: `infra/cloudflare/`, workflows.
- Project governance: `docs/`, root LICENSE and NOTICE.
- Historical Kotlin app code and old Chordline project modules were **removed from main's working tree**; history remains in Git.
- Supabase Auth and advanced B-Spatial/AutoMix features are not falsely represented here as deployed or merged.

## Complete tracked structure

```text
Breezze/
├── .github/
│   └── workflows/
│       ├── breezze-quality.yml
│       ├── ci.yml
│       ├── codeql.yml
│       ├── deploy-api-edge.yml
│       └── web-preview-smoke.yml
├── .vscode/
│   └── tasks.json
├── apps/
│   └── mobile/
│       ├── android/
│       │   └── app/
│       │       └── src/
│       │           └── main/
│       │               └── res/
│       │                   ├── drawable/
│       │                   │   └── ic_breezze_notification.xml
│       │                   ├── mipmap-hdpi/
│       │                   │   └── ic_launcher.png
│       │                   ├── mipmap-mdpi/
│       │                   │   └── ic_launcher.png
│       │                   ├── mipmap-xhdpi/
│       │                   │   └── ic_launcher.png
│       │                   ├── mipmap-xxhdpi/
│       │                   │   └── ic_launcher.png
│       │                   └── mipmap-xxxhdpi/
│       │                       └── ic_launcher.png
│       ├── assets/
│       │   └── icons/
│       │       ├── b-note-mark.svg
│       │       ├── breezze-app-icon.svg
│       │       ├── breezze-icon-app-glossy.svg
│       │       ├── breezze-logo-black.png
│       │       ├── breezze-logo-ribbon-monochrome.svg
│       │       ├── breezze-logo-white.png
│       │       ├── breezze-mark-monochrome-bnote.svg
│       │       ├── breezze-symbol-black.svg
│       │       ├── breezze-symbol-white.svg
│       │       ├── browse.svg
│       │       ├── download.svg
│       │       ├── edit.svg
│       │       ├── home.svg
│       │       ├── launcher.png
│       │       ├── library.svg
│       │       ├── music-note.svg
│       │       ├── new.svg
│       │       ├── pause.svg
│       │       ├── play.svg
│       │       ├── plus.svg
│       │       ├── profile.svg
│       │       ├── radio.svg
│       │       ├── search.svg
│       │       ├── skip-next.svg
│       │       ├── star-filled.svg
│       │       └── star.svg
│       ├── ios/
│       │   └── Runner/
│       │       └── Assets.xcassets/
│       │           └── AppIcon.appiconset/
│       │               ├── Icon-App-1024x1024@1x.png
│       │               ├── Icon-App-20x20@1x.png
│       │               ├── Icon-App-20x20@2x.png
│       │               ├── Icon-App-20x20@3x.png
│       │               ├── Icon-App-29x29@1x.png
│       │               ├── Icon-App-29x29@2x.png
│       │               ├── Icon-App-29x29@3x.png
│       │               ├── Icon-App-40x40@1x.png
│       │               ├── Icon-App-40x40@2x.png
│       │               ├── Icon-App-40x40@3x.png
│       │               ├── Icon-App-60x60@2x.png
│       │               ├── Icon-App-60x60@3x.png
│       │               ├── Icon-App-76x76@1x.png
│       │               ├── Icon-App-76x76@2x.png
│       │               └── Icon-App-83.5x83.5@2x.png
│       ├── lib/
│       │   ├── app/
│       │   │   ├── appearance_controller.dart
│       │   │   ├── bootstrap.dart
│       │   │   ├── download_preferences.dart
│       │   │   ├── downloads_controller.dart
│       │   │   ├── library_section_preferences_store.dart
│       │   │   ├── main_tab.dart
│       │   │   ├── playlist_store.dart
│       │   │   ├── recent_store.dart
│       │   │   ├── saved_album_store.dart
│       │   │   └── search_history_store.dart
│       │   ├── core/
│       │   │   ├── api/
│       │   │   │   └── breezze_api.dart
│       │   │   ├── audio/
│       │   │   │   ├── audio_service_bridge.dart
│       │   │   │   ├── background_audio.dart
│       │   │   │   ├── just_audio_engine_adapter.dart
│       │   │   │   ├── playback_source_policy.dart
│       │   │   │   └── youtube_player_handoff.dart
│       │   │   ├── auth/
│       │   │   │   └── auth_session.dart
│       │   │   └── database/
│       │   │       ├── README.md
│       │   │       ├── breezze_database.dart
│       │   │       ├── catalog_id_map_dao.dart
│       │   │       ├── database_connection.dart
│       │   │       ├── database_connection_native.dart
│       │   │       ├── database_connection_web.dart
│       │   │       ├── database_providers.dart
│       │   │       ├── db_instance.dart
│       │   │       ├── favorites_dao.dart
│       │   │       ├── favorites_store_drift.dart
│       │   │       ├── migrate_to_drift.dart
│       │   │       ├── outbox_sync_service.dart
│       │   │       ├── playback_heartbeat_outbox_dao.dart
│       │   │       ├── recent_store_drift.dart
│       │   │       ├── recently_played_dao.dart
│       │   │       └── sync_outbox_dao.dart
│       │   ├── features/
│       │   │   ├── authentication/
│       │   │   │   └── auth_screen.dart
│       │   │   ├── browse/
│       │   │   │   └── browse_screen.dart
│       │   │   ├── catalog/
│       │   │   │   └── catalog_detail_screens.dart
│       │   │   ├── downloads/
│       │   │   │   └── downloads_screen.dart
│       │   │   ├── free_music/
│       │   │   │   └── device_audio.dart
│       │   │   ├── home/
│       │   │   │   └── home_screen.dart
│       │   │   ├── library/
│       │   │   │   ├── library_screen.dart
│       │   │   │   └── playlist_detail_screen.dart
│       │   │   ├── notifications/
│       │   │   │   └── notifications_screen.dart
│       │   │   ├── onboarding/
│       │   │   │   ├── bz_onboarding_scaffold.dart
│       │   │   │   ├── onboarding_controller.dart
│       │   │   │   └── onboarding_flow.dart
│       │   │   ├── player/
│       │   │   │   ├── now_playing_screen.dart
│       │   │   │   ├── playback_session_client.dart
│       │   │   │   ├── player_controller.dart
│       │   │   │   └── sleep_timer_controller.dart
│       │   │   ├── search/
│       │   │   │   └── search_screen.dart
│       │   │   ├── settings/
│       │   │   │   ├── account_screen.dart
│       │   │   │   ├── help_support_screen.dart
│       │   │   │   └── settings_screen.dart
│       │   │   └── video/
│       │   │       ├── device_video.dart
│       │   │       ├── official_music_video_screen.dart
│       │   │       └── open_youtube_player.dart
│       │   ├── widgets/
│       │   │   ├── breezze_app_root.dart
│       │   │   ├── bz_brand_icons.dart
│       │   │   ├── bz_playback_scrubber.dart
│       │   │   └── bz_shell.dart
│       │   └── main.dart
│       ├── linux/
│       │   ├── flutter/
│       │   │   └── CMakeLists.txt
│       │   ├── runner/
│       │   │   ├── CMakeLists.txt
│       │   │   ├── main.cc
│       │   │   ├── my_application.cc
│       │   │   └── my_application.h
│       │   ├── .gitignore
│       │   └── CMakeLists.txt
│       ├── macos/
│       │   └── Runner/
│       │       └── Assets.xcassets/
│       │           └── AppIcon.appiconset/
│       │               ├── app_icon_1024.png
│       │               ├── app_icon_128.png
│       │               ├── app_icon_16.png
│       │               ├── app_icon_256.png
│       │               ├── app_icon_32.png
│       │               ├── app_icon_512.png
│       │               └── app_icon_64.png
│       ├── test/
│       │   ├── core/
│       │   │   ├── api/
│       │   │   │   ├── breezze_api_config_test.dart
│       │   │   │   ├── breezze_api_home_test.dart
│       │   │   │   ├── breezze_api_playlist_test.dart
│       │   │   │   ├── breezze_api_support_test.dart
│       │   │   │   └── breezze_api_sync_test.dart
│       │   │   ├── audio/
│       │   │   │   ├── playback_source_policy_test.dart
│       │   │   │   └── youtube_player_handoff_test.dart
│       │   │   └── database/
│       │   │       ├── account_scoped_local_data_test.dart
│       │   │       └── playback_heartbeat_outbox_dao_test.dart
│       │   ├── features/
│       │   │   └── player/
│       │   │       ├── player_controller_test.dart
│       │   │       └── sleep_timer_controller_test.dart
│       │   ├── bz_playback_scrubber_test.dart
│       │   ├── catalog_detail_screens_test.dart
│       │   ├── download_preferences_test.dart
│       │   ├── federated_catalog_search_test.dart
│       │   ├── help_support_screen_test.dart
│       │   ├── library_section_preferences_store_test.dart
│       │   ├── player_controller_test.dart
│       │   ├── saved_album_api_test.dart
│       │   ├── saved_album_cloud_sync_test.dart
│       │   ├── saved_album_store_test.dart
│       │   ├── search_history_store_test.dart
│       │   ├── search_typeahead_test.dart
│       │   └── social_auth_api_test.dart
│       ├── tool/
│       │   ├── generate_platform_targets.sh
│       │   ├── prepare_web_database.sh
│       │   ├── run_dev.sh
│       │   └── verify_platform_network_permissions.py
│       ├── web/
│       │   ├── icons/
│       │   │   ├── Icon-192.png
│       │   │   ├── Icon-512.png
│       │   │   ├── Icon-maskable-192.png
│       │   │   └── Icon-maskable-512.png
│       │   ├── drift_worker.dart
│       │   ├── favicon.png
│       │   ├── index.html
│       │   └── manifest.json
│       ├── windows/
│       │   └── runner/
│       │       └── resources/
│       │           └── app_icon.ico
│       ├── README.md
│       └── pubspec.yaml
├── backend/
│   ├── api/
│   │   ├── prisma/
│   │   │   ├── migrations/
│   │   │   │   ├── 20261120000000_initial_schema/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121193000_hash_refresh_tokens/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121203000_user_roles/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121213000_admin_audit_events/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121213500_admin_audit_append_only/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121220000_admin_totp_mfa/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121221000_totp_replay_protection/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261121222000_mfa_recovery_codes/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122010000_artist_claim_uniqueness/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122020000_remove_artist_portal/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122050000_user_email_normalization/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122060000_track_foreign_keys/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122070000_home_feed_query_indexes/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122100000_playback_sessions/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122110000_server_verified_listening_events/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122130000_support_requests/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122205000_user_saved_catalog_albums/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261122211000_social_oauth/
│   │   │   │   │   └── migration.sql
│   │   │   │   ├── 20261123010000_followed_artists/
│   │   │   │   │   └── migration.sql
│   │   │   │   └── migration_lock.toml
│   │   │   ├── README.md
│   │   │   └── schema.prisma
│   │   ├── src/
│   │   │   ├── admin/
│   │   │   │   ├── admin.controller.ts
│   │   │   │   ├── admin.module.ts
│   │   │   │   ├── admin.service.spec.ts
│   │   │   │   └── admin.service.ts
│   │   │   ├── auth/
│   │   │   │   ├── admin.guard.spec.ts
│   │   │   │   ├── admin.guard.ts
│   │   │   │   ├── auth-registration.spec.ts
│   │   │   │   ├── auth-session.integration.spec.ts
│   │   │   │   ├── auth.controller.spec.ts
│   │   │   │   ├── auth.controller.ts
│   │   │   │   ├── auth.mfa.service.spec.ts
│   │   │   │   ├── auth.module.ts
│   │   │   │   ├── auth.service.spec.ts
│   │   │   │   ├── auth.service.ts
│   │   │   │   ├── current-session.decorator.ts
│   │   │   │   ├── current-user.decorator.ts
│   │   │   │   ├── jwt-auth.guard.ts
│   │   │   │   ├── jwt.strategy.spec.ts
│   │   │   │   ├── jwt.strategy.ts
│   │   │   │   ├── social-auth.controller.ts
│   │   │   │   ├── social-auth.service.spec.ts
│   │   │   │   ├── social-auth.service.ts
│   │   │   │   ├── totp.spec.ts
│   │   │   │   └── totp.ts
│   │   │   ├── catalog/
│   │   │   │   ├── catalog.controller.spec.ts
│   │   │   │   ├── catalog.controller.ts
│   │   │   │   ├── catalog.module.ts
│   │   │   │   ├── catalog.service.spec.ts
│   │   │   │   └── catalog.service.ts
│   │   │   ├── classical/
│   │   │   │   ├── classical.controller.ts
│   │   │   │   ├── classical.module.ts
│   │   │   │   └── classical.service.ts
│   │   │   ├── discovery/
│   │   │   │   ├── discovery.controller.ts
│   │   │   │   ├── discovery.module.ts
│   │   │   │   ├── discovery.service.spec.ts
│   │   │   │   └── discovery.service.ts
│   │   │   ├── downloads/
│   │   │   │   ├── downloads.controller.spec.ts
│   │   │   │   ├── downloads.controller.ts
│   │   │   │   ├── downloads.module.ts
│   │   │   │   ├── downloads.service.spec.ts
│   │   │   │   ├── downloads.service.tenant.spec.ts
│   │   │   │   └── downloads.service.ts
│   │   │   ├── home/
│   │   │   │   ├── home-play-event.integration.spec.ts
│   │   │   │   ├── home.controller.spec.ts
│   │   │   │   ├── home.controller.ts
│   │   │   │   ├── home.module.ts
│   │   │   │   ├── home.service.spec.ts
│   │   │   │   └── home.service.ts
│   │   │   ├── library/
│   │   │   │   ├── library.controller.ts
│   │   │   │   ├── library.module.ts
│   │   │   │   ├── library.service.spec.ts
│   │   │   │   ├── library.service.ts
│   │   │   │   ├── saved-albums.integration.spec.ts
│   │   │   │   └── saved-albums.service.spec.ts
│   │   │   ├── lyrics/
│   │   │   │   ├── lyrics.controller.spec.ts
│   │   │   │   ├── lyrics.controller.ts
│   │   │   │   ├── lyrics.module.ts
│   │   │   │   ├── lyrics.service.spec.ts
│   │   │   │   └── lyrics.service.ts
│   │   │   ├── moderation/
│   │   │   │   ├── moderation.controller.ts
│   │   │   │   ├── moderation.module.ts
│   │   │   │   ├── moderation.service.spec.ts
│   │   │   │   └── moderation.service.ts
│   │   │   ├── notifications/
│   │   │   │   ├── notifications.controller.ts
│   │   │   │   ├── notifications.module.ts
│   │   │   │   ├── notifications.service.spec.ts
│   │   │   │   └── notifications.service.ts
│   │   │   ├── onboarding/
│   │   │   │   ├── onboarding.controller.ts
│   │   │   │   ├── onboarding.module.ts
│   │   │   │   ├── onboarding.service.spec.ts
│   │   │   │   └── onboarding.service.ts
│   │   │   ├── playback/
│   │   │   │   ├── media-signer.factory.spec.ts
│   │   │   │   ├── media-signer.factory.ts
│   │   │   │   ├── media-signer.service.spec.ts
│   │   │   │   ├── media-signer.service.ts
│   │   │   │   ├── playback-resolve.service.spec.ts
│   │   │   │   ├── playback-resolve.service.ts
│   │   │   │   ├── playback-session.service.spec.ts
│   │   │   │   ├── playback-session.service.ts
│   │   │   │   ├── playback.controller.ts
│   │   │   │   └── playback.module.ts
│   │   │   ├── playlists/
│   │   │   │   ├── playlists.controller.ts
│   │   │   │   ├── playlists.module.ts
│   │   │   │   ├── playlists.service.spec.ts
│   │   │   │   └── playlists.service.ts
│   │   │   ├── providers/
│   │   │   │   ├── deezer.adapter.spec.ts
│   │   │   │   ├── deezer.adapter.ts
│   │   │   │   ├── internal-catalog.adapter.ts
│   │   │   │   ├── jamendo.adapter.spec.ts
│   │   │   │   ├── jamendo.adapter.ts
│   │   │   │   ├── provider-adapter.interface.ts
│   │   │   │   ├── provider-cache.service.ts
│   │   │   │   ├── provider-registry.service.spec.ts
│   │   │   │   ├── provider-registry.service.ts
│   │   │   │   ├── provider-result.ts
│   │   │   │   ├── providers.controller.ts
│   │   │   │   ├── providers.module.ts
│   │   │   │   ├── ytmusic.adapter.spec.ts
│   │   │   │   └── ytmusic.adapter.ts
│   │   │   ├── recommendations/
│   │   │   │   ├── recommendations.controller.spec.ts
│   │   │   │   ├── recommendations.controller.ts
│   │   │   │   ├── recommendations.module.ts
│   │   │   │   ├── recommendations.service.spec.ts
│   │   │   │   └── recommendations.service.ts
│   │   │   ├── replay/
│   │   │   │   ├── replay.controller.ts
│   │   │   │   ├── replay.module.ts
│   │   │   │   ├── replay.service.spec.ts
│   │   │   │   └── replay.service.ts
│   │   │   ├── rights/
│   │   │   │   ├── rights-decision.service.spec.ts
│   │   │   │   ├── rights-decision.service.ts
│   │   │   │   ├── rights-decision.types.ts
│   │   │   │   └── rights.module.ts
│   │   │   ├── search/
│   │   │   │   ├── search.controller.spec.ts
│   │   │   │   ├── search.controller.ts
│   │   │   │   ├── search.module.ts
│   │   │   │   ├── search.service.spec.ts
│   │   │   │   └── search.service.ts
│   │   │   ├── support/
│   │   │   │   ├── support.controller.ts
│   │   │   │   ├── support.module.ts
│   │   │   │   ├── support.service.spec.ts
│   │   │   │   └── support.service.ts
│   │   │   ├── users/
│   │   │   │   ├── users.controller.ts
│   │   │   │   ├── users.module.ts
│   │   │   │   ├── users.service.spec.ts
│   │   │   │   └── users.service.ts
│   │   │   ├── app.module.ts
│   │   │   ├── cloudflare-aware-throttler.guard.spec.ts
│   │   │   ├── cloudflare-aware-throttler.guard.ts
│   │   │   ├── main.ts
│   │   │   ├── prisma.module.ts
│   │   │   ├── prisma.service.ts
│   │   │   └── response-envelope.interceptor.ts
│   │   ├── .env.example
│   │   ├── Dockerfile
│   │   ├── MODULES.md
│   │   ├── jest.config.js
│   │   ├── nest-cli.json
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── ytmusicapi/
│   │   ├── Dockerfile
│   │   ├── README.md
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── .env.example
│   ├── .env.production.example
│   ├── README.md
│   ├── docker-compose.production.yml
│   └── docker-compose.yml
├── docs/
│   ├── architecture/
│   │   ├── ADR-001-flutter-first-shared-codebase.md
│   │   ├── ADR-002-provider-fallback-and-cloudflare-scale.md
│   │   ├── BREEZZE_CORRECTED_PRODUCT_ARCHITECTURE.md
│   │   ├── BREEZZE_INTEGRATED_DESIGN_ENGINEERING_ARCHITECTURE.md
│   │   ├── BREEZZE_MULTISOURCE_PROVIDER_ARCHITECTURE.md
│   │   ├── BREEZZE_ONE_MILLION_SCALING_PLAN.md
│   │   ├── BREEZZE_PROVIDER_INTEGRATION_DECISION.md
│   │   ├── DISCOVERY_PROVIDER_SETUP.md
│   │   ├── YOUTUBE_MUSIC_PRIMARY_PROVIDER.md
│   │   └── offline-downloads-storage.md
│   ├── audit/
│   │   ├── MAIN_ACTIVE_SOURCE_CLEANUP.md
│   │   ├── MAIN_SOURCE_TREE.md
│   │   ├── branch-consolidation.md
│   │   └── gap-register.md
│   ├── design/
│   │   ├── BITCHORD_REFERENCE_TO_BREEZZE.md
│   │   ├── BREEZZE_FULL_EXPERIENCE_PARITY.md
│   │   ├── BREEZZE_INTERFACE_CONTRACT.md
│   │   ├── BREEZZE_LIQUID_GLASS_EXTENDED.md
│   │   ├── BREEZZE_VISUAL_SYSTEM_AND_PLATFORM_SPEC.md
│   │   ├── DESIGN_REVIEW_AND_ROADMAP.md
│   │   └── REFERENCE_REPOSITORIES.md
│   ├── legal/
│   │   └── BREEZZE_THIRD_PARTY_CODE_POLICY.md
│   ├── operations/
│   │   ├── SAVED_ALBUM_CLOUD_SYNC.md
│   │   └── SOCIAL_OAUTH_GOOGLE_APPLE.md
│   ├── providers/
│   │   └── active-catalogue.md
│   ├── PRODUCTION_SECURITY_AND_CACHING_CHECKLIST.md
│   ├── PRODUCT_EXPERIENCE.md
│   ├── ROADMAP_AND_BUG_BACKLOG.md
│   └── index.html
├── infra/
│   └── cloudflare/
│       ├── api-worker/
│       │   ├── src/
│       │   │   └── index.ts
│       │   ├── README.md
│       │   ├── package.json
│       │   ├── tsconfig.json
│       │   └── wrangler.toml
│       ├── media-worker/
│       │   ├── src/
│       │   │   └── index.ts
│       │   ├── README.md
│       │   ├── package.json
│       │   ├── tsconfig.json
│       │   └── wrangler.toml
│       └── README.md
├── packages/
│   ├── api_client/
│   │   ├── lib/
│   │   │   ├── src/
│   │   │   │   ├── bz_track.dart
│   │   │   │   ├── download_manager.dart
│   │   │   │   ├── downloads_library.dart
│   │   │   │   ├── lyrics_provider.dart
│   │   │   │   ├── membership.dart
│   │   │   │   ├── provider_adapter.dart
│   │   │   │   └── source_chain.dart
│   │   │   └── breezze_api_client.dart
│   │   ├── test/
│   │   │   ├── automix_source_chain_test.dart
│   │   │   └── downloads_library_test.dart
│   │   └── pubspec.yaml
│   ├── audio_contracts/
│   │   ├── lib/
│   │   │   ├── src/
│   │   │   │   ├── audio_engine_adapter.dart
│   │   │   │   ├── audio_quality.dart
│   │   │   │   ├── automix.dart
│   │   │   │   ├── crossfade_controller.dart
│   │   │   │   ├── lrc_parser.dart
│   │   │   │   ├── playback_state_machine.dart
│   │   │   │   ├── queue_manager.dart
│   │   │   │   └── scrobble_bus.dart
│   │   │   └── audio_contracts.dart
│   │   ├── test/
│   │   │   ├── audio_quality_test.dart
│   │   │   ├── lyrics_scrobble_test.dart
│   │   │   ├── playback_state_machine_test.dart
│   │   │   └── queue_manager_test.dart
│   │   └── pubspec.yaml
│   └── design_system/
│       ├── lib/
│       │   ├── src/
│       │   │   ├── glass/
│       │   │   │   ├── bz_glass.dart
│       │   │   │   └── bz_glass_tokens.dart
│       │   │   ├── bz_ambient_backdrop.dart
│       │   │   ├── bz_filter_pill.dart
│       │   │   ├── bz_glass_container.dart
│       │   │   ├── bz_skeleton.dart
│       │   │   ├── bz_theme.dart
│       │   │   └── tokens.dart
│       │   ├── breezze_design_system.dart
│       │   └── bz_theme.dart
│       ├── test/
│       │   ├── bz_filter_pill_test.dart
│       │   ├── bz_glass_test.dart
│       │   └── bz_skeleton_test.dart
│       ├── DESIGN.md
│       └── pubspec.yaml
├── .gitignore
├── BREEZZE_MASTER_PLAN.txt
├── LICENSE
├── NOTICE.md
├── README.md
├── SECURITY.md
└── run.sh
```
