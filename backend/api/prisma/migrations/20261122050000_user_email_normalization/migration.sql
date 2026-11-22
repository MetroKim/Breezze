DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "User"
    GROUP BY LOWER(BTRIM("email"))
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot normalize Breezze user emails: case-insensitive duplicates exist';
  END IF;
END $$;

UPDATE "User"
SET "email" = LOWER(BTRIM("email"))
WHERE "email" <> LOWER(BTRIM("email"));

CREATE UNIQUE INDEX "User_email_lower_key"
ON "User" (LOWER("email"));
