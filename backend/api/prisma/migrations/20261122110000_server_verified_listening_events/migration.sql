ALTER TABLE "ListeningEvent"
ADD COLUMN "isServerVerified" BOOLEAN NOT NULL DEFAULT false;

DROP INDEX IF EXISTS "ListeningEvent_userId_trackId_idx";
DROP INDEX IF EXISTS "ListeningEvent_trackId_createdAt_idx";

CREATE INDEX "ListeningEvent_userId_isServerVerified_trackId_idx"
ON "ListeningEvent"("userId", "isServerVerified", "trackId");

CREATE INDEX "ListeningEvent_isServerVerified_trackId_createdAt_idx"
ON "ListeningEvent"("isServerVerified", "trackId", "createdAt");
