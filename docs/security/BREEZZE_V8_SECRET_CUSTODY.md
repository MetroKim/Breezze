# Breezze V8 — API Key Custody and Migration Record

**Checked 2026-11-26.** This is a *names-only* inventory. Never commit, paste, print, or attach real key material to this file.

## Verified account infrastructure
- **Supabase:** Breezze project `djwvyjtebmsavhcrmhxf`, PostgreSQL 17, active/healthy. `supabase_vault` extension **0.3.2 installed**, and `vault.secrets` currently contains **zero records**. **No original API keys have been migrated to Vault.**
- **Railway:** Breezze project has a production environment and **Breezze API**, **Breezze Catalog Metadata**, **Redis**, and **Postgres** services. Keep their runtime credentials in Railway variables; do not export values through app logs or repository commits.
- **GitHub:** checked tracked filenames in `main`. No native credential/signing files were tracked under the common `google-services.json`, `GoogleService-Info.plist`, `.keystore`, `.jks`, `*.pem`, or `key.properties` names. This is **not** a full-content or history scan, and old leaks still require rotation.
- **Cloudflare:** existing Workers and R2 may have worker-specific token bindings; verify variable *names* in the Cloudflare dashboard, not secret values in Git.

## Runtime deployment and storage choices

| Secret type | Runtime source of truth | Backup / DB storage | Exposed to Flutter? |
|---|---|---|---|
| Supabase publishable key and URL | Flutter build config (public) | Not required | **Yes** — publishable key only |
| Supabase service_role/secret key | Railway or Cloudflare encrypted server configuration | Supabase Vault only if DB actually uses it | **Never** |
| `DATABASE_URL`, Redis passwords | Railway service references | Encrypted manager, do not duplicate by default | **Never** |
| `EDGE_SHARED_SECRET`, `MEDIA_SIGNING_KEY`, R2 access secrets | Cloudflare Worker secrets + Railway deploy vars as applicable | Supabase Vault if a dedicated server-side Vault integration is implemented | **Never** |
| Spotify client secret, Google OAuth client secret, Apple signing key | Provider console → secret manager | Restricted Vault record only where needed | **Never** |
| OAuth *public* client IDs | Public app config | Not required | Yes, if provider permits |
| Android signing keystore, iOS certificates/profiles | Restricted CI/environment secret storage | **Not** in app DB or source | Never |
| Users' refresh tokens | Platform secure store / Supabase Auth lifecycle | Native provider tables | Never in plain logs |

## Concrete key names to review (not secret values)
`JWT_SECRET`, `EDGE_SHARED_SECRET`, `MEDIA_SIGNING_KEY`, `MFA_ENCRYPTION_KEY`, `REDIS_URL`, `DATABASE_URL`, `R2_ACCOUNT_ID`, `R2_SECRET_ACCESS_KEY`, `YOUTUBE_DATA_API_KEY`, `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, and Google/Apple provider OAuth signing credentials.

Names originate from tracked sanitized `.env.example` templates; live service variable inventory must be confirmed separately. Some keys may legitimately be unused.

## Correct migration procedure
1. Identify the exact runtime consumers for each key. Deactivate/rotate any key leaked to historical Git commits; `.gitignore` does not remove previously tracked content.
2. Store originals using the **Railway/Cloudflare secret facilities** where the process consumes them. Verify safe startup without printing them.
3. For SQL-only secrets, use **Supabase Vault**, not `public` tables. Vault encrypts on disk, but privileged SQL can decrypt: grant no anonymous/authenticated read on `vault.decrypted_secrets` and never return it from a public SQL function.
4. If a database-backed settings inventory is needed, store only identifiers, owners, last-rotation dates and `vault_secret_id`. **Do not** store original values in a normal SQL column.
5. Validate every provider can initialize with a *server-only* secret, that missing keys fail cleanly, and that no secrets appear in CI artifacts, client binary, Git history or logs.
6. Do not silently relocate/rotate live credentials; verify production consumer and deployment parity first.
7. Run full secret-history scanning and security advisories before signing release builds.

## Outstanding key release gates
- [ ] Populate Vault with **actual selected SQL-use secrets** via restricted operator flow, only after confirming which keys are needed.
- [ ] Review Railway and Cloudflare variable-name inventory for drift; rotate old historical exposures.
- [ ] Scan **entire Git history** with a secret scanner; inspect results without publishing key values.
- [ ] Demonstrate successful runtime configuration after each key rotation.
- [ ] Confirm service_role and R2 credentials are absent from all shipped binaries.

**Current database status:** encrypted Vault exists, **empty**; no claim of migration completion.
