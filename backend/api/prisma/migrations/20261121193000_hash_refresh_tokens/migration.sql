-- Store only SHA-256 hashes of high-entropy refresh tokens.
-- Existing raw tokens are hashed in-place so active sessions remain valid.
-- The repository currently has no baseline schema migration, so this migration
-- safely no-ops on a brand-new database where RefreshToken does not exist yet.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF to_regclass('"RefreshToken"') IS NOT NULL THEN
    ALTER TABLE "RefreshToken" RENAME COLUMN "token" TO "tokenHash";
    UPDATE "RefreshToken"
    SET "tokenHash" = encode(digest("tokenHash", 'sha256'), 'hex');
  END IF;
END
$$;
