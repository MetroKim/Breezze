import {
  Body,
  Headers,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { PlaybackResolveService } from './playback-resolve.service';

export class ProviderResolveDto {
  @IsString()
  providerId!: string;

  @IsString()
  providerTrackId!: string;

  @IsString()
  canonicalTrackId!: string;

  @IsOptional()
  @IsString()
  territory?: string;
}

export class ResolveDto {
  @IsString()
  trackId!: string;

  // Deprecated compatibility field. Playback authorization uses only the
  // country injected by the trusted Cloudflare Worker.
  @IsOptional()
  @IsString()
  territory?: string;

  @IsOptional()
  @IsIn(['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES'])
  requestedQuality?: string;
}

@Controller('playback')
export class PlaybackController {
  constructor(private readonly resolver: PlaybackResolveService) {}

  @Post('provider/resolve')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  resolveProvider(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Body() dto: ProviderResolveDto,
  ) {
    return this.resolver.resolveProvider(userId, dto, edgeCountry);
  }

  @Post('resolve')
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  resolve(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
    @Body() dto: ResolveDto,
  ) {
    return this.resolver.resolve(userId, dto, edgeCountry);
  }
}
