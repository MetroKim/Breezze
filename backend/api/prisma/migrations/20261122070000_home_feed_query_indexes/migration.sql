CREATE INDEX "Track_artistId_title_idx" ON "Track"("artistId", "title");
CREATE INDEX "Favorite_userId_createdAt_idx" ON "Favorite"("userId", "createdAt");
CREATE INDEX "RecentlyPlayed_userId_playedAt_idx" ON "RecentlyPlayed"("userId", "playedAt");
CREATE INDEX "ListeningEvent_userId_trackId_idx" ON "ListeningEvent"("userId", "trackId");
CREATE INDEX "ListeningEvent_trackId_createdAt_idx" ON "ListeningEvent"("trackId", "createdAt");
CREATE INDEX "ContentTakedownCase_trackId_status_idx" ON "ContentTakedownCase"("trackId", "status");
