# LUME Cloudflare backend — production reconciliation

This backend reconciles the original LUME CP10 Cloudflare/D1 architecture with the security and client-contract hardening reached by CP35 / Android build 38.

## Runtime contract
- D1 is authoritative for catalog, accounts, progress, idempotency and sync cursor events.
- `POST /v1/auth/login` issues an 8-hour HMAC-signed session understood by the current Flutter client.
- Bootstrap/media/progress/sync require authentication. Consumers can access only their profile; admins can access any profile and `POST /v1/admin/catalog`.
- Sync accepts the current Flutter `ops` field and the legacy `operations` field, returning the current `ack/events/rejected` envelope.
- Media descriptors return a 5-minute Worker-signed download URL. The Worker streams edition bytes from Google Drive through a service-account `drive.readonly` token while preserving Range/If-Range semantics.
- Password verification uses an HMAC-SHA256 verifier keyed by the Worker-only `PASSWORD_PEPPER`. Provisioned passwords should be high entropy; the included helper generates a 144-bit random password by default. This avoids a CPU-heavy password KDF inside the 10 ms Workers Free request CPU budget.

## Production secrets
Never commit these values. Set them with `wrangler secret put`:
- `AUTH_SECRET` — 32+ random characters
- `MEDIA_SIGNING_SECRET` — 32+ random characters
- `PASSWORD_PEPPER` — 32+ random characters
- `GOOGLE_SERVICE_ACCOUNT_JSON` — service account JSON; share the media Drive folder/files with its `client_email`

## First deploy
1. `npm install`
2. `npm test`
3. `npx wrangler d1 create lume`
4. Put the returned D1 ID in `wrangler.toml` in place of `REPLACE_WITH_D1_DATABASE_ID`.
5. `npx wrangler d1 migrations apply lume --remote`
6. Add the four production secrets.
7. Provision the admin with `LUME_PASSWORD_PEPPER=... node tool/create_account.mjs <username> admin`; execute the emitted SQL against the remote D1. Do not persist the generated password in source control.
8. `npx wrangler deploy`
9. Set GitHub Actions secret `LUME_API_BASE` to the deployed HTTPS Worker URL, then configure the Android production-signing secrets and generate the distribution APK.

The recovered checkpoints do not show a physical CP10 production D1 deployment, so this branch treats D1 as a fresh production database. If an external CP10 database exists, migrate it explicitly instead of replaying the fresh schema over it.
