-- Prevent ordinary application credentials from mutating or deleting audit evidence.
-- A database owner/superuser can still disable triggers; production ownership
-- and grants must keep those credentials out of the API runtime.
CREATE OR REPLACE FUNCTION "reject_admin_audit_event_mutation"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'ADMIN_AUDIT_EVENTS_ARE_APPEND_ONLY'
    USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS "AdminAuditEvent_append_only" ON "AdminAuditEvent";
CREATE TRIGGER "AdminAuditEvent_append_only"
BEFORE UPDATE OR DELETE ON "AdminAuditEvent"
FOR EACH ROW
EXECUTE FUNCTION "reject_admin_audit_event_mutation"();
