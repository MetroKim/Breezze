# Breezze — App Security, Caching and Production Checklist

**Purpose:** release-gate checklist for the Flutter app, NestJS API, PostgreSQL, Redis, Cloudflare edge and provider integrations.

**Status key**
- [x] Implemented in repository code/config inspected on 2026-11-21. This does not prove production deployment.
- [~] Partial: foundation exists, but controls, tests, operational configuration or evidence are missing.
- [ ] Not implemented or not verified.

**Selected architecture**
- Identity: **Breezze-owned NestJS auth (current implementation)**; evaluate managed OIDC before enterprise SSO. No third-party IdP integration is claimed.
- Protocol: **15-minute JWT bearer access token** for the current mobile API; OIDC/PKCE required if browser/social SSO is introduced.
- Password hashing: **Argon2id, 19 MiB, 2 iterations, parallelism 1** baseline; benchmark and tune upward on production hardware.
- Database: **PostgreSQL + Prisma**.
- Cache/coordination: **Redis**; global API IP rate limits now use atomic shared Redis counters across API replicas.
- Edge/CDN/WAF: **Cloudflare**.
- Media storage: **Cloudflare R2**, only for Breezze-owned or rights-cleared media.
- Mobile token storage: **iOS Keychain / Android Keystore** via Flutter secure storage; access tokens remain memory-only.
- Logging: **request IDs and structured logging foundation**; centralized immutable audit storage and alerting remain.

> A checked code item is not proof of a secure production deployment. Cloudflare rules, TLS, secret-manager values, private networking, backups, restore drills and app-store signing must be verified in actual environments.

## 1. Authentication
- [~] Identity provider: custom NestJS auth exists; federate with a mature OIDC provider before enterprise SSO/high-risk launch.
- [~] Protocol: JWT bearer access tokens; key rotation, key IDs and multi-key verification are not implemented.
- [x] Access-token lifetime: 15 minutes.
- [x] Refresh-token rotation: consumed token row is revoked and a new token is created in the same family.
- [x] Refresh-token storage: SHA-256 hashes are stored; migration hashes existing values in place.
- [~] Refresh-token reuse: replay of a revoked token can revoke its family; unit regression tests cover replay and concurrent rotation, but DB-backed integration tests remain.
- [~] Administrator MFA: TOTP is enforced for admin routes, secrets are AES-256-GCM encrypted, accepted time-steps are replay-protected, and ten one-time recovery codes are stored as hashes. Password + fresh TOTP/recovery-code step-up can rotate the full recovery set; the action is audited and Redis-rate-limited. Passkeys/WebAuthn, secure reset and delegated recovery controls remain.
- [~] Login protection: atomic Redis-backed per-IP quota plus hashed per-account-and-source-IP login quota are shared across API replicas; progressive backoff and CAPTCHA escalation remain.
- [ ] Account recovery: single-use expiring links and generic responses that do not reveal whether an email exists.
- [ ] Email verification: signed one-time verification before sensitive actions.
- [ ] Social login: Google/Apple/GitHub OIDC and verified-email claim validation.
- [ ] JWT key rotation: key ring with overlap window, key ID, emergency revocation and documented procedure.

## 2. Passwords and sessions
- [x] Argon2id with explicit baseline parameters: 19 MiB, 2 iterations, parallelism 1.
- [x] Registration password minimum 12 characters, maximum 128.
- [~] Long passphrases accepted up to 128 characters; verify UI does not trim or normalize passwords.
- [ ] Breached-password checks using HIBP k-anonymity or equivalent.
- [ ] Password change: current-password re-authentication, session-family revocation and notification.
- [x] Access JWTs carry a session-family identifier; JWT validation requires an unrevoked, unexpired refresh-token family, so revoking that family invalidates its access JWTs on the next API request.
- [~] Rollout note: access JWTs issued before the `sid` claim change are rejected; force clients to refresh/re-authenticate during deployment and verify mobile refresh handling.
- [ ] Browser cookies: HttpOnly, Secure, SameSite and __Host- prefix if a browser session frontend is added.
- [ ] CSRF tokens for cookie-authenticated state-changing browser requests.
- [x] Mobile access token is memory-only; refresh token is persisted through OS secure storage (Keychain/Keystore).
- [~] Logout attempts server revocation of the complete session family and clears OS secure storage; logout-all-devices and revoke-all endpoint remain. Access JWT revocation is enforced on the next authenticated API request.

