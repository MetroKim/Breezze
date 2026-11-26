-- Private user-uploaded cover thumbnails. Stored as bounded PNG base64 in the
-- owner's existing Playlist row. Playlist owner checks remain in NestJS APIs;
-- no public file bucket, exposed download URL, or provider stream is created.
ALTER TABLE "Playlist"
  ADD COLUMN "coverPngBase64" TEXT;

-- Private listener profile avatar thumbnail; never publicly exposed.
ALTER TABLE "User"
  ADD COLUMN "avatarPngBase64" TEXT;
