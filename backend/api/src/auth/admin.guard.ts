import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';

@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<{
      user?: { role?: string; mfaEnabled?: boolean; mfaVerified?: boolean };
    }>();
    if (request.user?.role !== 'admin') {
      throw new ForbiddenException('ADMIN_ACCESS_REQUIRED');
    }
    if (request.user.mfaEnabled !== true || request.user.mfaVerified !== true) {
      throw new ForbiddenException('ADMIN_MFA_REQUIRED');
    }
    return true;
  }
}