## 3. Authorization
- [~] Deny by default: guards exist on parts of API; audit every controller and route.
- [~] Server-side permission checks exist in selected services; require a route-by-route authorization matrix and tests.
- [~] Object-level/IDOR checks: playlist, favorites, media uploads, distributor submissions and artist analytics have account-scoped regression tests; push-token registration rejects cross-account reassignment and handles unique-insert races; artist claims now have database uniqueness and idempotent retry handling. PostgreSQL-backed concurrent artist-claim constraint tests now run in CI; broader endpoint-level concurrency tests and adversarial tests for every resource ID remain.
- [~] Persisted admin RBAC now protects admin and moderation-review routes; distributor release validation is transactionally audited. Full resource-level RBAC and ABAC for territory/rights/resource context remain.
- [ ] PostgreSQL RLS or equivalent tenant isolation; current schema is user-scoped, not a complete tenant/RLS implementation.
- [x] Artist claim uniqueness: one claim per account/artist plus a partial unique index allowing only one approved claimant per artist. CI applies migrations to PostgreSQL and runs concurrent insert tests for both constraints. Before applying the migration to an existing database, check for duplicate `(userId, artistId)` pairs and multiple approved claims per artist and reconcile them; the migration intentionally fails rather than deleting claim records.
- [~] Admin routes require persisted admin role; separate hostname/network boundary, MFA, privileged audit trail and just-in-time access remain.
- [x] Media upload completion is retry-safe after queue insertion/network failures: owner-scoped state checks plus deterministic BullMQ job IDs prevent duplicate pipeline work. Terminal failed jobs can now be retried by their owner; retry removes a retained failed BullMQ job before reusing its deterministic ID and restores the DB state if enqueue fails.
- [~] Least privilege: separate DB users and service identities; deployment examples still use shared development credentials.
- [~] Account deletion now requires password reauthentication; email change, artist ownership transfer and other sensitive-action reauthentication remain.

## 4. Input, output and common attacks
- [x] SQL injection: Prisma parameterized query APIs are the persistence standard.
- [x] Global NestJS ValidationPipe: whitelist, forbidNonWhitelisted and transform.
- [~] Audit every endpoint for type, length, format, enum, nested DTO and response validation.
- [~] Helmet is enabled; strict production CSP and rich-text sanitization remain.
- [ ] CSRF protection if browser cookies are used.
- [~] Media jobs are quarantined and R2 is intended for owned/cleared media; add byte-level MIME sniffing, size quotas, random keys, malware scan and separate serving origin.
- [ ] SSRF: outbound host allowlists, block loopback/private/link-local/metadata IPs and revalidate redirects.
- [ ] Path traversal: canonicalize paths and verify they remain under fixed storage roots; add adversarial tests.
- [x] Code-review rule: never pass user-controlled values to shell commands; use library APIs.
- [~] DTO whitelist helps mass-assignment defense; ensure clients cannot set owner IDs, roles or internal status fields.
- [ ] Open redirects: relative destinations or strict host allowlist.
- [x] JSON + DTO validation; never deserialize untrusted payloads into executable/object types.
- [ ] CSV export escaping for cells beginning with =, +, - or @ if exports are introduced.
- [~] Helmet defaults provide framing protection; verify explicit CSP frame-ancestors for any web UI.

