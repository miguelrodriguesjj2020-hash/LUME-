# LUME production backend — Cloudflare Workers + D1

This directory is the production backend target for LUME 0.35.3. It preserves the mobile `/v1` contract while replacing the development Node/SQLite process with Cloudflare Workers + D1.

## Implemented contract

- `POST /v1/auth/login` — D1 users, peppered HMAC password verifier, 8-hour HMAC session.
- `GET /v1/health` and `GET /v1/ready` — fail-closed readiness for D1/secrets/Drive.
- `GET /v1/bootstrap` — revisioned normalized catalog, `304` when unchanged.
- `POST /v1/admin/catalog` — admin-only full catalog publication with revision-reuse protection.
- `GET|PUT /v1/profiles/:profile/progress/:edition` — anti-regression progress.
- `POST /v1/profiles/:profile/sync` — idempotent op IDs, ack/reject/events/cursor.
- `GET /v1/media/:edition` — 5-minute signed media descriptor.
- `GET|HEAD /v1/media-bytes/:edition` — validates descriptor signature and proxies private Google Drive bytes, forwarding `Range`/`If-Range` for resumable downloads.

CBR remains catalog-compatible but deliberately unsupported by the Android reader.

## Required private bindings / secrets

D1 binding: `DB`.

Worker secrets/vars (never commit values):

- `AUTH_SECRET` — >=32 random characters.
- `MEDIA_SECRET` — >=32 random characters.
- `PASSWORD_PEPPER` — >=32 random characters.
- `GDRIVE_CLIENT_EMAIL` — Google service-account email with read access to the library.
- `GDRIVE_PRIVATE_KEY` — PKCS#8 service-account private key PEM.

The Android production build separately requires its release keystore secrets and `LUME_API_BASE=https://<worker-domain>`.

## Activation order

1. Create D1 and replace `REPLACE_WITH_D1_DATABASE_ID` in `wrangler.jsonc`.
2. Apply `migrations/0001_initial.sql` to D1.
3. Add Worker secrets listed above.
4. Insert private users into `users`. `password_mac` is HMAC-SHA256 over `lume-password-v1:<password>` keyed by `PASSWORD_PEPPER`.
5. Deploy the Worker and verify `/v1/health` then `/v1/ready` (ready must be HTTP 200).
6. Login as the private admin and publish the normalized production manifest via `/v1/admin/catalog`; this also materializes the `media` map from edition `sourceFileId`s.
7. Set GitHub `LUME_API_BASE` to the Worker HTTPS URL and production Android signing secrets.
8. Build and require `APK_CLASSIFICATION=production-signing-and-api-config-present` before distribution.

## Local contract checks

No runtime dependency is needed for the pure contract suite:

```sh
npm test
npm run check
```

Wrangler is only required for D1 migration/deployment.
