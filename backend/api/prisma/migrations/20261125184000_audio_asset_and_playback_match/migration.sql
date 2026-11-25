-- Asset catalogue: no media URLs, credentials or YouTube extraction data.
-- A "ready" row is created only after a verified, separately ingested R2 object.
CREATE TABLE "AudioAssetVariant" (
  "trackId" TEXT NOT NULL,
  "quality" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "mimeType" TEXT NOT NULL,
  "sizeBytes" BIGINT,
  "sha256" TEXT,
  "verifiedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "AudioAssetVariant_pkey" PRIMARY KEY ("trackId","quality"),
  CONSTRAINT "AudioAssetVariant_quality_check" CHECK ("quality" IN ('AAC_128','AAC_256','LOSSLESS','HI_RES')),
  CONSTRAINT "AudioAssetVariant_status_check" CHECK ("status" IN ('pending','ready','failed','revoked')),
  CONSTRAINT "AudioAssetVariant_size_check" CHECK ("sizeBytes" IS NULL OR "sizeBytes" > 0),
  CONSTRAINT "AudioAssetVariant_ready_check" CHECK (
    "status" <> 'ready' OR ("verifiedAt" IS NOT NULL AND "sizeBytes" IS NOT NULL)
  )
);
CREATE INDEX "AudioAssetVariant_status_verifiedAt_idx" ON "AudioAssetVariant"("status","verifiedAt");
ALTER TABLE "AudioAssetVariant" ADD CONSTRAINT "AudioAssetVariant_trackId_fkey"
 FOREIGN KEY ("trackId") REFERENCES "Track"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Third-party metadata can match an internal recording but cannot create it.
CREATE TABLE "CatalogPlaybackMatch" (
  "source" TEXT NOT NULL,
  "externalTrackId" TEXT NOT NULL,
  "playableTrackId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "verifiedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "CatalogPlaybackMatch_pkey" PRIMARY KEY ("source","externalTrackId"),
  CONSTRAINT "CatalogPlaybackMatch_status_check" CHECK ("status" IN ('pending','approved','rejected','revoked')),
  CONSTRAINT "CatalogPlaybackMatch_approval_check" CHECK ("status" <> 'approved' OR "verifiedAt" IS NOT NULL)
);
CREATE INDEX "CatalogPlaybackMatch_playableTrackId_status_idx" ON "CatalogPlaybackMatch"("playableTrackId","status");
ALTER TABLE "CatalogPlaybackMatch" ADD CONSTRAINT "CatalogPlaybackMatch_playableTrackId_fkey"
 FOREIGN KEY ("playableTrackId") REFERENCES "Track"("id") ON DELETE CASCADE ON UPDATE CASCADE;
