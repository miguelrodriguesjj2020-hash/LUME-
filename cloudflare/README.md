# LUME production backend — Cloudflare Workers + D1

This directory contains the production backend target for LUME 0.35.3, using Cloudflare Workers + D1 while preserving the current mobile API contract.

Security and Free-plan constraints addressed:
- users are stored in D1 (not a large environment variable);
- generated high-entropy passwords are verified with keyed HMAC (`hmac-sha256-pepper-v1`) using a Worker secret;
- plaintext credentials and catalog source IDs remain outside the public repository;
- Google Drive service-account credentials remain server-side;
- CBR/RAR remains rejected by the internal reader path.

The private activation bundle contains the D1 user seed, normalized production catalog, signing material and deployment instructions. Do not commit those private files.
