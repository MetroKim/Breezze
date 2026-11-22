import {
  Body,
  Controller,
  Get,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  IsIn,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { SupportService } from './support.service';

const SUPPORT_CATEGORIES = [
  'account',
  'playback',
  'downloads',
  'playlists',
  'bug',
  'feedback',
  'other',
] as const;

export class CreateSupportRequestDto {
  @IsString()
  @IsIn(SUPPORT_CATEGORIES)
  category!: string;

  @IsString()
  @MinLength(3)
  @MaxLength(120)
  subject!: string;

  @IsString()
  @MinLength(10)
  @MaxLength(5000)
  message!: string;
}

@Controller('support/requests')
@UseGuards(JwtAuthGuard)
export class SupportController {
  constructor(private readonly support: SupportService) {}

  @Post()
  create(
    @CurrentUser() userId: string,
    @Body() dto: CreateSupportRequestDto,
  ) {
    return this.support.create(userId, dto);
  }

  @Get()
  list(@CurrentUser() userId: string) {
    return this.support.list(userId);
  }
}
