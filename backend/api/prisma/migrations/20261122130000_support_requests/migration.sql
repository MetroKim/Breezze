CREATE TABLE "SupportRequest" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "subject" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "SupportRequest_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SupportRequest_userId_createdAt_idx"
    ON "SupportRequest"("userId", "createdAt");

CREATE INDEX "SupportRequest_status_createdAt_idx"
    ON "SupportRequest"("status", "createdAt");

ALTER TABLE "SupportRequest"
    ADD CONSTRAINT "SupportRequest_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "User"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
