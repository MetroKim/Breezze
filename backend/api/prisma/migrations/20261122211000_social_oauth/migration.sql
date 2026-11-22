-- Social identities never implicitly link by matching email alone.
CREATE TABLE "SocialAuthIdentity" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "subject" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SocialAuthIdentity_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "SocialAuthIdentity_provider_subject_key" ON "SocialAuthIdentity"("provider","subject");
CREATE INDEX "SocialAuthIdentity_userId_provider_idx" ON "SocialAuthIdentity"("userId","provider");
ALTER TABLE "SocialAuthIdentity" ADD CONSTRAINT "SocialAuthIdentity_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "SocialLoginFlow" (
  "id" TEXT NOT NULL,
  "provider" TEXT NOT NULL,
  "stateHash" TEXT NOT NULL,
  "pollSecretHash" TEXT NOT NULL,
  "nonce" TEXT NOT NULL,
  "codeVerifier" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "resultCiphertext" TEXT,
  "errorCode" TEXT,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CONSTRAINT "SocialLoginFlow_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "SocialLoginFlow_stateHash_key" ON "SocialLoginFlow"("stateHash");
CREATE INDEX "SocialLoginFlow_expiresAt_idx" ON "SocialLoginFlow"("expiresAt");
