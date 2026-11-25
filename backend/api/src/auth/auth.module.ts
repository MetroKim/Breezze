import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { SocialAuthController } from './social-auth.controller';
import { SocialAuthService } from './social-auth.service';
import { JwtStrategy } from './jwt.strategy';
import { JwtAuthGuard } from './jwt-auth.guard';
import { SupabaseExchangeService } from './supabase-exchange.service';
import { jwtSecretForEnvironment } from './legacy-auth-policy';

@Module({
  imports: [
    PassportModule,
    JwtModule.register({
      secret: jwtSecretForEnvironment(process.env.NODE_ENV, process.env.JWT_SECRET),
    }),
  ],
  controllers: [AuthController, SocialAuthController],
  providers: [AuthService, SocialAuthService, SupabaseExchangeService, JwtStrategy, JwtAuthGuard],
  exports: [AuthService, JwtAuthGuard],
})
export class AuthModule {}
