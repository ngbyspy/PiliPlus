# PiliPlus contribution policy

## Workspace and remotes

Use the stable contribution checkout `D:/Projects/PiliPlusAbout/PiliPlus`.
`origin` is `ngbyspy/PiliPlus`; `upstream` is `bggRGjQaUbCoE/PiliPlus`.
The SPY development and release checkouts are separate, on `spy/dev` and `spy/main`.
Do not create another sibling source directory for an ordinary contribution.

Inspect live repository instructions, contribution templates, workflow pins and upstream/main before preparing a new contribution. Historical Flutter versions, checkout states and old issue-specific examples are not current requirements. Run `scripts/preflight.ps1` for Git/remotes/branch evidence; use `-RequireFeatureBranch` before staging.

## Branch and scope

Use a focused `codex/*` branch from fetched `upstream/main`, preserving other public branches and unrelated changes. Prefer the repository's current commit conventions (normally `fix:`, `feat:` or a scoped variant). Do not force-push or rewrite unrelated history.

For a feature originating in SPY, port the implementation, relevant integration points and tests. Exclude downstream branding and application identities, signing material, release infrastructure, private diagnostics, historical injection machinery and unrelated fixes. Keep the contribution checkout useful for continued upstream development.

## Validation

Use the repository's actual pinned Flutter SDK and required platform patches. Format the changed Dart files, inspect `git diff --check`, run focused analysis/tests and relevant platform builds. Distinguish automated tests, packaging success and manual acceptance. CI does not prove interactive playback or responsive-layout behavior.

For the official watchroom feature, accepted core behavior was tested by the user on Android, Windows and iPad. Linux and live disconnection testing remain deferred. Preserve these limits when describing validation; future changes need evidence proportionate to their effect.

## Publication

Target `ngbyspy/PiliPlus:<feature branch>` to `bggRGjQaUbCoE/PiliPlus:main`. Reuse explicit authorization already given in the active conversation. Prepare a concrete reviewable result before any required final publication decision. Do not treat a source push as permission to send extra maintainer messages.

Describe the concrete problem, resulting behavior and relevant validation. Link the issue with `Refs #...` when a Draft PR is for discussion. Reuse supplied demonstrations. Omit personal-use reasons, assistant process notes and unsupported promises to maintain or take over the feature.

Current watchroom contribution: Draft PR #3679, linked to issue #3639. Check for an existing PR before creating another one. Do not ping maintainers just to attract attention.
