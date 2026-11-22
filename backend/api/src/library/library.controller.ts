import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ArrayMaxSize, IsArray, IsBoolean, IsOptional, IsString, Matches,
  MaxLength, MinLength,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { LibraryService } from './library.service';

export class FavoriteDto {
  @IsString()
  trackId!: string;
}

export class SavedCatalogAlbumDto {
  @IsString()
  @Matches(/^[0-9]{1,20}$/)
  externalAlbumId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  artist!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  artworkUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  catalogUrl?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  genres?: string[];

  @IsOptional()
  @IsBoolean()
  isCompilation?: boolean;
}

@Controller('library')
@UseGuards(JwtAuthGuard)
export class LibraryController {
  constructor(private readonly library: LibraryService) {}

  @Get('albums')
  listSavedAlbums(
    @CurrentUser() userId: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.library.listSavedAlbums(userId, cursor);
  }

  @Post('albums')
  saveAlbum(@CurrentUser() userId: string, @Body() dto: SavedCatalogAlbumDto) {
    return this.library.upsertSavedAlbum(userId, dto);
  }

  @Delete('albums/:externalAlbumId')
  removeAlbum(
    @CurrentUser() userId: string,
    @Param('externalAlbumId') externalAlbumId: string,
  ) {
    return this.library.removeSavedAlbum(userId, externalAlbumId);
  }

  @Get('favorites')
  listFavorites(@CurrentUser() userId: string) {
    return this.library.listFavorites(userId);
  }

  @Post('favorites')
  addFavorite(@CurrentUser() userId: string, @Body() dto: FavoriteDto) {
    return this.library.addFavorite(userId, dto.trackId);
  }

  @Delete('favorites/:trackId')
  removeFavorite(
    @CurrentUser() userId: string,
    @Param('trackId') trackId: string,
  ) {
    return this.library.removeFavorite(userId, trackId);
  }
}
