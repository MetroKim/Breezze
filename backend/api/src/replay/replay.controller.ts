import { Controller, Get, Headers, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { ReplayService } from './replay.service';

@Controller('replay')
@UseGuards(JwtAuthGuard)
export class ReplayController {
  constructor(private readonly replay: ReplayService) {}

  @Get()
  summary(
    @CurrentUser() userId: string,
    @Headers('x-breezze-country') edgeCountry: string | undefined,
  ) {
    return this.replay.summary(userId, edgeCountry);
  }
}
