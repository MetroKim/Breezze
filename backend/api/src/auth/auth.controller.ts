import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  HttpCode,
  HttpStatus,
  Post,
  Param,
  UseGuards,
} from '@nestjs/common';
import { assertLegacyAuthAllowed } from './legacy-auth-policy';
import { IsEmail, IsString, IsOptional, Matches, MaxLength, MinLength } from 'class-validator';
import { AuthService } from './auth.service';
import { SupabaseExchangeService } from './supabase-exchange.service';
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

export class PasswordReauthDto {
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;
}

export class TotpCodeDto {
  @IsString()
  @Matches(/^(?:\d{6}|[A-Fa-f0-9]{4}(?:-?[A-Fa-f0-9]{4}){3})$/)
  code!: string;
}

export class MfaRecoveryRegenerationDto {
  @IsString()
  @MinLength(1)
  @MaxLength(128)
  password!: string;

  @IsString()
  @Matches(/^(?:\d{6}|[A-Fa-f0-9]{4}(?:-?[A-Fa-f0-9]{4}){3})$/)
  code!: string;
}

export class RefreshDto {
  @IsString()
  @MinLength(32)
  @MaxLength(256)
  refreshToken!: string;
}

export class SupabaseExchangeDto {
  @IsString()
  @MinLength(20)
  @MaxLength(8192)
  accessToken!: string;
}

export class SupabaseLinkLegacyDto extends SupabaseExchangeDto {
  @IsEmail()
  @MaxLength(320)
  legacyEmail!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(128)
  legacyPassword!: string;
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly supabaseExchange: SupabaseExchangeService,
  ) {}

  // Transitional: only a token validated by Supabase Auth may be exchanged.
  // This route never links a preexisting Breezze account by email alone.
  @Post('supabase/exchange')
  @HttpCode(HttpStatus.OK)
  @Header('Cache-Control', 'no-store')
  exchangeSupabase(@Body() dto: SupabaseExchangeDto) {
    return this.supabaseExchange.exchange(dto.accessToken);
  }

  // Two independently verified credentials; never link by email alone.
  // Rate-limited by the same account quota as password login.
  @Post('supabase/link-legacy')
  @HttpCode(HttpStatus.OK)
  @Header('Cache-Control', 'no-store')
  linkSupabaseLegacy(@Body() dto: SupabaseLinkLegacyDto) {
    return this.supabaseExchange.linkLegacy(
      dto.accessToken,
      dto.legacyEmail,
      dto.legacyPassword,
    );
  }

  @Post('register')
  register(@Body() dto: RegisterDto) {
    assertLegacyAuthAllowed();
    return this.auth.register(dto.email, dto.password, dto.displayName);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto) {
    assertLegacyAuthAllowed();
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
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  beginMfaSetup(@CurrentUser() userId: string, @Body() dto: PasswordReauthDto) {
    return this.auth.beginMfaSetup(userId, dto.password);
  }

  @Post('mfa/setup/verify')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  verifyMfaSetup(
    @CurrentUser() userId: string,
    @CurrentSession() sessionId: string,
    @Body() dto: TotpCodeDto,
  ) {
    return this.auth.verifyMfaSetup(userId, sessionId, dto.code);
  }

  @Post('mfa/recovery-codes/regenerate')
  @Header('Cache-Control', 'private, no-store')
  @UseGuards(JwtAuthGuard)
  regenerateMfaRecoveryCodes(
    @CurrentUser() userId: string,
    @CurrentSession() sessionId: string,
    @Body() dto: MfaRecoveryRegenerationDto,
  ) {
    return this.auth.regenerateMfaRecoveryCodes(userId, sessionId, dto.password, dto.code);
  }

  @Post('mfa/verify')
  @Header('Cache-Control', 'private, no-store')
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
