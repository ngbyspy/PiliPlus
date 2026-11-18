# Archived PiliPlus personal kit

This branch preserves the earlier module/injection experiments and their source.
New development uses the ordinary Flutter source on `spy/dev`; distributable
PiliPlus-SPY source and packaging use `spy/main` in this fork.

The old per-feature generated-worktree workflow is retired. Its workflows are
kept under `.github/legacy-workflows` as historical reference and do not run on
new pushes. Platform patches and native dependency identities remain available
for recovery. Machine-local caches, credentials, runtime diagnostics and binaries
are excluded from this source branch.

The cache-exporter code here is an experiment, not a shipped SPY feature.
Accepted watchroom source snapshots are available on `archive/watchroom-*`.
