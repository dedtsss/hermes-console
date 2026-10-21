# dedtsss Hermes Console fork policy

This repository is a user-owned fork of `xP3ta/hermes-console` used by TestLab for a Russian-localized Android build and narrowly scoped compatibility fixes.

## Upstream

- Canonical upstream: `xP3ta/hermes-console`.
- Original fork baseline when created: upstream `main` at `a2af8bc6115f96a84138028465d8f71c3ef6d308`.
- Current stable baseline: `v1.3.0` (`1.3.0+9630`), commit `7c51c99b3d665affda79742ca501aa04dad9d42f`.
- Preserve upstream history. Sync published stable tags only using the explicit local overlay, never unreleased main.
- Procedure and translation handoff: [STABLE_UPSTREAM_SYNC.md](STABLE_UPSTREAM_SYNC.md).
- Stable baseline pin: `tool/fork/upstream.json`; overlay classification: `tool/fork/overlay.json`.

## Fork invariants

- The fork remains an operator client for stock Hermes Agent. Do not turn it into a second lifecycle owner or a separate Hermes runtime.
- Russian localization is the primary fork delta. Existing English and Spanish behavior must remain intact.
- The customized Android build must be able to coexist with the official Hermes Console installation on one device; use a distinct Android application ID for the fork build while preserving required deep-link/pairing behavior.
- Do not weaken the upstream privacy, secret-storage, transport, release-channel, or signing boundaries documented in `AGENTS.md`, `docs/SECURITY_POLICY.md`, and `docs/RELEASE_DISTRIBUTION.md`.
- Never commit real Gateway, Bridge, Dashboard, Cloudflare, SSH, signing, or account credentials. Test fixtures use synthetic values only.
- Do not publish changes, issues, pull requests, comments, releases, or other mutations to the upstream repository without explicit owner approval. Work stays in this fork unless the owner separately approves an upstream contribution.

## Build and validation

Use the repository's existing Flutter/Android CI as the authoritative build/test environment. Local worker hosts should prefer source changes and lightweight checks; Android SDK/Gradle build evidence belongs in GitHub Actions unless a task explicitly says otherwise.

## Durable RU identity and translation gate

- Established package: `io.github.dedtsss.hermesconsole`; label: `Hermes Console RU`; QA suffix: `.qa`.
- Established signing alias: `hermes-console-ru-release`. Preserve the existing key and repository secrets; never substitute the upstream signer.
- Pairing remains `hermes://pair`; all update links remain in this fork.
- RU must cover all source ARB and native Android messages, with compatible recursive ICU, metadata and printf contracts. New or changed source text requires explicit translation review.
- `tool/fork/untranslated.json` is the Codex handoff. CI fails closed until it is empty and the reviewed-source ledger matches; never approve English fallback automatically.
- Stable detection/staging may open one draft source PR in this fork. It never merges, signs, tags, uploads binaries or publishes a release.
- Upstream release helpers retain upstream certificate/Play/provenance anchors as reference policy. They do not authorize RU signing or publication. After the final head passes CI, the host/controller owns automatic tested-build delivery under the owner's standing Android authorization; the implementation worker does not sign or publish. Actual established RU certificate and artifact evidence remain mandatory; see the handoff in `docs/STABLE_UPSTREAM_SYNC.md`.
