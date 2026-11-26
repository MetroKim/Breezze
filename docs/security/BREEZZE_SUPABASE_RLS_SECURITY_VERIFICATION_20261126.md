# Breezze Supabase live RLS / Data API privileges verification

**Audit date:** 26 November 2026 • **Project:** `djwvyjtebmsavhcrmhxf` • **Status:** narrow migration verified; full auth acceptance open.

## Why the migration was necessary

The three user-data tables in the exposed `public` schema—`profiles`, `user_library`, and `pinned_playlists`—had RLS enabled with owner-scoped SELECT/INSERT/UPDATE/DELETE policies. However, the built-in `authenticated` role also had `TRUNCATE`, `REFERENCES`, `TRIGGER`, and `MAINTAIN` privileges. PostgreSQL explicitly excludes `TRUNCATE` and `REFERENCES` from row-level security: https://www.postgresql.org/docs/17/ddl-rowsecurity.html . This is a potentially destructive bypass despite correct CRUD RLS.

## Corrective Supabase migration (already applied)

**Version recorded by Supabase:** `20261126100716`  
**Name:** `breezze_revoke_rls_bypass_grants`

```sql
-- Restrict whole-table and DDL-like operations on user-owned data.
-- Preserve authenticated SELECT, INSERT, UPDATE, DELETE and existing RLS.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLE public.profiles, public.user_library, public.pinned_playlists
FROM anon, authenticated;
```

The migration succeeded. Do **not** rerun as a new migration under a different identifier or change the established Railway Prisma database: it is a Supabase project-specific privilege hardening action, not a schema replacement.

## Verification on the live project

A read-only post-migration query used `has_table_privilege('authenticated', 'public.<table>', '<privilege>')` for each of the three tables.

| Privilege | `profiles` | `user_library` | `pinned_playlists` |
| --- | --- | --- | --- |
| SELECT / INSERT / UPDATE / DELETE | All true | All true | All true |
| TRUNCATE / REFERENCES / TRIGGER / MAINTAIN | All false | All false | All false |
| `relrowsecurity` (RLS enabled) | true | true | true |

Supabase's security advisor returned **zero security lints**. Public table row estimates were zero when inspected; the migration did not modify user rows or policies. Verified the new version appears in Supabase's migration ledger.

## Important limitations and follow-ups

- A schema/privilege audit is **not** a real 2-user cross-account access test. Test authenticated owner/non-owner reads and writes, anonymous sign-in denial, token expiry, account switching, and backend session verification before release.
- New future tables can inherit insecure default grants depending on migration origin. For each new `public` table, audit RLS, policies, `anon`/`authenticated` grants and any dangerous `TRUNCATE`/DDL privilege immediately.
- PostgreSQL `service_role`, `postgres`, Railway Postgres and Supabase role grants are distinct. Do not conflate them.
- Keep the release freeze. The legacy/production auth migration remains an independent QA and deployment gate.
