# Breezze Third-Party Code and Provider Policy

**Status:** Engineering policy for the independent Breezze implementation  
**Last reviewed:** 2026-11-22

## 1. BitChord reference boundary

BitChord's repository includes the GNU General Public License, version 3 (GPL-3.0), in its LICENSE file:

- Upstream: https://github.com/kushagrasinghx/BitChord
- License: https://github.com/kushagrasinghx/BitChord/blob/main/LICENSE

Breezze has selected an independent implementation. BitChord may be consulted for high-level product concepts and architectural patterns such as separating catalogue discovery, source resolution, queues and the player. Breezze must not copy or port BitChord source code, tests, assets, private endpoints, signing logic or other protectable implementation expression.

No BitChord source, assets or private endpoints are intentionally included in the current engine branch.

## 2. Existing repository cleanup and history caveat

The current branch removes the previously present client-side BitChordAdapter / YouTube InnerTube adapter files, their associated tests, and the unused youtube_explode_dart dependency. Playback resolution remains a Breezze-owned backend capability; YouTube Music metadata remains metadata-only.

**Important:** deleting files from the current tree does not erase earlier Git commits that may contain those files. This work does not rewrite repository history. Before a public binary release or repository redistribution, the project owner should decide—after appropriate legal review—whether historical cleanup is required. Do not rewrite shared Git history without explicit project-owner approval.

## 3. Third-party audio dependencies

The engine uses just_audio behind Breezze's own AudioEngineAdapter contract. Linux and Windows support is supplied by just_audio_media_kit and the corresponding media_kit native audio libraries.

The upstream package metadata currently identifies:
- just_audio_media_kit: Unlicense
- media_kit: MIT
- media_kit_libs_linux: MIT
- media_kit_libs_windows_audio: MIT
- audio_service_mpris: MIT (Linux MPRIS platform adapter)
- audio_service_win: MIT (Windows SMTC platform adapter)

These are separate dependencies, not BitChord code. The release process must regenerate and review pubspec.lock and the complete transitive license inventory for the exact shipped versions.

## 4. Music provider and recording rights

A public catalogue endpoint or a technically playable URL is not, by itself, proof that Breezze has all rights required for a commercial or public music-streaming service.

Provider adapters must enforce the provider's documented access controls and Breezze takedown policy. Audius playback is currently restricted to public, ungated, API-accessible tracks. Gated releases, downloads, uploads, access-control bypasses and audio rehosting are not implemented.

YouTube Music via ytmusicapi is metadata/discovery only. Breezze must not extract YouTube audio streams or represent metadata access as a streaming licence.

Before enabling any provider for production, obtain and record a provider-specific review of its API terms, creator permissions, territories, allowed playback use, attribution, caching, and takedown obligations.

## 5. Release checklist

- [ ] Confirm the shipped source tree contains no copied BitChord source or assets.
- [ ] Review Git history for previously committed BitChord-derived code and decide whether history remediation is needed.
- [ ] Regenerate pubspec.lock and review the full transitive licence inventory.
- [ ] Record provider-specific API terms and permitted use before production playback.
- [ ] Verify takedown and provider access-control enforcement with tests.
- [ ] Obtain qualified legal review for the intended distribution and music-streaming model.