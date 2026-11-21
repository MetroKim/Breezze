import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { IsIn, IsUUID } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { AdminService } from './admin.service';

export class RoleDto {
  @IsUUID()
  userId!: string;

  @IsIn(['admin', 'moderator', 'user'])
  role!: string;
}

// All administrative operations require a persisted admin role.
@Controller('admin')
@UseGuards(JwtAuthGuard, AdminGuard)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('dashboard')
  dashboard() {
    return this.admin.dashboard();
  }

  @Get('takedowns')
  takedowns() {
    return this.admin.listTakedowns();
  }

  @Post('takedowns/:id/resolve')
  resolve(@Param('id') id: string) {
    return this.admin.resolveTakedown(id);
  }

  @Post('roles')
  grantRole(@Body() dto: RoleDto) {
    return this.admin.createUserRole(dto.userId, dto.role);
  }
}
