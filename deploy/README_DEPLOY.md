# LUME backend 0.36.0 — production deploy

This package runs the durable LUME backend used by the Android release candidate.

## Required production properties
- Node 24.
- Persistent volume mounted so `LUME_DB_PATH` survives restarts.
- HTTPS terminated by the hosting platform/reverse proxy.
- `LUME_AUTH_SECRET` and `LUME_MEDIA_SECRET` are independent random secrets of at least 32 characters.
- `LUME_USERS_JSON` contains scrypt password records. Generate one record with `LUME_NEW_PASSWORD='...' node backend/make_user.js <username> <admin|consumer> <profileId>`.
- Media URLs registered in production must use HTTPS.

## Initial catalog and media
Mount a seed JSON and set `LUME_SEED_FILE`. With `LUME_REQUIRE_SEED=1`, startup fails closed if the seed is missing. The seed is idempotent at the catalog revision and media entries are upserted. Set `LUME_SEED_PRUNE_MEDIA=1` to remove stale media registrations not present in the seed.

The sample seed demonstrates the schema only. Replace the media URL with the real production media-provider URL before deployment.

## Admin interface
After deployment, open `/admin` on the same HTTPS origin. It supports admin login, loading the current catalog, adding/editing/removing works and editions, publishing a new catalog revision, and registering/removing media descriptors. No credential is embedded in the page.

## Readiness
- `GET /v1/health`: process liveness.
- `GET /v1/ready`: production configuration + durable SQLite readiness.
- Run `npm run verify-db` for SQLite quick-check/integrity verification.

## Release coupling
The Android production build must receive this public HTTPS origin through the `LUME_API_BASE` GitHub Actions secret. Do not distribute an APK that the Android audit classifies as `qa-only-not-for-distribution`.
