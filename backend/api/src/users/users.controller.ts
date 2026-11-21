import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  UseGuards,
} from '@nestjs/common';
import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CurrentUser } from '../auth/current-user.decorator';
import { UsersService } from './users.service';

export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  displayName?: string;
}

export class DeleteAccountDto {
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;
}

@Controller('users')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  me(@CurrentUser() userId: string) {
    return this.users.profile(userId);
  }

  @Patch('me')
  patchMe(
    @CurrentUser() userId: string,
    @Body() body: UpdateMeDto,
  ) {
    return this.users.update(userId, body);
  }

  @Delete('me')
  deleteMe(@CurrentUser() userId: string, @Body() dto: DeleteAccountDto) {
    return this.users.delete(userId, dto.password);
  }
}
