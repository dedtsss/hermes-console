# Stable upstream updates for Hermes Console RU

The baseline is **Hermes Console 1.2.15+9540**, tag `v1.2.15`, commit
`aa6e5119d8397220eea4399a352ce746b21f1834`. The tag was resolved through its
annotated tag object, not through the release's mutable `target_commitish: main`.
`tool/fork/upstream.json` records the immutable baseline. Upstream
`xP3ta/hermes-console` is read-only; all branches and PRs belong to
`dedtsss/hermes-console`.

## What the fork owns

`tool/fork/overlay.json` classifies every difference from the stable baseline:

- `patch`: a small explicit `overlay.patch` for RU locale selection, Android
  identity/actions/notification metadata, fork update links, focused tests and
  CI gates. An upstream edit conflicting with a hunk stops staging; there is no
  three-way conflict guessing or unattended resolution.
- `local`: RU ARB/native catalogs, translation review data, fork tools,
  documentation and workflows. An upstream file colliding with a local path
  stops staging instead of being overwritten.
- `derived`: the five source SBOM outputs, compared against the full generator
  in authoritative Flutter CI.

English and Spanish source catalogs, the Hermes runtime and pairing protocol
remain upstream code. Spanish remains the upstream `gen-l10n` template because
it carries the complete typed placeholder metadata. EN and ES have the same
message keys and argument names; some ES messages use plurals where English
uses a simple count. RU preserves the Spanish template's recursive ICU contract
and metadata exactly, without changing English or Spanish behavior.

The initial integration preserves both histories with the exact stable commit
as a merge parent. Future staging assembles the stable tree plus this overlay
in a new worktree and creates a two-parent commit. It does not merge arbitrary
upstream main commits or replay the entire historical localization diff.

## Detect and stage

Lightweight local commands require Python 3, Git and an authenticated `gh` CLI
with read access to upstream and write access only to the owner's fork:

```bash
python3 tool/fork/sync.py detect
python3 tool/fork/sync.py check-overlay
python3 tool/fork/localization.py check
python3 -m unittest discover -s test -p 'fork_sync_test.py'

# Use the published stable tag reported by detect; example future version:
python3 tool/fork/sync.py stage --tag v1.2.16 --output /tmp/hermes-ru-stable
```

Staging requires a clean tree, a fully reviewed current RU catalog, an exact
current overlay, and `origin` pointing to `dedtsss/hermes-console`. It fetches
only `refs/tags/vMAJOR.MINOR.PATCH`, peels annotated tags to commits and checks
that pubspec version/build agrees with the tag and increases the Android build
number. Drafts, prereleases, arbitrary refs and downgrades are rejected.
`sync.py` itself never pushes, opens a PR, signs or publishes.

The scheduled/manual `stable-upstream-sync.yml` workflow detects the highest
published stable semantic version, then stages `sync/upstream-vVERSION` and
opens one draft PR. An existing open `sync/upstream-*` PR pauses new staging.
It uses only the standard repository `GITHUB_TOKEN`; no translation service,
paid API or new persistent secret is required. The repository must permit
Actions to create PRs. If that GitHub setting disallows PR creation, the branch
is retained and the run fails visibly; the owner can open the draft PR from it.
An existing divergent branch is never force-pushed.

Commits use the release publication time, so a retry with the same main head,
release and overlay produces the same commit. The workflow explicitly dispatches
quality, Android and real-gateway checks because PR events created with
`GITHUB_TOKEN` do not themselves start other workflows. Checks remain required
when a human updates the draft. Nothing automatically marks it ready or merges
it. Source PR creation is the only automated publication-like action; there
are no binary uploads, release tags, GitHub Releases or upstream writes.

## Translate only the delta

`tool/fork/untranslated.json` is a machine-readable handoff to Codex. It contains
only new, changed, invalid or unreviewed entries, with their source messages,
metadata and current RU text. Removed keys appear separately under `obsolete`.
ARB entries are `arb/KEY`; native Android entries are
`android/string/NAME`, `android/plurals/NAME` or `android/string-array/NAME`.

