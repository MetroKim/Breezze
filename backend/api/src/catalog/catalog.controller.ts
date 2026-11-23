import {
  Body,
  Controller,
  Get,
  Headers,
  NotAcceptableException,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsInt, IsString, Min, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CatalogService } from './catalog.service';

export class ResolveTrackDto {
  @IsString()
  @MinLength(1)
  externalId!: string;

  @IsString()
  @MinLength(1)
  source!: string;

  @IsString()
  @MinLength(1)
  title!: string;

  @IsString()
  @MinLength(1)
  artistName!: string;

  @IsInt()
  @Min(1)
  durationSec!: number;
}

function requireEdgeTerritory(value?: string): string {
  const territory = value?.trim().toUpperCase();
  if (!territory || !/^[A-Z]{2}$/.test(territory)) {
    throw new NotAcceptableException('CATALOG_TERRITORY_UNAVAILABLE');
  }
  return territory;
}

@Controller('catalog')
export class CatalogController {
  constructor(private readonly catalog: CatalogService) {}

  @Post('resolve')
  @UseGuards(JwtAuthGuard)
  resolve(@Body() dto: ResolveTrackDto) {
    return this.catalog.resolve(dto);
  }

  @Get('songs/:id')
  song(
    @Param('id') id: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
  ) {
    return this.catalog.song(id, requireEdgeTerritory(edgeCountry));
  }

  @Get('albums/:id')
  album(
    @Param('id') id: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
  ) {
    return this.catalog.album(id, requireEdgeTerritory(edgeCountry));
  }

  @Get('artists/:id')
  artist(
    @Param('id') id: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
  ) {
    return this.catalog.artist(id, requireEdgeTerritory(edgeCountry));
  }
}
