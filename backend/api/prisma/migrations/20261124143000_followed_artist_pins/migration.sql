-- Backfill old follows without losing account membership.
ALTER TABLE "UserFollowedArtist"
  ADD COLUMN "displayName" TEXT,
  ADD COLUMN "isPinned" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "followedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;
CREATE INDEX "UserFollowedArtist_userId_isPinned_followedAt_artistKey_idx"
  ON "UserFollowedArtist"("userId", "isPinned", "followedAt", "artistKey");
