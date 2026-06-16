# Releasing

Releases are tagged from `main`. A tag produces a multi-arch Docker image on GHCR and a
draft GitHub release; the same image is what production runs and what self-hosters pull.

## Versioning rule

Plain semver (`vMAJOR.MINOR.PATCH`). The contract for self-hosters:

- **Patch / minor**: upgrading never requires more than pulling the new image and running
  `bin/rails db:prepare`.
- **Major**: may require manual steps — the release's *Upgrade notes* section says exactly
  what to do.

## Cutting a release

1. Make sure `main` is green and deployed to the dev environment.
2. Tag and push:

   ```sh
   git tag v0.4.0
   git push origin v0.4.0
   ```

3. The `Release` workflow builds and pushes `ghcr.io/firefightlabs/firefight`
   (`v0.4.0`, `0.4`, `latest`; linux/amd64 + arm64) and drafts a GitHub release with
   auto-generated notes. PRs labeled `migration` are grouped under **Schema migrations**
   (the label is applied automatically to PRs touching `db/migrate/`, `db/*_schema.rb`,
   or engine migrations).
4. Edit the draft: fill in the **Upgrade notes** section — new required env vars
   (keep `.env.example` in sync), breaking changes, manual steps. Most releases need only
   the default "run `bin/rails db:prepare`" line.
5. Publish the release.
6. Promote the release in the Northflank pipeline to production.

## Upgrade notes checklist

- [ ] Schema migrations included? (`db:prepare` line stays; call out anything long-running)
- [ ] New or changed env vars? (list them; update `.env.example` in the same release)
- [ ] Anything removed/renamed a self-hoster might depend on (API fields, env vars, routes)?
