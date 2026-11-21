import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Param,
  UseGuards,
} from '@nestjs/common';
import { IsEmail, IsString, IsOptional, MaxLength, MinLength } from 'class-validator';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { CurrentUser } from './current-user.decorator';
import { CurrentSession } from './current-session.decorator';

export class RegisterDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(12)
  @MaxLength(128)
  password!: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  displayName?: string;
}

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(1)
  password!: string;
}

export class TotpCodeDto {
  @IsString()
  @MinLength(6)
  @MaxLength(6)
  code!: string;
}

export class RefreshDto {
  @IsString()
  @MinLength(32)
  @MaxLength(256)
  refreshToken!: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto.email, dto.password, dto.displayName);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  logout(@Body() dto: RefreshDto) {
    return this.auth.logout(dto.refreshToken);
  }

  @Post('mfa/setup')
  @UseGuards(JwtAuthGuard)
  beginMfaSetup(@CurrentUser() userId: string) {
    return this.auth.beginMfaSetup(userId);
  }

  @Post('mfa/setup/verify')
  @UseGuards(JwtAuthGuard)
  verifyMfaSetup(
    @CurrentUser() userId: string,
    @CurrentSession() sessionId: string,
    @Body() dto: TotpCodeDto,
  ) {
    return this.auth.verifyMfaSetup(userId, sessionId, dto.code);
  }

  @Post('mfa/verify')
  @UseGuards(JwtAuthGuard)
  verifyMfa(
    @CurrentUser() userId: string,
    @CurrentSession() sessionId: string,
    @Body() dto: TotpCodeDto,
  ) {
    return this.auth.verifyMfa(userId, sessionId, dto.code);
  }

  @Get('me')
  @UseGuards(JwtAuthGuard)
  me(@CurrentUser() userId: string) {
    return this.auth.profile(userId);
  }

  @Get('sessions')
  @UseGuards(JwtAuthGuard)
  sessions(@CurrentUser() userId: string) {
    return this.auth.listSessions(userId);
  }

  @Delete('sessions/:id')
  @UseGuards(JwtAuthGuard)
  async revokeSession(@CurrentUser() userId: string, @Param('id') sessionId: string) {
    await this.auth.revokeSession(userId, sessionId);
    return { revoked: true };
  }
}
