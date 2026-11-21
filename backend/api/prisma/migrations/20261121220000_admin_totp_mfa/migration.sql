ALTER TABLE "User"
  ADD COLUMN "mfaEnabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "mfaSecretCiphertext" TEXT,
  ADD COLUMN "mfaPendingSecretCiphertext" TEXT;

ALTER TABLE "RefreshToken"
  ADD COLUMN "mfaVerified" BOOLEAN NOT NULL DEFAULT false;
