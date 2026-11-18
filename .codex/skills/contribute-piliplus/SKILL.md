---
name: contribute-piliplus
description: Prepare, validate and publish focused upstream PiliPlus issues or pull requests from the user's fork, including cleaned features ported from PiliPlus-SPY. Use the stable contribution checkout; use build-private-piliplus for SPY development and releases.
---

# Contribute to PiliPlus

Use `D:/Projects/PiliPlusAbout/PiliPlus/`. Read its parent AGENTS.md, live repository instructions and [contribution policy](references/contribution-policy.md). Inspect root, branch, status, remotes and worktrees. Run `scripts/preflight.ps1 -RepoPath <checkout>` before edits and with `-RequireFeatureBranch` before staging.

`origin` is the user's fork, normally `ngbyspy/PiliPlus`; `upstream` is `bggRGjQaUbCoE/PiliPlus`. Fetch the authoritative base and use a focused `codex/*` branch from `upstream/main`, unless current upstream policy says otherwise. Preserve public contribution branches and unrelated work. Reuse this checkout for sequential tasks; another worktree requires an actual concurrency need and belongs inside `PiliPlusAbout/.build/`.

## Port a downstream feature cleanly

A validated feature from `spy/dev` or `spy/main` may be contributed upstream. Extract its coherent implementation, integration points and useful tests onto the upstream-based branch. Exclude SPY branding, package/signing identities, release workflows, generated snapshots, orphan-toolkit machinery, private diagnostics and obsolete injection markers. Never open an upstream PR directly from `spy/main`, `spy/dev` or `personal/main`.

Follow the host project's platform/layout abstractions. Avoid unrelated formatting, dependency upgrades and generated-code churn. Discover the live pinned Flutter version; dated reference versions are historical observations. Format changed files, run focused analysis/tests and relevant builds, and describe actual manual acceptance accurately.

## Review and publication

Inspect `git diff --check`, status, the patch and explicit staged files. Use a concise Conventional Commit subject. Do not force-push or rewrite unrelated history.

Commit, push and create a PR when the active request authorizes that step. Reuse existing authorization instead of repeatedly asking. If the user is only asking whether a PR is advisable, prepare the reviewable proposal before requesting the final publication decision. A large feature can be a Draft PR linked with `Refs #...`; do not close its discussion preemptively or @mention maintainers merely for attention.

PR direction: `ngbyspy/PiliPlus:<focused branch>` to `bggRGjQaUbCoE/PiliPlus:main`. Describe the problem, resulting behavior, actual tests/builds and remaining limitations. Reuse existing demonstrations where appropriate. Omit personal-use reasons, assistant process notes and unsupported maintenance promises.
