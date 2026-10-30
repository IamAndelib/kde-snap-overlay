# KDE Snap Overlay: project memory

A KWin 6 script (KDE Plasma 6, Wayland) that shows a Windows-style "Snap Layouts" popup when a window is dragged to the top edge. Dropping on a zone applies **KWin's native quick tiling**. Author: IamAndelib. Licence: GPL-3.0-or-later (some components derive from KZones; see `NOTICE`).

**Status:** v1.7.1 is released and is the only GitHub release (older releases and tags were deleted on purpose). `main` is the release branch. Unreleased work is listed under `## [Unreleased]` in `CHANGELOG.md`.

## Read first

- [docs/architecture.md](docs/architecture.md): repo map, how `main.qml` is organised, and the **behaviour contract**. Don't change contract behaviour without asking.
- [docs/kwin-notes.md](docs/kwin-notes.md): the KWin behaviour the script depends on, verified in KWin's source. **Read it before touching tiles, the drag/drop lifecycle, activation or screens.**
- [CONTRIBUTING.md](CONTRIBUTING.md): every test, lint and release command, the mutation check, style and git conventions.
- [tests/kwin/README.md](tests/kwin/README.md): the real-KWin multi-monitor test bed.

## Working rules

- Be meticulous and precise. **Never break working behaviour.** When a fix changes observable behaviour, ask first.
- Verify KWin behaviour in KWin's source (`https://raw.githubusercontent.com/KDE/kwin/<branch>/src/...`, e.g. `Plasma/6.7`, the version the user runs) rather than guessing; record new facts in `docs/kwin-notes.md`.
- Plan non-trivial work first; ask before anything outward or irreversible (pushing, merging, releases, deleting releases/tags/branches, force-pushes). KDE Store uploads are the user's.
- Every behaviour fix gets a test that fails on the broken variant (mutation check). Multi-monitor and reveal changes also get a `tests/kwin` scenario.
- Keep docs in step with the code: test counts and commands in `CONTRIBUTING.md`, the contract in `docs/architecture.md`, user-visible changes in `CHANGELOG.md` and the README.
- Git: feature branch, PR, **merge commit** (not squash); `fix:`/`feat:`/`test:`/`docs:`/`chore:` subjects with an explanatory body.

## This machine: develop in the container, test on the host

The user keeps the host untouched. **All development commands run inside the distrobox `dev`** (Fedora 44 toolbox, set up by `dev/setup-container.sh`; it shares `$HOME`, so the repo has the same path inside). From a host shell:
`distrobox enter dev -- bash -c 'cd ~/Development/kde-snap-overlay && <command>'`.

- Never install packages or tools on the host; add them to `dev/setup-container.sh` and run it in the container.
- The only host-side step is a preview for the user: `dev/preview.sh` (tests in the container, then installs `<version>-preview.<commit>`); `--status`, `--restore`. The user must **log out and back in** afterwards.
- Feature flow: develop and validate in the container (unit tests, linters, `tests/kwin` when relevant), `dev/preview.sh`, then hand the user a real-session test checklist. Publish only after their sign-off. The user has a single 1920x1080 monitor, a bottom panel and per-output virtual desktops enabled, so multi-monitor behaviour is verified in `tests/kwin`.

## History, in brief

- Up to 1.7.0: the KZones-style popup, native dialog panel, FancyZones overlay model.
- 1.7.1: cleanup, licence corrected to GPL-3.0-or-later, exact KWin tile geometry (the `parentTile`/`childTiles` bug), Escape and Meta+drag fixes, hardening, release automation. The old v2.x line was abandoned and removed.
- Unreleased: fixes found with the new `tests/kwin` bed (wrong-monitor snap for wide windows, stacked monitors, top panel, shadow line, per-output desktop switches, first-drag flash, Escape after a held press, fixed-size windows, `topGap` maximum), contributor docs and CI linting.
- A sibling project, `window-geometry-restore`, lives in its own repo and is out of scope here.
