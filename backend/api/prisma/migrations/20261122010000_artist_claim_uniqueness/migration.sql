-- A user may submit only one claim per artist. This also makes concurrent
-- duplicate submissions fail at the database boundary instead of creating
-- duplicate pending records.
CREATE UNIQUE INDEX IF NOT EXISTS "ArtistClaim_userId_artistId_key"
ON "ArtistClaim"("userId", "artistId");

-- An artist may have only one approved claimant, even if two moderation
-- requests race. Pending claims remain allowed from different accounts.
CREATE UNIQUE INDEX IF NOT EXISTS "ArtistClaim_one_approved_per_artist_key"
ON "ArtistClaim"("artistId")
WHERE "status" = 'approved';
