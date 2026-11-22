import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { DownloadsService } from './downloads.service';

export class AuthorizeDownloadDto {
  @IsUUID()
  trackId!: string;
}

@Controller('downloads')
@UseGuards(JwtAuthGuard)
export class DownloadsController {
  constructor(private readonly downloads: DownloadsService) {}

  @Post()
  authorize(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Body() dto: AuthorizeDownloadDto,
  ) {
    return this.downloads.authorizeAndRecord(userId, {
      trackId: dto.trackId,
      territory: edgeCountry ?? '',
    });
  }

  @Post(':trackId/revalidate')
  revalidate(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Param('trackId', new ParseUUIDPipe()) trackId: string,
  ) {
    return this.downloads.revalidateOfflineLease(userId, trackId, edgeCountry ?? '');
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
