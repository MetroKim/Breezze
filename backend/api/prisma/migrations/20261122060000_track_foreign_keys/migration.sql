-- Remove pre-existing orphan rows before adding referential constraints.
DELETE FROM "LyricTranslation" lt
WHERE NOT EXISTS (SELECT 1 FROM "Lyrics" l WHERE l."id" = lt."lyricsId");

DELETE FROM "Lyrics" l
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = l."trackId");

DELETE FROM "PlaylistItem" pi
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = pi."trackId");

DELETE FROM "DownloadRecord" d
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = d."trackId");

DELETE FROM "Favorite" f
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = f."trackId");

DELETE FROM "RecentlyPlayed" rp
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = rp."trackId");

DELETE FROM "ListeningEvent" le
WHERE NOT EXISTS (SELECT 1 FROM "Track" t WHERE t."id" = le."trackId");

ALTER TABLE "Favorite"
  ADD CONSTRAINT "Favorite_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "RecentlyPlayed"
  ADD CONSTRAINT "RecentlyPlayed_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "ListeningEvent"
  ADD CONSTRAINT "ListeningEvent_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "PlaylistItem"
  ADD CONSTRAINT "PlaylistItem_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "DownloadRecord"
  ADD CONSTRAINT "DownloadRecord_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "Lyrics"
  ADD CONSTRAINT "Lyrics_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "LyricTranslation"
  ADD CONSTRAINT "LyricTranslation_lyricsId_fkey"
  FOREIGN KEY ("lyricsId") REFERENCES "Lyrics"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
