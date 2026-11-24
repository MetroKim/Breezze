import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { YoutubeAccountController } from './youtube-account.controller';
import { YoutubeAccountService } from './youtube-account.service';

@Module({
  imports: [AuthModule],
  controllers: [YoutubeAccountController],
  providers: [YoutubeAccountService],
})
export class YoutubeAccountModule {}
