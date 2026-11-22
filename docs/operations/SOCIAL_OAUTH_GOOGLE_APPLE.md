# Breezze Google / Apple OAuth

## Security model

The Flutter UI uses the same Breezze sessions as email sign-in, with system-browser OAuth. The backend owns the Google/Apple client credentials and validates authorization codes and provider-signed identity tokens. Browser callbacks contain no Breezze access or refresh token. A single-use app-only pairing secret is SHA-256-hashed in PostgreSQL; a completed session is AES-256-GCM encrypted at rest with a key derived from the production JWT_SECRET. Expiring flow state, OIDC nonce, Google's S256 PKCE, and immutable issuer/subject checks prevent several common account and OAuth substitution attacks.

Existing email/password accounts are never silently linked to a social identity by matching an email. Matching existing email results in SOCIAL_ACCOUNT_LINK_REQUIRED. Admin MFA remains required.

## API endpoints

- GET /api/v1/auth/social/providers: whether either provider is configured
- POST /api/v1/auth/social/google/start and /apple/start: returns id, app-only secret, authorizationUrl and expiry
- GET /api/v1/auth/social/callback/google: provider browser callback, status page only
- POST /api/v1/auth/social/callback/apple: Apple form_post callback, status page only
- POST /api/v1/auth/social/poll: id and secret -> pending, failed, or single-use completed first-party session

## Railway provider configuration

On the EXISTING Breezze API Railway service, configure only through encrypted variables:

Google: GOOGLE_OAUTH_CLIENT_ID; GOOGLE_OAUTH_CLIENT_SECRET; GOOGLE_OAUTH_REDIRECT_URI.

Apple: APPLE_SERVICE_ID; APPLE_TEAM_ID; APPLE_KEY_ID; APPLE_PRIVATE_KEY; APPLE_OAUTH_REDIRECT_URI.

Each HTTPS redirect must be registered verbatim with its provider and end with /api/v1/auth/social/callback/google or /apple. A first-party verified domain routed through the Cloudflare API edge is recommended. Google requires registered OAuth client credentials and consent configuration. Apple requires an Apple developer account, Services ID, Sign in with Apple enabled, and verified domain/return URL. The app does NOT obtain these automatically. An example.com callback or a random unverified domain will not work.

With none of these values configured, both sign-in buttons are intentionally disabled rather than pretending to succeed. Existing email/password and MFA continue working. Do not embed secrets in source or Flutter defines.

## OS support and validation

The shared Flutter UI and url_launcher system-browser pairing approach supports Android, iOS, macOS, Windows, Linux and the web in architecture. Real browser sessions and provider callbacks must be verified per platform. Web browsers may block popup launch following an asynchronous API request; a same-tab return-state fallback will be required for any browser that does. Platform sign-in and native OS media controls are separate concerns.

Still required for a production PASS: provider credentials, real Google/Apple code exchange on each target, Apple private relay flows, consent-denied/cancel handling, account-linking design, administrative MFA checks, one-time token and account-switch tests, popup-blocker handling, expired-flow cleanup, accessibility, signing and store privacy review.

Editable Figma: https://www.figma.com/design/50wWGo2FObDEtnMY60cz60