## 5. Transport and security headers
- [~] HTTPS is required for production API origin; Worker rejects non-HTTPS origin except localhost. Verify origin TLS/cert automation.
- [ ] TLS 1.3 (TLS 1.2 minimum) at Cloudflare and origin.
- [ ] HTTP-to-HTTPS redirects at edge and origin.
- [ ] HSTS max-age 31536000 + includeSubDomains only after all subdomains are HTTPS-ready.
- [~] Helmet enabled; strict production CSP not yet configured.
- [x] X-Content-Type-Options via Helmet defaults.
- [~] Referrer-Policy via Helmet defaults; verify strict-origin-when-cross-origin.
- [ ] Explicit Permissions-Policy denying camera, mic and geolocation unless required.
- [x] CORS uses explicit allowlist; production default is empty and arbitrary origins are not reflected.
- [ ] External production header audit using securityheaders.com or equivalent.

## 6. Secrets and keys
- [x] .env files ignored; placeholder .env.example files committed.
- [~] Production secrets must live in Cloudflare/hosting secret manager; no live secret-manager deployment is verified.
- [ ] Gitleaks/TruffleHog in pre-commit and CI; scan full Git history.
- [ ] Separate dev/staging/prod credentials.
- [ ] Scheduled and incident-triggered secret rotation.
- [~] Edge shared secret exists as a design; scope and rotate R2/provider credentials.
- [x] No provider API secret is intended to ship in Flutter; treat all client-embedded values as public.
- [ ] Rotate any credential previously pasted into chat, issue, commit, build log or client bundle. Never reuse it.

## 7. Data protection
- [ ] Verify managed PostgreSQL, Redis, R2 and backups use provider encryption/KMS.
- [ ] Classify PII and use envelope/field encryption where required.
- [~] Enforce TLS for PostgreSQL, Redis and service-to-service links in production.
- [ ] Data minimization and deletion policy per feature.
- [ ] Per-table retention policy and account-deletion workflow.
- [~] Request IDs and structured HTTP logging foundations; add redaction tests for passwords, bearer/refresh tokens, emails and PII.
- [ ] Never copy raw production data into development; use anonymized fixtures.
- [x] Breezze currently has no payment/card feature. If payments are added, use hosted checkout and never store card numbers.

## 8. API security
- [~] Atomic Redis quotas are shared across API replicas: global per-IP plus a separate per-account-and-source-IP login bucket; per-user/per-key quotas and endpoint-specific policies remain.
- [~] Cloudflare WAF/rate rules are documented but production thresholds/rules must be configured and verified.
- [~] Set explicit request body limits and request/upstream timeouts per route.
- [~] Bounded pagination is a route-by-route task; cap every list endpoint.
- [ ] Idempotency keys for retried writes, upload completion and future payment-like actions.
- [~] Request DTO validation is global; response validation/OpenAPI contract tests are incomplete.
- [~] Generic provider errors exist; audit exception filters for stack traces/internal messages.
- [ ] If API keys are introduced: hash, show once, scope, expire and revoke.
- [ ] Webhooks: signatures, timestamp window, replay store and idempotent processing.
- [ ] GraphQL is not current API surface; if introduced, depth/complexity limits and production introspection policy.
- [x] API versioned under /api/v1; publish deprecation policy.

## 9. Infrastructure security
- [~] Cloudflare Worker and edge cache code exist; live WAF, bot rules and DDoS settings need configuration.
- [ ] PostgreSQL, Redis and sidecars private; no public DB/Redis ports in production.
- [ ] SSH keys only; SSM/bastion/VPN/Tailscale; no open admin ports.
- [ ] Per-service IAM roles, MFA on cloud console, no shared human accounts.
- [~] ytmusicapi container runs non-root; harden API/worker images, read-only filesystem and dropped capabilities.
- [ ] Automated base-image rebuilds and dependency updates.
- [ ] Deny inbound by default; expose only required HTTPS endpoints.
- [~] API Worker is code-ready but not deployed; verify private origin ingress and edge secret before launch.

