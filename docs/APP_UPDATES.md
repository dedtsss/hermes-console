# Hermes Console RU Android application updates

About → **Check for app updates** updates this phone's Android application.
It does not invoke the separate remote `hermes update` feature. There is no
automatic download or install: the owner checks, reviews version/notes,
downloads and then separately opens Android's Package Installer. The Android 8+
per-source permission is requested through Settings; returning does not install
anything until the installer button is pressed again. Cancellation/rejection
keeps the retry action. Progress, rate limits, missing release, incompatible
metadata, integrity failures and installer errors have EN/ES/RU messages.

## Required release contract

Only `dedtsss/hermes-console` is consulted, using the public, unauthenticated
`GET https://api.github.com/repos/dedtsss/hermes-console/releases/latest`.
HTTP 404 means no published update. The controller publishes a non-draft,
**non-prerelease**, explicitly **latest** GitHub Release with tag
`vMAJOR.MINOR.PATCH-ru.N` (`N >= 1`). The current source is `1.3.0-ru.1+9631`;
the intended tag is `v1.3.0-ru.1`. Never reuse a version for different APK bytes.
Increase both visible `-ru.N` and actual Android `versionCode` for later builds.

These exact basenames are mandatory for the RU updater channel:

| Asset | Content |
| --- | --- |
| `hermes-console-ru-arm64-v8a-full-release.apk` | Signed ARM64 `fullRelease` APK with established RU signer |
| `hermes-console-ru-update.json` | UTF-8 JSON manifest below (at most 16 KiB) |
| `SHA256SUMS` | Lowercase SHA-256 of the two files above, two spaces, exact basename, one per line |

The controller may additionally attach approved non-secret release evidence.
Never include unsigned/debug/profile/qa/play binaries, AABs, signing keys,
mappings or private diagnostics. Do not substitute upstream APKs or a universal
APK for this named ARM64 asset. The compiled archive must contain ARM64
`libflutter.so` and `libapp.so` and use package `io.github.dedtsss.hermesconsole`.

Example manifest (**replace the placeholder with the measured signed hash**):

```json
{
  "schemaVersion": 1,
  "packageName": "io.github.dedtsss.hermesconsole",
  "versionName": "1.3.0-ru.1",
  "versionCode": 11631,
  "abi": "arm64-v8a",
  "flavor": "full",
  "buildType": "release",
  "assetName": "hermes-console-ru-arm64-v8a-full-release.apk",
  "sha256": "REPLACE_WITH_64_LOWERCASE_HEX_DIGITS"
}
```

`versionCode` is measured from the **final signed APK**, not copied blindly
from pubspec. Flutter ARM64 split builds add 2000 to the pubspec build number:
`9631` normally becomes `11631`. Do not normalize the installed code or infer
newness from a version string; the updater compares actual codes and rejects
equal versions/downgrades. Manifest version name must equal the tag without
`v` and the compiled APK version name.

### GitHub Actions build candidate

The `RU Android source build` workflow may expose one short-lived Actions
artifact named `ru-fullrelease-arm64-<sha>-<run-id>-<attempt>` containing only
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. This is an unsigned,
non-debuggable `fullRelease` ARM64 build candidate for the owner-controlled
signing route; it is not a release asset and cannot pass the app updater's
signature checks. The workflow verifies package, version, ABI libraries and
absence of a signature before upload. It uses no signing secret and leaves the
permanent Gradle release-signing guard intact. No other workflow may upload an
artifact. The controller downloads the exact successful run artifact, signs
the APK with the established RU JKS, then independently verifies the signed
APK and creates the release manifest and checksums. Never reuse the unsigned
candidate as a public asset.

Both required assets must have GitHub API `digest: sha256:<64 lowercase hex>`
and exact `browser_download_url` under this repository/tag. Manifest bytes are
checked against its GitHub digest; APK bytes must match both the manifest hash
and APK GitHub digest. Missing digests stop the update. `SHA256SUMS` supports
independent verification; the app uses API digest + manifest, not an unchecked
checksum file. URLs are constructed from the fixed repository/name and
validated tag; redirects allow only HTTPS on GitHub's
`release-assets.githubusercontent.com` CDN. No credentials are sent.

## Native boundary and delivery gate

The updater is exposed only for `full`, package RU, ARM64 devices. Only `full`
declares `REQUEST_INSTALL_PACKAGES`; no broad storage/enumeration permission is
added. Download goes to a native-generated file in one private cache directory,
with a 512 MiB ceiling,
length checks, network timeouts, cancellation and partial-file cleanup. The
native adapter rehashes the APK and parses package/version/signer presence,
rejects debuggable/unsigned APKs and requires ARM64 release libraries. It repeats
validation before requesting the installer. The dedicated non-exported
FileProvider exposes only `cache/app_update/`, with temporary read URI permission
and ClipData. The method channel accepts no arbitrary file path/URI/package.

Android's Package Installer remains the authority for signature compatibility,
rotation, platform restrictions and final user consent. Hashes from one GitHub
account prove transport consistency, not independent publisher authenticity.
A matching hash does not prove signing continuity. A profile APK mislabeled by
a compromised publisher cannot be fully classified from metadata alone; the
controller must build and inspect the actual signed `fullRelease` artifact.

After final-SHA CI passes, the host/controller follows the standing authorized
sign/build/delivery route. Confirm the established RU certificate and backup;
inspect package/version/ABI/release flags; compute signed-file hashes; create
manifest/checksums; upload all assets; verify hosted bytes/API digests; then
expose stable/latest and verify the updater sees the same release. Reconcile
upstream-only signer/package/provenance helpers first; never use their upstream
certificate for RU. The implementation worker does not sign or publish. Prior
certificate-evidence and private-build-route blockers in
[STABLE_UPSTREAM_SYNC.md](STABLE_UPSTREAM_SYNC.md) remain until verified by the
controller.

Required device acceptance before claiming delivery: update a trusted previous
RU install with the same signer, retain data/pairing, exercise denied/granted
unknown sources, cancellation, insufficient storage, corrupted/wrong-package
APK and signer mismatch. Source/widget tests and CI compilation cannot prove
those physical installer results.

References: [GitHub Releases API](https://docs.github.com/en/rest/releases/releases),
[asset digests](https://docs.github.com/en/rest/releases/assets),
[Android per-source install permission](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()),
[FileProvider grants](https://developer.android.com/reference/androidx/core/content/FileProvider).
