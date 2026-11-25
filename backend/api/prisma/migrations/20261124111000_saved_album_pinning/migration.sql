-- Additive owner-scoped album pinning; existing bookmarks are preserved.
ALTER TABLE "UserSavedCatalogAlbum"
  ADD COLUMN "isPinned" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "UserSavedCatalogAlbum_userId_isPinned_savedAt_id_idx"
  ON "UserSavedCatalogAlbum"("userId", "isPinned", "savedAt", "id");
DROP INDEX IF EXISTS "UserSavedCatalogAlbum_userId_savedAt_id_idx";