## 10. Dependencies and supply chain
- [~] Inspect/commit lockfiles for every Node/Python/Flutter workspace; some CI workspaces use npm install rather than npm ci.
- [ ] Dependabot/Renovate for all package ecosystems and Docker images.
- [~] CI reports npm audit summaries but does not fail on defined severity threshold; add OSV/Trivy and Python/Dart scanning.
- [ ] Review maintainers, release cadence, transitive dependencies and install scripts for new packages.
- [ ] Enforce 2FA on GitHub, npm, PyPI and cloud accounts.
- [ ] Main branch rulesets: required checks/reviews; verify in GitHub settings.
- [ ] Pin third-party GitHub Actions to immutable commit SHAs and scope CI permissions/secrets.
- [ ] Generate CycloneDX or SPDX SBOM for every release.

## 11. Logging, audit and detection
- [~] API generates request IDs and returns X-Request-Id.
- [~] pino-http dependency exists; verify JSON output and redaction of sensitive headers/body.
- [~] Admin role changes, takedown resolutions, moderation report decisions and administrator MFA enrollment/verification/recovery-code rotation now write actor/action/target/time/metadata audit events in the same database transaction; authenticated admins can inspect the newest 100 events. Login changes, exports and deletions still need coverage.
- [~] PostgreSQL migration installs a trigger that rejects UPDATE/DELETE on audit rows for ordinary runtime credentials; database owners/superusers can still disable triggers. Keep schema-owner credentials out of the API runtime and ship events to centralized tamper-resistant write-once storage.
- [ ] Alerts for login spikes, 401/403 anomalies, unusual downloads, new admins, provider failures and cache-origin surges.
- [ ] Legal retention/deletion schedule.
- [ ] Incident runbook: severity, contacts, containment, credential rotation, evidence preservation and postmortem.

## 12. Mobile-specific
- [x] Refresh tokens use flutter_secure_storage backed by iOS Keychain / Android Keystore; never put refresh tokens in preferences or SQLite.
- [x] No provider secrets in app bundle by design; use backend proxy.
- [ ] Certificate pinning only with backup pin and tested emergency rotation plan.
- [ ] Play Integrity and Apple App Attest verification for sensitive endpoints.
- [ ] Encrypt Drift/SQLite local DB if it stores sensitive user data.
- [ ] R8/ProGuard and iOS release hardening; disable debug endpoints/logging.
- [~] Validate all deep-link scheme, host, path and parameters before action.
- [ ] Prevent screenshots/app-switcher previews on privacy-sensitive screens.
- [ ] Dev/staging/prod build flavors and signing configurations.
- [x] Server validates requests; Flutter is not an authorization boundary.

## 13. AI features
Breezze currently has no user-facing LLM feature. These are mandatory gates before one is introduced:
- [ ] Per-user quotas, global spend cap, hard stop and alerts.
- [ ] Strict AI endpoint rate limits.
- [ ] Provider keys only on backend.
- [ ] Prompt injection defense: retrieved/user text is untrusted and separated from instructions.
- [ ] Output schema validation/sanitization; never eval/exec model output.
- [ ] Generated code sandboxed without network or secrets.
- [ ] Tool allowlists, least privilege and human approval for destructive actions.
- [ ] PII redaction and provider retention review.
- [ ] Timeouts, bounded retries, circuit breaker and approved fallback provider.
- [ ] Streaming and safe prompt caching where privacy permits.
- [ ] Moderation policy and input/output filtering as appropriate.

