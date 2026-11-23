CREATE TABLE IF NOT EXISTS "AdminAuditEvent" (
  "id" TEXT NOT NULL,
  "actorId" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "targetType" TEXT NOT NULL,
  "targetId" TEXT NOT NULL,
  "metadata" JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminAuditEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "AdminAuditEvent_createdAt_idx" ON "AdminAuditEvent"("createdAt");
CREATE INDEX IF NOT EXISTS "AdminAuditEvent_actorId_createdAt_idx" ON "AdminAuditEvent"("actorId", "createdAt");
CREATE INDEX IF NOT EXISTS "AdminAuditEvent_targetType_targetId_createdAt_idx" ON "AdminAuditEvent"("targetType", "targetId", "createdAt");
