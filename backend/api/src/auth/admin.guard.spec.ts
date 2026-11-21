import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard';

describe('AdminGuard', () => {
  const guard = new AdminGuard();
  const context = (role?: string) => ({
    switchToHttp: () => ({ getRequest: () => ({ user: role ? { role } : undefined }) }),
  }) as any;

  it('allows users with the persisted admin role', () => {
    expect(guard.canActivate(context('admin'))).toBe(true);
  });

  it.each(['user', 'moderator', undefined])('rejects non-admin role %s', (role) => {
    expect(() => guard.canActivate(context(role))).toThrow(ForbiddenException);
  });
});
