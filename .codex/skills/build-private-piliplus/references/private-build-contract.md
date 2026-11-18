# PiliPlusAbout workspace contract

The user's explicit 2026-11-18 redesign establishes three stable source directories beneath `D:/Projects/PiliPlusAbout`:

- `PiliPlus/`: upstream contributions on focused `codex/*` branches.
- `PiliPlus-personal-kit/`: SPY development and experiments on `spy/dev`.
- `PiliPlus-SPY/`: distributable downstream source on `spy/main`.

`origin` is `https://github.com/ngbyspy/PiliPlus.git`; `upstream` is `https://github.com/bggRGjQaUbCoE/PiliPlus.git`.

## Ownership

Accepted Flutter source lives in `spy/main`; work in progress lives in `spy/dev`. Promote validated changes through Git rather than copying divergent module trees. The orphan `personal/main` kit and 2026-11 generated watchroom trees are historical backups, not the mandatory future build architecture. Functionality takes priority over the former ultra-low-coupling rule.

Contribute cleaned features from an upstream-based branch. Never target upstream from `spy/main`, `spy/dev`, `personal/main` or a historical snapshot.

## Storage

- `Releases/`: versioned packages, checksums and build reports.
- `.cache/`: reusable SDKs and downloaded dependencies.
- `.build/`: disposable platform staging; preserve failed work when useful for diagnosis.
- `Archive/` or `.state/`: recovery manifests and unique historical source/diagnostics. Private runtime evidence stays local.
- `.secrets/`: ignored signing material, with a separate local key backup. Never upload it.

Use commits, tags and source archives for old versions, not new dated project siblings. Explain temporary parallel workspaces and retire them once safely integrated.

## Release evidence

The requested release interface is LOCAL: `Releases/index.html` resembles GitHub Releases and links versioned platform files. Each version has Windows/Android/iPad directories and `_metadata` for reports, manifest and hashes. Keep technical details collapsed in the page. Register ready artifacts and append a later IPA to the same version; do not infer permission to publish a GitHub Release. The user will report the current iPad CI outcome, so do not continue polling that run unless asked.

Pin Flutter and the upstream baseline, preserve verified platform patch chains, lock dependencies, run appropriate analysis/tests and build actual artifacts. CI success does not replace native acceptance.

The original official-watchroom core has user acceptance on Android, Windows and iPad. Report changed package identities and behavior accurately. Linux and network-disconnection recovery remain deferred. iPad IPA signing is done by the user after GitHub macOS no-codesign builds.

Record exact SPY/upstream commits, dependencies/toolchain, checks and artifact hashes. Preserve previous accepted packages and the signing identity.

## Current authorization

The user requested uploading all source modifications to their fork, reorganizing parallel folders into this layout, updating these skills and preparing their own three-platform packages. This covers necessary branch setup, commits/pushes to their fork, recoverable moves and retirement of verified redundant trees. It does not authorize publishing credentials/private runtime data or unsolicited maintainer messages.
