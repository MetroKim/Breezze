import {
  Body,
  Controller,
  Get,
  Headers,
  NotAcceptableException,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { LyricsService } from './lyrics.service';

export class LyricsRequestDto {
  @IsString()
  @IsUUID()
  trackId!: string;
}

export class LyricsTranslationsQueryDto {
  @IsUUID()
  lyricsId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(35)
  language?: string;
}

function requireEdgeTerritory(value?: string): string {
  const territory = value?.trim().toUpperCase();
  if (!territory || !/^[A-Z]{2}$/.test(territory)) {
    throw new NotAcceptableException('LYRICS_TERRITORY_UNAVAILABLE');
  }
  return territory;
}

@Controller('lyrics')
@UseGuards(JwtAuthGuard)
export class LyricsController {
  constructor(private readonly lyrics: LyricsService) {}

  @Post()
  getLyrics(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Body() dto: LyricsRequestDto,
  ) {
    return this.lyrics.getLyrics(userId, {
      trackId: dto.trackId,
      territory: requireEdgeTerritory(edgeCountry),
    });
  }

  @Get('translations')
  translations(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Query() dto: LyricsTranslationsQueryDto,
  ) {
    return this.lyrics.getTranslations(
      userId,
      dto.lyricsId,
      requireEdgeTerritory(edgeCountry),
      dto.language,
    );
  }
}