## 14. Caching
- [~] Hashed static assets should use one-year immutable cache headers; verify web hosting/build output.
- [x] Cloudflare API Worker caches only explicit public catalog GET routes with no auth/cookie/query parameters.
- [x] Private API responses bypass cache and receive private, no-store.
- [x] Current edge key includes URL, country and Accept-Language.
- [~] TTLs: edge catalog 90 seconds + 30-second stale window; Redis provider search 60 seconds and track metadata 15 minutes.
- [~] Redis provider cache-aside exists; audit DB-backed reads and write invalidation.
- [~] Per-process in-flight provider dedupe exists; distributed Redis lock/stale-while-revalidate for all hot keys remains.
- [ ] TTL jitter to avoid synchronized expiry.
- [ ] Brief negative caching for stable not-found responses where safe.
- [~] Provider search key includes normalized query hash; add locale/territory/catalog version if output varies by them.
- [x] Authenticated/user data, cookies and authorization requests are not shared-CDN cached.
- [x] Worker only caches status 200; errors are not cached.
- [~] Explicit route allowlist reduces poisoning risk; add adversarial cache-key tests.
- [ ] Cache hit/miss/bypass, origin latency, stale served, Redis memory/eviction metrics and alerts.
- [ ] Separate pure-cache Redis (maxmemory + allkeys-lru) from durable queues/locks/sessions (noeviction + persistence).
- [ ] Redis TLS, ACL/password, private network and no public exposure.
- [ ] Add replicas/cluster only after measured need.

## 15. Database
- [~] Prisma schema has unique/foreign-key relations; audit common filters and verify with EXPLAIN ANALYZE.
- [ ] Profile and fix N+1 queries.
- [ ] PgBouncer/managed pooler and explicit global connection budget.
- [x] Prisma schema defines unique constraints and relations; add domain CHECK constraints where required.
- [x] A generated initial schema baseline now provisions fresh PostgreSQL databases; later migrations are baseline-safe. CI applies the complete migration history to PostgreSQL 16. Existing pre-baseline databases must be schema-diffed and have the baseline marked applied only after equivalence is confirmed (see `backend/api/prisma/README.md`).
- [ ] Daily backups + PITR + 3-2-1 offsite policy.
- [ ] Monthly isolated restore drill with recorded result.
- [ ] Define and test RPO/RTO.
- [ ] Enable slow query log and weekly review.
- [ ] Read replicas/partitioning only when measured scale justifies them.
- [ ] Runtime DB role cannot own/drop schema; use separate migration role.
- [~] Soft delete where recovery/audit needs it; hard-delete personal data where required.

## 16. Performance
- [~] Bound payloads, paginate and avoid over-fetching; cursor pagination remains route-by-route.
- [ ] Brotli/gzip compression at edge/origin; verify content types.
- [~] Artwork URLs exist; standardize WebP/AVIF and lazy loading within source terms.
- [ ] Code splitting/tree shaking/bundle budgets; measure Flutter web separately if deployed.
- [~] Cloudflare supports modern HTTP; verify origin keep-alive and protocol settings.
- [~] BullMQ/worker process exists; ensure slow work is off request path with bounded concurrency and dead-letter handling.
- [ ] SSE/WebSockets only where needed; enforce auth and connection limits.
- [ ] Web LCP <2.5s, INP <200ms, CLS <0.1; add Lighthouse and real-user monitoring.
- [~] Reuse Prisma and HTTP clients; define DB and outbound HTTP pool budgets.
- [~] Drift/outbox/offline download foundations exist; add bounded retries, conflict policy and connectivity tests.

## 17. Reliability
- [~] Sidecar healthcheck exists; add API liveness and dependency-aware readiness endpoints.
- [x] ytmusicapi adapter has bounded search/metadata timeouts; audit every provider, DB and outbound call.
- [~] Exponential backoff + jitter only for idempotent calls; central retry budget and tests remain.
- [x] ytmusicapi sidecar limits each container to 8 concurrent upstream requests; excess receives 503/Retry-After.
- [x] Identical provider metadata misses coalesce per API process.
- [x] Provider circuit breaker opens after 5 retryable failures for 30 seconds with one half-open probe per process.
- [ ] Distributed provider budgets/breaker across replicas; current controls are process/container local.
- [~] BullMQ retry caps and deterministic idempotency are configured for media jobs; owner-scoped retry of terminal failures is implemented. A formal dead-letter queue, operational replay tooling and alerting remain.
- [ ] Graceful shutdown: drain work and close Prisma/Redis/HTTP clients.
- [ ] k6/Locust load tests for realistic mix, hot keys, cache-miss storms, provider failures and regional traffic.
- [ ] No one-million-concurrent-user claim until repeatable load tests, saturation metrics and cost model are approved.
- [ ] Define availability/latency/error/recovery SLOs and burn-rate alerts.

