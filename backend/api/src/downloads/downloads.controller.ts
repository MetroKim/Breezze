import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsString } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { DownloadsService } from './downloads.service';

export class RevalidateDownloadDto {
  @IsString()
  territory!: string;
}

export class AuthorizeDownloadDto {
  @IsString()
  trackId!: string;

  @IsString()
  territory!: string;
}

@Controller('downloads')
@UseGuards(JwtAuthGuard)
export class DownloadsController {
  constructor(private readonly downloads: DownloadsService) {}

  @Post()
  authorize(
    @CurrentUser() userId: string,
    @Body() dto: AuthorizeDownloadDto,
  ) {
    return this.downloads.authorizeAndRecord(userId, dto);
  }

  @Post(':trackId/revalidate')
  revalidate(
    @CurrentUser() userId: string,
    @Param('trackId') trackId: string,
    @Body() dto: RevalidateDownloadDto,
  ) {
    return this.downloads.revalidateOfflineLease(userId, trackId, dto.territory);
  }

  @Get()
  list(@CurrentUser() userId: string) {
    return this.downloads.list(userId);
  }

  @Delete(':trackId')
  remove(@CurrentUser() userId: string, @Param('trackId') trackId: string) {
    return this.downloads.remove(userId, trackId);
  }
}
