CREATE TABLE "PlaybackSession" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "trackId" TEXT NOT NULL,
  "providerId" TEXT,
  "territory" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "startedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "lastHeartbeatAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "stoppedAt" TIMESTAMP(3),
  "lastSequence" INTEGER NOT NULL DEFAULT 0,
  "accumulatedMs" INTEGER NOT NULL DEFAULT 0,
  CONSTRAINT "PlaybackSession_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "PlaybackHeartbeat" (
  "id" TEXT NOT NULL,
  "sessionId" TEXT NOT NULL,
  "sequence" INTEGER NOT NULL,
  "elapsedMs" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PlaybackHeartbeat_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "PlaybackSession_userId_status_expiresAt_idx" ON "PlaybackSession"("userId","status","expiresAt");
CREATE INDEX "PlaybackSession_trackId_startedAt_idx" ON "PlaybackSession"("trackId","startedAt");
CREATE UNIQUE INDEX "PlaybackHeartbeat_sessionId_sequence_key" ON "PlaybackHeartbeat"("sessionId","sequence");
CREATE INDEX "PlaybackHeartbeat_sessionId_createdAt_idx" ON "PlaybackHeartbeat"("sessionId","createdAt");
ALTER TABLE "PlaybackSession" ADD CONSTRAINT "PlaybackSession_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "PlaybackSession" ADD CONSTRAINT "PlaybackSession_trackId_fkey"
  FOREIGN KEY ("trackId") REFERENCES "Track"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "PlaybackHeartbeat" ADD CONSTRAINT "PlaybackHeartbeat_sessionId_fkey"
  FOREIGN KEY ("sessionId") REFERENCES "PlaybackSession"("id") ON DELETE CASCADE ON UPDATE CASCADE;
