import { Module } from '@nestjs/common';
import { AudioProofController } from './audio-proof.controller';
import { AudioProofService } from './audio-proof.service';

@Module({
  controllers: [AudioProofController],
  providers: [AudioProofService],
})
export class AudioProofModule {}
