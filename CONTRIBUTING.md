# Contributing

Thanks for helping. Start with [docs/architecture.md](docs/architecture.md) (how the script is put together and the behaviour it promises) and [docs/kwin-notes.md](docs/kwin-notes.md) (the KWin internals it depends on). Anything about KWin's behaviour should be checked in KWin's source, for the Plasma version you target, rather than assumed: `https://raw.githubusercontent.com/KDE/kwin/Plasma/6.7/src/...`.

## Set up

Development happens in a Fedora 44 distrobox (or toolbox), so your host only ever gets the script itself. Fedora 44 ships Plasma 6.7, which the real-KWin tests need.

```sh
distrobox create --name dev --image registry.fedoraproject.org/fedora-toolbox:44
distrobox enter dev -- ./dev/setup-container.sh
```

`setup-container.sh` installs Node 22, the packaging and lint tools, and everything `tests/kwin` needs; lint tools go into `/opt/kso-tools`, inside the container. Run the commands below inside the container.

## Test

| What | Command | When |
| --- | --- | --- |
| Unit and lifecycle tests | `node --test tests/*.test.mjs` | Always |
| Multi-monitor scenarios in a real KWin | `python3 -I tests/kwin/scenarios.py` (about 3 min; `--list`, `-k NAME`) | Anything touching screens, the reveal, the drop or KWin's tiles |
| QML lint | `/opt/kso-tools/bin/pyside6-qmllint contents/ui/main.qml` | QML changes |
| Shell | `bash -n` and `shellcheck` on `install.sh package.sh dev/*.sh` | Script changes |
| Test bed | `/opt/kso-tools/bin/pyflakes tests/kwin/*.py` | Test bed changes |
| Workflows | `/opt/kso-tools/bin/actionlint .github/workflows/*.yml` | Workflow changes |

CI runs all of these except the KWin scenarios and qmllint.

- **The unit harness** (`tests/lifecycle.test.mjs`) takes the real functions (declared at 4-space indent) and the config settings out of `main.qml` and runs them against a fake KWin. It fails with "harness drift" when something it relies on disappears. New popup-level state must also be declared in its scope.
- **qmllint** can't load KWin's or Plasma's modules outside KWin, so import and `[unqualified]` warnings are expected. Compare against `main`: no new warning types, no syntax errors.
- **Every behaviour fix gets a test that fails without the fix.** Prove it with a mutation check: copy `contents/` and `metadata.json` somewhere, undo the fix there, then run `KSO_ROOT=/path/to/copy node --test tests/*.test.mjs` (or the KWin scenarios with the same `KSO_ROOT`). The guarding test must fail. See [tests/kwin/README.md](tests/kwin/README.md) for writing scenarios.

## Try it in a real session

`./install.sh` installs or upgrades the working tree and enables it. With a distrobox, `dev/preview.sh` (run on the host) runs the tests in the container first and installs a preview stamped `<version>-preview.<commit>`; `dev/preview.sh --restore` puts the release back. Either way, **log out and back in**: KWin keeps running a loaded script's old code until the session ends.

To see what the script does, turn on its log:

```sh
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key debugLog true
qdbus6 org.kde.KWin /KWin reconfigure
journalctl --user -f | grep kde-snap-overlay
```

It reports the grid source per drag and screen (`grid h=… v=… source=quick-tiles|default screen=…`), the overlay engaging and switching, and any snap it skips.

## Style

- QML and JS: 4-space indent; `main.js` uses semicolons, the `.mjs` tests don't. Python: PEP 8. Match the code around you.
- Comments explain *why* (often a KWin fact, with the KWin function it comes from), not what the next line does.
- No new runtime dependencies: the script runs inside KWin with only what KWin's scripting offers.
- Keep `contents/code/main.js` free of QML and KWin access so it stays unit-testable; put geometry and decisions there and the wiring in `main.qml`.

## Commits and pull requests

- Work on a branch; open a pull request against `main`. PRs are merged with a **merge commit**, not squashed.
- Commit subjects are conventional-ish (`fix:`, `feat:`, `test:`, `docs:`, `chore:`) with a body explaining what changed and why.
- Behaviour changes need a real-session check on Plasma before release; say in the PR what you tested and on which Plasma version.
- User-visible changes go into the `## [Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).

## Release

`main` is the release branch: a push that carries a `metadata.json` version without a GitHub release publishes one (`release.yml`).

1. Bump `KPlugin.Version` in `metadata.json` (1.8.0, then 1.8.1 or 1.9.0).
2. Rename `## [Unreleased]` in `CHANGELOG.md` to `## [x.y.z] - YYYY-MM-DD` (add an empty `## [Unreleased]` again after the release); its body becomes the release notes. Keep the existing shape: a headline, then **Fixes**, **Hardening**, **Under the hood**, **Requirements**, and an install line.
3. Run `./package.sh --force`, commit the new `.kwinscript`, `git rm` the previous one, and update the file name in the README's install options.
4. After a real-session check, merge to `main`. The release workflow refuses to publish if the CHANGELOG section is missing or the committed package doesn't match the source.
5. Upload the package to the KDE Store by hand.
