import { ForbiddenException } from '@nestjs/common';

/**
 * Supabase owns all new production sign-ins. Existing accounts can still be
 * linked through /auth/supabase/link-legacy, which independently verifies a
 * Supabase identity and the old password without creating a legacy session.
 *
 * Keep the old endpoints available only in non-production integration tests
 * and during local migration work; never allow a production sign-in downgrade.
 */
export function assertLegacyAuthAllowed(environment = process.env.NODE_ENV): void {
  if (environment === 'production') {
    throw new ForbiddenException('SUPABASE_AUTH_REQUIRED');
  }
}

/**
 * A shared static/dev key is never acceptable for production JWT signing.
 * The backend must fail at boot rather than issue attacker-forgeable sessions.
 */
export function jwtSecretForEnvironment(
  environment: string | undefined,
  configured: string | undefined,
): string {
  if (environment === 'production' &&
      (!configured || configured.trim().length < 32)) {
    throw new Error('JWT_SECRET_REQUIRED_PRODUCTION');
  }
  return configured || 'dev-only-secret-change-me';
}
