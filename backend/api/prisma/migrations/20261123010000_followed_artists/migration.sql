CREATE TABLE "UserFollowedArtist" (
    "userId" TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
    "artistKey" TEXT NOT NULL,
    PRIMARY KEY ("userId", "artistKey")
);
