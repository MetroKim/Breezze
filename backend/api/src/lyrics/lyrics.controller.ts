import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import {
  IsOptional,
  IsString,
  IsUUID,
  Length,
  MaxLength,
  Matches,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { LyricsService } from './lyrics.service';

export class LyricsRequestDto {
  @IsString()
  @IsUUID()
  trackId!: string;

  @IsString()
  @Length(2, 2)
  @Matches(/^[A-Z]{2}$/)
  territory!: string;
}

export class LyricsTranslationsQueryDto {
  @IsUUID()
  lyricsId!: string;

  @IsString()
  @Length(2, 2)
  @Matches(/^[A-Z]{2}$/)
  territory!: string;

  @IsOptional()
  @IsString()
  @MaxLength(35)
  language?: string;
}

@Controller('lyrics')
@UseGuards(JwtAuthGuard)
export class LyricsController {
  constructor(private readonly lyrics: LyricsService) {}

  @Post()
  getLyrics(
    @CurrentUser() userId: string,
    @Body() dto: LyricsRequestDto,
  ) {
    return this.lyrics.getLyrics(userId, dto);
  }

  @Get('translations')
  translations(
    @CurrentUser() userId: string,
    @Query() dto: LyricsTranslationsQueryDto,
  ) {
    return this.lyrics.getTranslations(
      userId,
      dto.lyricsId,
      dto.territory,
      dto.language,
    );
  }
}
