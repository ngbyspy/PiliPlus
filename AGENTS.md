# PiliPlus-SPY source

Read the parent PiliPlusAbout/AGENTS.md when available. This Flutter source is shared by the stable development checkout (`PiliPlus-personal-kit`, `spy/dev`) and distributable checkout (`PiliPlus-SPY`, `spy/main`). Work on features in spy/dev and promote validated changes through Git. Keep incomplete experiments off spy/main. The initial consolidated SPY baseline is authorized by the user's 2026-11-18 reorganization request.

The original watchroom behavior has user acceptance on Android, Windows and iPad. Maintain it in `lib/features/watchroom` and `test/watchroom`. Do not regenerate the application from the historical personal/main injection kit. Build staging, SDK patches and generated dependency copies are machine-local; use `tool/spy/build.ps1` with the repository-pinned Flutter SDK.

Keep the SPY identities stable for updates: Android/iOS `com.ngbyspy.piliplus.spy`, Windows executable `piliplus_spy.exe`. Android release signing material is outside this repository in PiliPlusAbout/.secrets and has a separate local backup. Never regenerate a missing key or put credentials in source, logs or artifacts. iPad is a no-codesign device IPA prepared on GitHub macOS for user signing.

Deliverables and checksums go to PiliPlusAbout/Releases. Preserve the preceding accepted packages. Record actual source commit, upstream baseline, checks and native acceptance. Linux and live disconnection tests remain deferred. For an upstream PR, port only the feature onto a fresh upstream-based branch in PiliPlusAbout/PiliPlus, excluding SPY identities, release tooling and downstream-only history adjustments.
