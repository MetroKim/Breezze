-- Store only SHA-256 hashes of high-entropy refresh tokens.
-- Existing raw tokens are hashed in-place so active sessions remain valid.
-- This is safe for a fresh DB (no table) and for a DB already created from
-- the updated Prisma schema (tokenHash column already exists).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND table_name = 'RefreshToken'
      AND column_name = 'token'
  ) THEN
    ALTER TABLE "RefreshToken" RENAME COLUMN "token" TO "tokenHash";
    UPDATE "RefreshToken"
    SET "tokenHash" = encode(digest("tokenHash", 'sha256'), 'hex');
  END IF;
END
$$;