`prepare` synchronizes metadata and removes obsolete keys, but **never copies
English or Spanish into missing RU entries**. A reviewed-source ledger stores
hashes of both source locales/metadata and the reviewed translation. A changed
source therefore blocks the gate even if a stale RU value has the same key.
Changing a translation also requires review. Missing/blank text, source-language
fallback, incompatible ICU/printf arguments and metadata differences block CI.
Proper product/protocol names, command tokens and placeholder-only formats need
an exact value and a specific reason in `untranslated_allowlist.json`. That
exception cannot approve a later changed value.

Give Codex the delta and both source catalogs, then:

1. Translate the listed messages in `lib/l10n/app_ru.arb` and native XML in
   `android/app/src/main/res/values-ru`. Preserve argument names, types, ICU
   selectors, nested arms, native plural quantities and printf positions.
2. Use natural concise Russian. Preserve actual product/protocol names, file
   paths and executable commands. Review mixed-language text manually; no
   syntactic tool can certify translation meaning.
3. Run `python3 tool/fork/localization.py prepare`. New native resource files
   must be added to the explicit `local` manifest before committing.
4. Write a JSON array of the reviewed delta keys, for example
   `["arb/newMessage", "android/string/new_label"]`, to `/tmp/reviewed-keys.json`.
5. Record that explicit review and refresh the delta:

   ```bash
   python3 tool/fork/localization.py review --keys /tmp/reviewed-keys.json \
     --report tool/fork/untranslated.json
   python3 tool/fork/localization.py check
   ```

`review --all` is reserved for an intentionally reviewed complete catalog (used
for the initial 1.2.15 integration). Never run it unattended to clear failures.
A reviewed ledger is an audit record, not an automatic translation approval.

After intentional overlay edits, review the diff, run
`python3 tool/fork/sync.py refresh-overlay`, and run `check-overlay` again. Add
new overlay/local files explicitly to `overlay.json`; unclassified tracked
changes fail. Stage individual paths, never `git add -A`.

## CI and signing boundaries

Use lightweight source checks locally. `pr-quality.yml` remains authoritative
for Flutter analysis, all Dart/Python tests, localization generation, SBOM
regeneration, licensing and secret scans. `fork-android-check.yml` compiles the
`full` flavor in debug mode to verify Android compatibility, reads no signing
secrets and uploads no artifact. Debug output is temporary CI build evidence,
not an installable release delivery. The existing real-gateway lane remains.

`source_sbom.py` can rebind the stable source SBOM fingerprints only when every
generator input matches the pinned upstream tree except Android identity and
comments in Gradle. Dependency graph/inventory data is retained, never invented.
Any other input change requires full regeneration. CI runs the complete generator
and rejects a difference; these source checks claim no signed/build evidence.

The established Android ID is `io.github.dedtsss.hermesconsole`, visible name
`Hermes Console RU`, QA suffix `.qa`, Kotlin namespace
`com.hermesagent.hermes_android`. The established signing alias is
`hermes-console-ru-release`. Existing `key.properties` loading and fail-closed
release signing are retained. Do not generate a replacement key, change the
alias or rewrite repository signing secrets. Version `1.2.15+9540` advances the
previous RU `1.2.9+4964`. Notification metadata/actions use the RU identity;
`hermes://pair` continues to work. Updates link to this fork's releases, not the
upstream package or Play listing.

Upstream 1.2.15 replaced its signed artifact workflow with verification-only CI.
That boundary is retained. `tool/release/release_contract.json` and the release
helpers are upstream reference policy, including **upstream** signer certificate,
source actors, provenance and Play package expectations. They are not RU signing
authority and must never be used to replace this fork's signer. Their strict
checks reject RU artifacts. Before any separately approved RU publication,
reconcile the release contract against the already established RU certificate
and artifact evidence; do not copy the upstream certificate. This sync neither
reads signing material nor requests or performs a release.

Stable 1.2.15 itself retires Mobile Bridge/local-agent code. Its Dashboard
migration and `hermes://pair` support are retained unchanged; no private BruceVPS
endpoints or credentials are introduced. Existing authorized public HTTPS
connections still use stock upstream transport/privacy rules.
