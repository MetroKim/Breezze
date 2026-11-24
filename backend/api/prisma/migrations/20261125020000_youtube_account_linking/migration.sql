-- Dedicated YouTube account linking is separate from Breezze social login.
-- Secrets are AES-256-GCM ciphertext; keys live in server environment only.
CREATE TABLE "YoutubeAccountConnection" (
  "userId" TEXT NOT NULL,
  "channelId" TEXT NOT NULL,
  "channelTitle" TEXT,
  "accessTokenCiphertext" TEXT NOT NULL,
  "refreshTokenCiphertext" TEXT NOT NULL,
  "accessExpiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "YoutubeAccountConnection_pkey" PRIMARY KEY ("userId")
);
CREATE UNIQUE INDEX "YoutubeAccountConnection_channelId_key"
  ON "YoutubeAccountConnection"("channelId");
ALTER TABLE "YoutubeAccountConnection" ADD CONSTRAINT "YoutubeAccountConnection_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "YoutubeAccountLinkFlow" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "stateHash" TEXT NOT NULL,
  "codeVerifier" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completedAt" TIMESTAMP(3),
  CONSTRAINT "YoutubeAccountLinkFlow_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "YoutubeAccountLinkFlow_stateHash_key"
  ON "YoutubeAccountLinkFlow"("stateHash");
CREATE INDEX "YoutubeAccountLinkFlow_userId_status_createdAt_idx"
  ON "YoutubeAccountLinkFlow"("userId", "status", "createdAt");
CREATE INDEX "YoutubeAccountLinkFlow_expiresAt_idx"
  ON "YoutubeAccountLinkFlow"("expiresAt");
ALTER TABLE "YoutubeAccountLinkFlow" ADD CONSTRAINT "YoutubeAccountLinkFlow_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
