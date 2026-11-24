-- Account-scoped, owner-authorized playlist pinning.
-- Existing playlist IDs, ordered tracks and offline journals remain untouched.
ALTER TABLE "Playlist"
  ADD COLUMN "isPinned" BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX "Playlist_userId_isPinned_createdAt_idx"
  ON "Playlist"("userId", "isPinned", "createdAt");
