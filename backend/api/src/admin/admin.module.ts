import { AdminGuard } from '../auth/admin.guard';
import { PlaybackModule } from '../playback/playback.module';
import { AudioCatalogAdminController } from './audio-catalog.controller';
import { AudioCatalogAdminService } from './audio-catalog.service';
import { VideoCatalogAdminController } from './video-catalog.controller';
import { VideoCatalogAdminService } from './video-catalog.service';
import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [PlaybackModule],
  controllers: [AdminController, AudioCatalogAdminController, VideoCatalogAdminController],
  providers: [AdminService, AdminGuard, AudioCatalogAdminService, VideoCatalogAdminService],
  exports: [AdminService],
})
export class AdminModule {}
