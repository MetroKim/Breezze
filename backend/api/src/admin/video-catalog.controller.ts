import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { IsInt, IsUUID, Max, Min } from 'class-validator';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { VideoCatalogAdminService } from './video-catalog.service';

class IssueVideoIngestDto {
  @IsUUID() trackId!: string;
  @IsInt() @Min(16) @Max(95_000_000) sizeBytes!: number;
}

class VerifyVideoAssetDto {
  @IsUUID() assetId!: string;
}

/** Listener accounts can never create or activate R2 video assets. */
@Controller('admin/video-catalog')
@UseGuards(JwtAuthGuard, AdminGuard)
export class VideoCatalogAdminController {
  constructor(private readonly catalog: VideoCatalogAdminService) {}

  @Post('issue-ingest')
  issueIngest(@CurrentUser() actorId: string, @Body() dto: IssueVideoIngestDto) {
    return this.catalog.issueIngest(actorId, dto.trackId, dto.sizeBytes);
  }

  @Post('verify-asset')
  verifyAsset(@CurrentUser() actorId: string, @Body() dto: VerifyVideoAssetDto) {
    return this.catalog.verifyAsset(actorId, dto.assetId);
  }
}
