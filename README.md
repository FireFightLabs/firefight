# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Active Storage (Cloudflare R2)

Set these environment variables to archive incident files to R2:

- `ACTIVE_STORAGE_SERVICE=r2`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_ENDPOINT` (for example `https://<account-id>.r2.cloudflarestorage.com`)
- `R2_BUCKET`
- `R2_REGION` (use `auto` for R2)
- `R2_REQUEST_CHECKSUM_CALCULATION` (recommended: `when_required`)
- `R2_RESPONSE_CHECKSUM_VALIDATION` (recommended: `when_required`)
