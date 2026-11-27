import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AudioProofService } from './audio-proof.service';

@Controller('audio-proof')
@UseGuards(JwtAuthGuard)
export class AudioProofController {
  constructor(private readonly proof: AudioProofService) {}

  @Get('track')
  track() {
    return this.proof.track();
  }

  @Get('playback')
  playback() {
    return this.proof.playback();
  }
}
