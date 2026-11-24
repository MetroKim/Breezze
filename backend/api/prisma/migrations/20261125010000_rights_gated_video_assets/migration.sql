-- Video files are independent from metadata-only YouTube results.
-- A ready asset is a verified R2 object at video/<assetId>/original.mp4.
CREATE TABLE "VideoAsset" (
  "id" TEXT NOT NULL,
  "trackId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "mimeType" TEXT NOT NULL DEFAULT 'video/mp4',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "VideoAsset_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "VideoAsset_trackId_key" ON "VideoAsset"("trackId");
ALTER TABLE "VideoAsset" ADD CONSTRAINT "VideoAsset_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "VideoDownloadRecord" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "videoAssetId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "VideoDownloadRecord_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "VideoDownloadRecord_userId_videoAssetId_key"
  ON "VideoDownloadRecord"("userId", "videoAssetId");
CREATE INDEX "VideoDownloadRecord_userId_status_createdAt_idx"
  ON "VideoDownloadRecord"("userId", "status", "createdAt");
ALTER TABLE "VideoDownloadRecord" ADD CONSTRAINT "VideoDownloadRecord_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "VideoDownloadRecord" ADD CONSTRAINT "VideoDownloadRecord_videoAssetId_fkey"
  FOREIGN KEY ("videoAssetId") REFERENCES "VideoAsset"("id") ON DELETE CASCADE ON UPDATE CASCADE;
