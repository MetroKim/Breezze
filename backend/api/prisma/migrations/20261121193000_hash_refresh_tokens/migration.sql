-- Store only SHA-256 hashes of high-entropy refresh tokens.
-- Existing raw tokens are hashed in-place so active sessions remain valid.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE "RefreshToken" RENAME COLUMN "token" TO "tokenHash";

UPDATE "RefreshToken"
SET "tokenHash" = encode(digest("tokenHash", 'sha256'), 'hex');

