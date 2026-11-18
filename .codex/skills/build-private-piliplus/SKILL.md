---
name: build-private-piliplus
description: Develop, validate and package the user's PiliPlus-SPY downstream edition in the consolidated PiliPlusAbout workspace. Use for SPY releases, private features, Android/Windows/iPad builds, downstream updates, or personal-kit experiments. For a focused upstream PR, use contribute-piliplus.
---

# Develop and release PiliPlus-SPY

Read `D:/Projects/PiliPlusAbout/AGENTS.md` and the [workspace contract](references/private-build-contract.md). The user's 2026-11-18 redesign replaces the old per-feature orphan-kit/injection workflow.

## Three stable source directories

| Directory | Role | Normal branch |
| --- | --- | --- |
| `PiliPlusAbout/PiliPlus` | Upstream contributions | focused `codex/*` branches |
| `PiliPlusAbout/PiliPlus-personal-kit` | SPY development and experiments | `spy/dev` |
| `PiliPlusAbout/PiliPlus-SPY` | Distributable SPY source and packaging | `spy/main` |

Inspect the actual Git root, branch, status, remotes and worktrees. Preserve unrelated changes and existing public contribution branches. Push SPY source only to the user's fork, never upstream.

Use branches and commits for versions. Reuse the development checkout for ordinary feature work. Do not create a sibling worktree, clone or source copy per task, build or platform. Put tool-managed staging beneath `.build/` and shared dependencies beneath `.cache/` inside PiliPlusAbout. An additional temporary worktree needs a concrete concurrency reason and must stay inside this workspace.

## Source and promotion

Maintain ordinary Flutter source on `spy/dev` and `spy/main`. Release code is not regenerated from historical orphan `personal/main` modules. Historical injection tooling and snapshots are recovery material, not a second live source of truth.

Implement on `spy/dev`, run appropriate checks, inspect the diff, then promote accepted changes to `spy/main`. Keep incomplete experiments, private diagnostics and unrelated modules out of distributable source. Preserve shared platform logic and responsive behavior based on available window size. Functionality takes priority over the former ultra-low-coupling requirement.

Port an upstream contribution onto a focused branch from current `upstream/main` in `PiliPlus/`. Exclude SPY branding, release infrastructure, private diagnostics and obsolete injection markers. A downstream origin does not prohibit contributing a cleaned feature upstream.

## Builds and continuity

Use checked-in release tooling and pinned Flutter configuration. Verify platform-specific SDK/native-source patches and apply them only to the appropriate SDK or staging area. Do not modify global SDKs or another platform's verified SDK.

Prepare Windows ZIP, signed Android APK and a self-signable iPad/iPhone device IPA when the user requests a SPY version/release. iOS builds run on GitHub macOS runners without an Apple signing identity; the user signs the IPA. Linux remains deferred. Keep the same Android application identity and private signing key for updates; never silently regenerate a missing release key or publish signing material.

Run focused formatting, analysis and tests, inspect actual artifacts, and record the source commit, upstream baseline, toolchain, checks, platform patch hashes and artifact SHA256 values. Separate build success from native acceptance. Live network-disconnection recovery tests remain deferred unless requested.

The user wants a LOCAL release interface like GitHub Releases: `PiliPlusAbout/Releases/index.html`, with version cards and clear platform download buttons. Do not interpret this as authorization to publish GitHub Releases. Put ready packages in each version's Windows/Android/iPad folders; keep manifests, checksums and build reports under `_metadata`. Maintain the page with `tool/spy/register-release.ps1` and `render-releases.ps1`. Windows must include a clearly named portable ZIP (upstream convention: unzip and run with all DLL/data files). Add a later IPA to the same local version. Preserve per-platform source provenance, preceding accepted packages and signing backups. Publish to GitHub Releases only when explicitly requested.

## Reorganization and retirement

Before directory moves, snapshot refs and unique tracked/untracked source and preserve accepted artifacts. Move linked worktrees through Git and repair pointers after moving the primary repository. Check resolved targets before deletion. Retire obsolete worktrees only when their source and artifacts are recoverable. Keep runtime diagnostics, accounts, cached media, signing keys and generated dependencies out of public commits.
