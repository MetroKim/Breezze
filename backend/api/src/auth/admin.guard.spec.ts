import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';

describe('AdminGuard', () => {
  const guard = new AdminGuard();
  const context = (user?: { role?: string; mfaEnabled?: boolean; mfaVerified?: boolean }) => ({
    switchToHttp: () => ({ getRequest: () => ({ user }) }),
  }) as any;

  it('allows an admin only after MFA has been verified for this access token', () => {
    expect(guard.canActivate(context({ role: 'admin', mfaEnabled: true, mfaVerified: true }))).toBe(true);
  });

  it('rejects an admin whose session has not completed MFA', () => {
    expect(() => guard.canActivate(context({ role: 'admin', mfaEnabled: true, mfaVerified: false })))
      .toThrow('ADMIN_MFA_REQUIRED');
  });


  it('rejects an admin whose MFA enrollment is no longer active', () => {
    expect(() => guard.canActivate(context({ role: 'admin', mfaEnabled: false, mfaVerified: true })))
      .toThrow('ADMIN_MFA_REQUIRED');
  });

  it.each(['user', 'moderator', undefined])('rejects non-admin role %s', (role) => {
    expect(() => guard.canActivate(context(role ? { role, mfaEnabled: true, mfaVerified: true } : undefined)))
      .toThrow(ForbiddenException);
  });
});
