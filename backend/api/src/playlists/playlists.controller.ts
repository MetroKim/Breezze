import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ArrayUnique, IsArray, IsBoolean, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { PlaylistsService } from './playlists.service';

export class CreatePlaylistDto {
  @IsString()
  @MaxLength(128)
  name!: string;

  @IsOptional()
  @IsUUID('4')
  id?: string;
}

export class RenamePlaylistDto {
  @IsString()
  @MaxLength(128)
  name!: string;
}

export class PinPlaylistDto {
  @IsBoolean()
  pinned!: boolean;
}

export class AddTrackDto {
  @IsString()
  trackId!: string;
}

export class ReorderPlaylistDto {
  @IsArray()
  @ArrayUnique()
  @IsString({ each: true })
  trackIds!: string[];
}

@Controller('playlists')
@UseGuards(JwtAuthGuard)
export class PlaylistsController {
  constructor(private readonly playlists: PlaylistsService) {}

  @Post()
  create(
    @CurrentUser() userId: string,
    @Body() dto: CreatePlaylistDto,
  ) {
    return this.playlists.create(userId, dto.name, dto.id);
  }

  @Get()
  list(@CurrentUser() userId: string) {
    return this.playlists.list(userId);
  }

  @Get(':id')
  get(@CurrentUser() userId: string, @Param('id') id: string) {
    return this.playlists.get(userId, id);
  }

  @Patch(':id/pin')
  setPinned(
    @CurrentUser() userId: string,
    @Param('id') id: string,
    @Body() dto: PinPlaylistDto,
  ) {
    return this.playlists.setPinned(userId, id, dto.pinned);
  }

  @Patch(':id')
  rename(
    @CurrentUser() userId: string,
    @Param('id') id: string,
    @Body() dto: RenamePlaylistDto,
  ) {
    return this.playlists.rename(userId, id, dto.name);
  }

  @Delete(':id')
  delete(@CurrentUser() userId: string, @Param('id') id: string) {
    return this.playlists.delete(userId, id);
  }

  @Post(':id/tracks')
  addTrack(
    @CurrentUser() userId: string,
    @Param('id') id: string,
    @Body() dto: AddTrackDto,
  ) {
    return this.playlists.addTrack(userId, id, dto.trackId);
  }

  @Patch(':id/tracks/order')
  reorderTracks(
    @CurrentUser() userId: string,
    @Param('id') id: string,
    @Body() dto: ReorderPlaylistDto,
  ) {
    return this.playlists.reorderTracks(userId, id, dto.trackIds);
  }

  @Delete(':id/tracks/:trackId')
  removeTrack(
    @CurrentUser() userId: string,
    @Param('id') id: string,
    @Param('trackId') trackId: string,
  ) {
    return this.playlists.removeTrack(userId, id, trackId);
  }
}
