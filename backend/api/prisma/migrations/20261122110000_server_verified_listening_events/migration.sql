ALTER TABLE "ListeningEvent"
ADD COLUMN "isServerVerified" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "ListeningEvent_userId_trackId_isServerVerified_idx"
ON "ListeningEvent"("userId", "trackId", "isServerVerified");

CREATE INDEX "ListeningEvent_trackId_createdAt_isServerVerified_idx"
ON "ListeningEvent"("trackId", "createdAt", "isServerVerified");