## Release gate — all required before production-ready
- [ ] Latest CI green on exact release commit: Flutter, API typecheck/tests/build, Prisma validation and both Cloudflare Workers.
- [ ] Refresh-token migration tested on fresh/existing DB; replay/concurrent-refresh tests pass.
- [ ] Mobile refresh token stored only in OS secure storage; logout and revoke-all work.
- [~] Shared Redis IP and per-account-and-source-IP login rate limits are implemented and unit-tested; progressive backoff, CAPTCHA escalation and production Redis failure drills remain.
- [~] Playlist and favorites ownership tests exist; complete ownership/role tests for every protected endpoint before release.
- [ ] Secret scan passes current tree and Git history; exposed credentials rotated.
- [ ] Production Cloudflare WAF/rate rules, TLS/HSTS/CSP/CORS and private-origin restrictions verified.
- [ ] DB/Redis private, encrypted, least-privilege and backed up; restore drill passes.
- [ ] Central redacted logs, audit events, alerts and incident runbook operational.
- [ ] Load tests meet SLOs; one-million concurrency is demonstrated with measured workload and cost.

## Implementation map
- Cloudflare API Worker: infra/cloudflare/api-worker/
- Cloudflare guidance: infra/cloudflare/README.md
- API bootstrap: backend/api/src/main.ts
- Distributed rate limiter: backend/api/src/cloudflare-aware-throttler.guard.ts and backend/api/src/cloudflare-aware-throttler.guard.spec.ts
- Auth: backend/api/src/auth/
- Refresh-token schema/migration: backend/api/prisma/
- Provider resilience: backend/api/src/providers/ytmusic.adapter.ts and backend/ytmusicapi/main.py
- Mobile session: apps/mobile/lib/core/auth/auth_session.dart
- CI: .github/workflows/breezze-quality.yml

This checklist intentionally leaves operational controls unchecked until evidence exists in the real environment.


## 15. Persisted administrator roles (added 2026-11-21)
- [x] Persist a `role` column on users, defaulting to `user`; apply migration `20261121203000_user_roles` before deploying this code.
- [x] Admin dashboard, takedown and role-management routes require both JWT authentication and the persisted `admin` role.
- [x] Moderation report listing and resolution require the admin role; authenticated users may still file reports.
- [x] Role assignment updates the database instead of returning a success-shaped placeholder.
- [x] Unit tests cover admin guard allow/deny behavior and persisted role assignment.
- [ ] Bootstrap the first administrator out-of-band after verifying the account owner. Example (run against the production DB through an approved secure SQL session, replacing the address):

```sql
UPDATE "User" SET "role" = 'admin' WHERE "email" = 'verified-admin@example.com';
```

- [x] Require TOTP MFA for every administrator before protected admin routes are accessible; setup and verification are implemented.
- [ ] Add immutable audit events for role grants/revocations and all administrative actions.
- [ ] Add integration tests proving regular users receive HTTP 403 on every admin/moderation route.

**Important:** Do not expose a public bootstrap-admin endpoint. Keep the first promotion as a controlled database operation, verify the resulting admin account, then revoke the temporary DB access.


## 16. Push-token ownership isolation (added 2026-11-21)
- [x] Registering a device token already associated with a different account returns a conflict instead of silently transferring ownership.
- [x] Existing token owners update platform metadata with an owner-scoped conditional write; ownership is re-read and verified.
- [x] First registration uses create rather than upsert, preventing an upsert race from transferring token ownership.
- [x] Prisma unique-constraint race recovery re-reads the winning owner; a different owner receives a conflict, while the same owner may safely update metadata.
- [x] Unit tests cover cross-account rejection, owner-scoped updates, first registration and both outcomes of a simulated P2002 race.
- [~] Add a PostgreSQL-backed concurrency integration test with simultaneous requests; unit tests simulate the unique-constraint race but do not replace a real DB race test.


