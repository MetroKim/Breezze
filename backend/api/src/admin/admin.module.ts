import { AdminGuard } from '../auth/admin.guard';
import { PlaybackModule } from '../playback/playback.module';
import { AudioCatalogAdminController } from './audio-catalog.controller';
import { AudioCatalogAdminService } from './audio-catalog.service';
import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [PlaybackModule],
  controllers: [AdminController, AudioCatalogAdminController],
  providers: [AdminService, AdminGuard, AudioCatalogAdminService],
  exports: [AdminService],
})
export class AdminModule {}
