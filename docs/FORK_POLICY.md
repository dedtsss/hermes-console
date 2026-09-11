# dedtsss Hermes Console fork policy

This repository is a user-owned fork of `xP3ta/hermes-console` used by TestLab for a Russian-localized Android build and narrowly scoped compatibility fixes.

## Upstream

- Canonical upstream: `xP3ta/hermes-console`.
- Fork baseline when created: upstream `main` at `a2af8bc6115f96a84138028465d8f71c3ef6d308`.
- Preserve upstream history and keep changes small enough to rebase/sync deliberately.

## Fork invariants

- The fork remains an operator client for stock Hermes Agent. Do not turn it into a second lifecycle owner or a separate Hermes runtime.
- Russian localization is the primary fork delta. Existing English and Spanish behavior must remain intact.
- The customized Android build must be able to coexist with the official Hermes Console installation on one device; use a distinct Android application ID for the fork build while preserving required deep-link/pairing behavior.
- Do not weaken the upstream privacy, secret-storage, transport, release-channel, or signing boundaries documented in `AGENTS.md`, `docs/SECURITY_POLICY.md`, and `docs/RELEASE_DISTRIBUTION.md`.
- Never commit real Gateway, Bridge, Dashboard, Cloudflare, SSH, signing, or account credentials. Test fixtures use synthetic values only.
- Do not publish changes, issues, pull requests, comments, releases, or other mutations to the upstream repository without explicit owner approval. Work stays in this fork unless the owner separately approves an upstream contribution.

## Build and validation

Use the repository's existing Flutter/Android CI as the authoritative build/test environment. Local worker hosts should prefer source changes and lightweight checks; Android SDK/Gradle build evidence belongs in GitHub Actions unless a task explicitly says otherwise.
