import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { IsIn, IsInt, IsUUID, Matches, Max, Min } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { AudioCatalogAdminService } from './audio-catalog.service';

export class VerifyAudioAssetDto {
  @IsUUID() trackId!: string;
  @IsIn(['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES'])
  quality!: string;
}

export class IssueAudioIngestDto {
  @IsUUID() trackId!: string;
  @IsIn(['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES']) quality!: string;
  @IsIn(['audio/mp4', 'audio/aac', 'audio/flac', 'audio/x-flac']) mimeType!: string;
  @IsInt() @Min(12) @Max(500 * 1024 * 1024) sizeBytes!: number;
}

export class ApproveCatalogMatchDto {
  @Matches(/^bz:youtube_music:[A-Za-z0-9_-]{11}$/)
  externalTrackId!: string;
  @IsUUID() playableTrackId!: string;
}

/** The ingestion registry is privileged. Never exposed to listeners. */
@Controller('admin/audio-catalog')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AudioCatalogAdminController {
  constructor(private readonly catalog: AudioCatalogAdminService) {}

  @Post('issue-ingest')
  issueIngest(@CurrentUser() actor: string, @Body() dto: IssueAudioIngestDto) {
    return this.catalog.issueIngestGrant(
      actor, dto.trackId, dto.quality, dto.mimeType, dto.sizeBytes,
    );
  }

  @Post('verify-asset')
  verifyAsset(@CurrentUser() actor: string, @Body() dto: VerifyAudioAssetDto) {
    return this.catalog.verifyAsset(actor, dto.trackId, dto.quality);
  }

  @Post('approve-match')
  approveMatch(@CurrentUser() actor: string, @Body() dto: ApproveCatalogMatchDto) {
    return this.catalog.approveMatch(actor, dto.externalTrackId, dto.playableTrackId);
  }
}