### Admin audit trail implementation note (2026-11-21)
- Prisma model: `AdminAuditEvent`; migrations: `20261121213000_admin_audit_events` and `20261121213500_admin_audit_append_only`.
- Role changes record the acting admin, target user, previous role and new role.
- Takedown resolutions record the acting admin, case ID and resulting status.
- Audit insertion and the associated state change share a Prisma transaction: if audit insertion fails, the administrative mutation rolls back.
- `GET /api/v1/admin/audit-events` is protected by the controller's JWT and persisted-admin guards and returns at most 100 newest events.
- A PostgreSQL trigger rejects UPDATE/DELETE against audit rows. This raises the bar for the runtime role but is not cryptographic immutability: DB owners/superusers can disable triggers. Use a separate schema-owner credential, tightly scoped API DB role, and external WORM retention.


### Moderation audit coverage (2026-11-21)
- Resolving a report records the authenticated moderator, report ID and `dismissed`/`actioned` decision in the same transaction as the status update.
- Missing/already-resolved reports do not produce audit events.
- Regression tests cover successful and unsuccessful resolution paths.


### Administrator TOTP MFA implementation (2026-11-21)
- TOTP uses RFC 6238 / HMAC-SHA1, six digits, 30-second periods and a ±1-step clock-skew window.
- TOTP secrets are encrypted at rest with AES-256-GCM using `MFA_ENCRYPTION_KEY` (32 random bytes, base64). Use one identical secret across API replicas via a secrets manager; never commit it.
- Admin login responses expose `mfaRequired`; admins without enrollment also receive `mfaSetupRequired`. MFA enrollment requires fresh password reauthentication at `POST /api/v1/auth/mfa/setup` before a provisioning secret/URI is issued, then `POST /api/v1/auth/mfa/setup/verify` with a six-digit code to complete enrollment. Enrolled admins use `POST /api/v1/auth/mfa/verify` after password login.
- MFA setup and verification responses are marked `Cache-Control: private, no-store`.
- Enrolled users call `POST /api/v1/auth/mfa/verify` after password login. The endpoint upgrades only the current refresh-token family and returns an MFA-verified access token.
- Refresh-token records persist the MFA-verified state; refresh preserves it. AdminGuard rejects admin requests unless the access token carries the verified claim.
- MFA verification endpoints have a stricter Redis-backed per-source limit (default five attempts per 15 minutes); tune via `MFA_ATTEMPT_RATE_LIMIT` and `MFA_ATTEMPT_RATE_WINDOW_MS`.
- Accepted TOTP counters are stored atomically per account to prevent replay of a previously accepted time-step.
- Ten one-time recovery codes are issued once at enrollment; only SHA-256 hashes are persisted, and successful use atomically consumes the code. Admin audit events record whether TOTP or a recovery code was used.
- `POST /api/v1/auth/mfa/recovery-codes/regenerate` requires the current password, a fresh TOTP or unused recovery code, and an active MFA-verified session. It atomically consumes the step-up factor, invalidates all previous recovery codes, creates ten replacement hashes and writes an audit event. The replacement plaintext codes are returned once and must be stored offline.
- Production API startup refuses to run without a valid 32-byte base64 MFA encryption key.
- Configure `MFA_ENCRYPTION_KEY` before enabling MFA. Rotate it only through a planned re-encryption migration; changing it directly makes stored secrets undecryptable.
- Administrator MFA enrollment, successful verification and recovery-code regeneration are added to the privileged audit trail. Ten one-time recovery codes are generated at enrollment or regeneration, stored only as SHA-256 hashes and returned once. Secure MFA reset, backup factor enrollment, email/security notifications and delegated admin recovery procedures remain mandatory before broad production rollout.
