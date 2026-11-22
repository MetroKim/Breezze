-- Refuse to discard orphaned listener data. The migration locks all affected
-- tables before checking so no concurrent write can create a new orphan
-- between validation and constraint creation.
BEGIN;

LOCK TABLE "Track", "Favorite", "RecentlyPlayed", "ListeningEvent",
  "PlaylistItem", "DownloadRecord", "Lyrics", "LyricTranslation"
  IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "Favorite" f LEFT JOIN "Track" t ON t."id" = f."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: Favorite contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "RecentlyPlayed" rp LEFT JOIN "Track" t ON t."id" = rp."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: RecentlyPlayed contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "ListeningEvent" le LEFT JOIN "Track" t ON t."id" = le."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: ListeningEvent contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "PlaylistItem" pi LEFT JOIN "Track" t ON t."id" = pi."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: PlaylistItem contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "DownloadRecord" d LEFT JOIN "Track" t ON t."id" = d."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: DownloadRecord contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "Lyrics" l LEFT JOIN "Track" t ON t."id" = l."trackId" WHERE t."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Track foreign key: Lyrics contains orphan trackId values. Repair or archive these rows before retrying.';
  END IF;
  IF EXISTS (SELECT 1 FROM "LyricTranslation" lt LEFT JOIN "Lyrics" l ON l."id" = lt."lyricsId" WHERE l."id" IS NULL) THEN
    RAISE EXCEPTION 'Cannot add Lyrics foreign key: LyricTranslation contains orphan lyricsId values. Repair or archive these rows before retrying.';
  END IF;
END $$;

-- Keep canonical track rows stable: rights/takedown workflows should retire
-- tracks, not delete them and cascade away a listener's history or library.
ALTER TABLE "Favorite"
  ADD CONSTRAINT "Favorite_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "RecentlyPlayed"
  ADD CONSTRAINT "RecentlyPlayed_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "ListeningEvent"
  ADD CONSTRAINT "ListeningEvent_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "PlaylistItem"
  ADD CONSTRAINT "PlaylistItem_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "DownloadRecord"
  ADD CONSTRAINT "DownloadRecord_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Lyrics"
  ADD CONSTRAINT "Lyrics_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "LyricTranslation"
  ADD CONSTRAINT "LyricTranslation_lyricsId_fkey"
  FOREIGN KEY ("lyricsId") REFERENCES "Lyrics"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

COMMIT;
