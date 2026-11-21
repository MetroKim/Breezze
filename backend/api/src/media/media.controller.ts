import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsInt, IsString, Min } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { MediaService } from './media.service';

export class RegisterUploadDto {
  @IsString()
  submissionId!: string;

  @IsString()
  originalFilename!: string;

  @IsInt()
  @Min(1)
  bytes!: number;
}

@Controller('media')
@UseGuards(JwtAuthGuard)
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post('uploads')
  register(@CurrentUser() userId: string, @Body() dto: RegisterUploadDto) {
    return this.media.registerUpload(userId, dto);
  }

  @Post('jobs/:id/complete')
  complete(@CurrentUser() userId: string, @Param('id') id: string) {
    return this.media.completeUpload(userId, id);
  }

  @Get('jobs')
  jobs(@CurrentUser() userId: string) {
    return this.media.listJobs(userId);
  }
}
