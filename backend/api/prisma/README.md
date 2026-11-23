# Breezze PostgreSQL migrations

The migration history now starts with `20261120000000_initial_schema`, a Prisma-generated baseline for the current schema. Later migrations preserve the incremental security changes and are safe to run after this baseline.

## Fresh database

Create an empty PostgreSQL database and set `DATABASE_URL`, then run:

```bash
npx prisma migrate deploy
npx prisma generate
```

CI uses a fresh PostgreSQL 16 service and runs `prisma migrate deploy` before backend tests, including the concurrent artist-claim constraint tests.

## Existing database created before the baseline

Some earlier development databases may have been initialized with `prisma db push` rather than a complete migration history. Do not run the initial baseline against a database that already contains the tables: it is a create-schema migration.

1. Take and verify a database backup.
2. Confirm the database schema matches the current Prisma schema. From `backend/api`, run:

   ```bash
   npx prisma migrate diff \
     --from-url "$DATABASE_URL" \
     --to-schema-datamodel prisma/schema.prisma \
     --script
   ```

3. If the diff is not empty, stop and reconcile the schema manually. Do not mark the baseline applied while required tables, columns, indexes or foreign keys are missing.
4. Only after confirming the existing schema is equivalent to the baseline, mark the baseline as already applied:

   ```bash
   npx prisma migrate resolve --applied 20261120000000_initial_schema
   ```

5. Apply any later migrations that are not recorded as applied:

   ```bash
   npx prisma migrate deploy
   ```

Never use `prisma db push` as the ongoing production migration mechanism. Use a dedicated migration database role; the API runtime role must not own the schema.

## Existing-data preflight

The artist-claim migration adds:
- A unique index on `(userId, artistId)`.
- A partial unique index that allows only one approved claim per artist.

Before deploying to an existing database, check and reconcile duplicate claims. The migration deliberately fails rather than deleting or arbitrarily merging user claim records.

```sql
SELECT "userId", "artistId", COUNT(*)
FROM "ArtistClaim"
GROUP BY "userId", "artistId"
HAVING COUNT(*) > 1;

SELECT "artistId", COUNT(*)
FROM "ArtistClaim"
WHERE "status" = 'approved'
GROUP BY "artistId"
HAVING COUNT(*) > 1;
```
