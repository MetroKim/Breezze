import {
  Body,
  Controller,
  Get,
  GoneException,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { HomeService } from './home.service';

export class RecordRecentDto {
  @IsUUID()
  trackId!: string;
}

@Controller('home')
@UseGuards(JwtAuthGuard)
export class HomeController {
  constructor(private readonly home: HomeService) {}

  @Get()
  feed(@CurrentUser() userId: string) {
    return this.home.feed(userId);
  }

  @Post('recent')
  recordRecent(@CurrentUser() userId: string, @Body() dto: RecordRecentDto) {
    return this.home.recordRecent(userId, dto.trackId);
  }

  // Qualified ListeningEvents are now created only by server-authorized
  // playback sessions. Client-reported durations are not playback evidence.
  @Post('plays')
  @HttpCode(HttpStatus.GONE)
  recordPlay(): never {
    throw new GoneException('PLAYBACK_SESSION_REQUIRED');
  }
}
