-- Additive, account-scoped cloud album bookmarks.
-- Metadata is not a streaming/download entitlement.
CREATE TABLE "UserSavedCatalogAlbum" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'apple_itunes',
    "externalAlbumId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "artist" TEXT NOT NULL,
    "artworkUrl" TEXT,
    "catalogUrl" TEXT,
    "genres" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "isCompilation" BOOLEAN NOT NULL DEFAULT false,
    "savedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "UserSavedCatalogAlbum_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "UserSavedCatalogAlbum_userId_source_externalAlbumId_key"
    ON "UserSavedCatalogAlbum"("userId", "source", "externalAlbumId");

CREATE INDEX "UserSavedCatalogAlbum_userId_savedAt_id_idx"
    ON "UserSavedCatalogAlbum"("userId", "savedAt", "id");

ALTER TABLE "UserSavedCatalogAlbum"
    ADD CONSTRAINT "UserSavedCatalogAlbum_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
