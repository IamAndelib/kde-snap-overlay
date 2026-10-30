# Real-KWin test bed

Multi-monitor behaviour can't be unit-tested against a fake: which monitor a snap lands on, what KWin draws on which output, how outputs announce themselves. These scenarios run the working tree's script inside a real, headless KWin with one to three virtual monitors and check what KWin actually did; a few single-monitor scenarios cover what only a real KWin shows (the first map, Escape, pixels).

## Run

Inside the dev container (`dev/setup-container.sh` installs everything; KWin there matches Plasma 6.7):

```sh
python3 -I tests/kwin/scenarios.py              # all scenarios, about 3 minutes
python3 -I tests/kwin/scenarios.py --list       # what each scenario checks
python3 -I tests/kwin/scenarios.py -k stacked   # only names containing "stacked"
python3 -I tests/kwin/scenarios.py --shots DIR  # also save screenshots of key moments
```

`--keep` keeps each sandbox folder (`kwin.log` with the script's `debugLog` output, probe scripts). From the host: `distrobox enter dev -- bash -c 'cd ~/Development/kde-snap-overlay && python3 -I tests/kwin/scenarios.py'`.

## Environment

| Variable | Effect |
| --- | --- |
| `KSO_ROOT` | Test another checkout's `contents/` and `metadata.json` (mutation checks: break a fix in a copy, the guarding scenario must fail). |
| `KSO_SANDBOX_DIR` | Where sandbox folders go (default `/var/tmp`, which distrobox does not share with the host). |

## How it works

| File | Role |
| --- | --- |
| `sandbox.py` | `Sandbox`: one `kwin_wayland --virtual --output-count N` with its own D-Bus bus and HOME/XDG dirs, the script installed and enabled with `debugLog`. Drives the pointer through `org_kde_kwin_fake_input` (pywayland), reads KWin's state by loading small JS probe scripts over D-Bus, and captures screenshots through ScreenShot2. |
| `outputctl.c` | Moves, rescales and disables outputs through `kde_output_management_v2`. It is C because KWin 6.7 announces output devices with a server-created object, which pywayland can't receive. Built on the fly. |
| `window.qml` | A plain test window (Breeze-decorated by KWin, so drags start on a real titlebar). |
| `panel.qml` | A layer-shell top panel with an exclusive zone, standing in for a Plasma panel. |
| `scenarios.py` | The scenarios and the runner. |

## Writing a scenario

- Add an `s_name(sb_factory)` function with a docstring (its first sentence is what `--list` shows) and list it in `SCENARIOS`.
- Assert the scenario's own preconditions with `check(...)` ("setup: ..." / "precondition: ..."), so it can't pass without creating the situation it is about.
- Prove it guards something: it must fail on the code before the fix (`KSO_ROOT`).
- Prefer KWin's state (`sb.state()`, `sb.window()`, `popup()`, `overlay()`) over timing. Where timing matters, widen the margin through the script's config (`script_config={"highlightDelay": "500"}`) rather than sleeping less.
