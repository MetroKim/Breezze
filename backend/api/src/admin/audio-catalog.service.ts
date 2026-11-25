import { Injectable, NotAcceptableException, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { MediaSigner } from '../playback/media-signer.service';
import { inspectSignedMediaObject } from '../playback/signed-media-presence';
import { AUDIO_QUALITY_ORDER } from '../playback/audio-variant-selection';

@Injectable()
export class AudioCatalogAdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly signer: MediaSigner,
  ) {}

  /**
   * Promotes only an existing R2 audio object to "ready"; never accepts a
   * client-supplied media URL, checksum, content type or claimed file size.
   * A separate rights decision is still mandatory for every listener.
   */
  async verifyAsset(actorId: string, trackId: string, quality: string) {
    if (!AUDIO_QUALITY_ORDER.includes(quality as typeof AUDIO_QUALITY_ORDER[number])) {
      throw new NotAcceptableException('INVALID_AUDIO_QUALITY');
    }
    const track = await this.prisma.track.findUnique({
      where: { id: trackId },
      select: { source: true, externalId: true },
    });
    if (!track || track.source !== 'breezze_internal' || track.externalId !== null) {
      throw new NotAcceptableException('AUDIO_ASSET_REQUIRES_INTERNAL_RECORDING');
    }

    const signed = this.signer.createPlaybackUrl(trackId, quality);
    // Force HEAD in staging and production: no false "ready" flags in QA.
    const scanned = await inspectSignedMediaObject(signed.url, { force: true });
    if (!scanned) throw new NotFoundException('AUDIO_ASSET_NOT_VERIFIED');
    const allowed = quality === 'LOSSLESS' || quality === 'HI_RES'
      ? ['audio/flac', 'audio/x-flac']
      : ['audio/mp4', 'audio/aac'];
    if (!allowed.includes(scanned.mimeType)) {
      throw new NotAcceptableException('AUDIO_ASSET_CODEC_MISMATCH');
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.audioAssetVariant.upsert({
        where: { trackId_quality: { trackId, quality } },
        create: {
          trackId, quality, status: 'ready',
          mimeType: scanned.mimeType, sizeBytes: BigInt(scanned.sizeBytes),
          verifiedAt: new Date(),
        },
        update: {
          status: 'ready', mimeType: scanned.mimeType,
          sizeBytes: BigInt(scanned.sizeBytes), verifiedAt: new Date(),
        },
      });
      await tx.adminAuditEvent.create({
        data: {
          actorId, action: 'audio.asset.verified', targetType: 'audio_asset_variant',
          targetId: trackId, metadata: { quality, sizeBytes: scanned.sizeBytes, mimeType: scanned.mimeType },
        },
      });
    });
    return { trackId, quality, status: 'ready',
      sizeBytes: scanned.sizeBytes, mimeType: scanned.mimeType };
  }

  /** An admin must explicitly approve the identity match after an asset was
   * ingested; similarity or YouTube metadata cannot self-approve. */
  async approveMatch(actorId: string, externalTrackId: string, playableTrackId: string) {
    if (!/^bz:youtube_music:[A-Za-z0-9_-]{11}$/.test(externalTrackId)) {
      throw new NotAcceptableException('INVALID_EXTERNAL_TRACK_ID');
    }
    const track = await this.prisma.track.findUnique({
      where: { id: playableTrackId },
      select: { source: true, externalId: true },
    });
    if (!track || track.source !== 'breezze_internal' || track.externalId !== null) {
      throw new NotAcceptableException('MATCH_REQUIRES_INTERNAL_RECORDING');
    }
    const [assetCount, permission, takedown] = await Promise.all([
      this.prisma.audioAssetVariant.count({
        where: { trackId: playableTrackId, status: 'ready',
          verifiedAt: { not: null }, sizeBytes: { gt: 0 } },
      }),
      this.prisma.rightsUsagePermission.findUnique({
        where: { trackId_action: { trackId: playableTrackId, action: 'stream.full' } },
      }),
      this.prisma.contentTakedownCase.findFirst({
        where: { trackId: playableTrackId, status: 'active' },
        select: { id: true },
      }),
    ]);
    const now = new Date();
    if (!assetCount || !permission ||
        (permission.startAt && permission.startAt > now) ||
        (permission.endAt && permission.endAt <= now) || takedown) {
      throw new NotAcceptableException('MATCH_RECORDING_NOT_PLAYABLE');
    }
    await this.prisma.$transaction(async (tx) => {
      await tx.catalogPlaybackMatch.upsert({
        where: { source_externalTrackId: { source: 'youtube_music', externalTrackId } },
        create: { source: 'youtube_music', externalTrackId,
          playableTrackId, status: 'approved', verifiedAt: now },
        update: { playableTrackId, status: 'approved', verifiedAt: now },
      });
      await tx.adminAuditEvent.create({
        data: {
          actorId, action: 'audio.catalog_match.approved',
          targetType: 'catalog_playback_match', targetId: externalTrackId,
          metadata: { playableTrackId, source: 'youtube_music' },
        },
      });
    });
    return { externalTrackId, playableTrackId, status: 'approved' };
  }
}
