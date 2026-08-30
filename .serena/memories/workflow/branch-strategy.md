# Branch strategy & session state for kde-snap-overlay (session forked 2026-08-30)

## Branch topology (current)
- `main` @ b76b61c (v1.2.1) — release-only baseline; fast-forward from origin/main only.
- `develop` @ 4c8c668 (v1.6.0) — **ACTIVE development branch**: the PROVEN v1.2.1 trigger
  chassis with ONLY the KZones popup style grafted in (2659551). Diagnostic outcome: the
  login-trigger bug came from the dev line's own restructures — v1.2.1 never fails. Rule
  going forward: do NOT touch the v1.2.1 trigger/lifecycle machinery; style/UI work only.
  Currently local-only (unpushed).
- `testing` @ e06f8b8 — **SIDE-LINED**: the KZones-based fork line (21 commits ahead of
  origin/testing, unpushed). Do not develop here; cherry-pick from it if a piece proves
  worth keeping. History: v1.3.x zone overlay → v1.4.x KZones selector/lifecycle forks →
  v1.5.0/1.5.1 main.qml skeleton fork. Preserved intact.

## System state
- The SYSTEM currently runs v1.2.1 installed from `main` (user is comparison-testing the
  login-trigger bug). To test develop builds: `git switch develop` → `./install.sh`
  (kpackagetool6 --upgrade refuses downgrades → uninstall first when going older).
- Stale kwinrc overrides (`topGap`, `activationDistance`) were deleted from
  `[Script-kde-snap-overlay]`; group is now empty. Config keys in code:
  activationDistance(150, clamp 100–400), topGap(0 = KZones-glued), showDistance(75 =
  KZones' trigger), peekHeight(30), edgeGapRatio(0.25).
- User has kzones + magnetile installed in kwinrc but NOT enabled — leave them alone.

## Workflow rules (established this session)
- All development on the active dev branch (now `develop`); never commit to `main`.
- Feature branches upstream (`feature/*`, `fix/*`, `hardening/*`) — sync/install from them
  only when asked; never merge without approval.
- Single-artifact policy: only the latest `.kwinscript` is tracked; `package.sh` builds it,
  `install.sh` installs (stages metadata.json + contents; artifact only for distribution).
- Deploy loop: edit → `./package.sh` → `./install.sh` → verify `isScriptLoaded` +
  installed metadata version + journal for QML errors → commit on the dev branch.
- CRITICAL QML lessons (learned the hard way):
  - PlasmaCore.Dialog's default property only accepts Items — Connections/Timers go inside
    a plain Item child (KZones' mainItem pattern). Violating this fails the WHOLE component
    to load (journal: "Cannot assign object of type Connections to property QQuickItem*").
  - Signal connects use NO "on" prefix: `window.interactiveMoveResizeStarted.connect(...)`
    is proven on kwin 6.7.4; KZones' `on`-prefixed style is unproven here.
  - `Workspace.windowClosed` does NOT exist on kwin 6.7.4 (Connections warns "no signal
    matches") — don't rely on it.

## Open work
- The login-trigger bug (first drag after login shows nothing; native-snap primes it) —
  full evidence + candidate causes in `mem:debug/login-trigger-bug`. Unresolved.
- Demo GIF (screenshots/demo-compact.gif) is stale — shows the old 8-card UI; needs a
  manual re-recording eventually.
- `testing` line has good ideas worth cherry-picking if wanted: hover-sticky selector,
  moved-gate (grab-release never snaps), two-stage peek/drop reveal, dynamic tile-grid
  splits (splitsFromTileTree), popup-area-only selection.