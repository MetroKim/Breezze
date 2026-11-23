-- Breezze listener app does not accept artist claims or user release uploads.
-- Remove the legacy artist-facing workflow tables; catalog Artist metadata remains.
DROP TABLE IF EXISTS "MediaJob";
DROP TABLE IF EXISTS "ReleaseSubmission";
DROP TABLE IF EXISTS "ArtistClaim";
