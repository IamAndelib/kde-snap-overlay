# Open bug: popup fails to trigger on the first drag after login / KWin restart

Reported on all dev builds (v1.3.x → v1.5.1) and under investigation when the session forked.
Symptom: after login, the FIRST drag toward the top does not show the popup. The user must
native-snap a window to an edge once, and from then on the popup triggers reliably.

## Key diagnostic clue (user-observed)
"i have to snap a window first with native snap to edge and then i can trigger the popup later."
→ The first drag session primes something. If v1.2.1 (develop base) shows the same failure,
the bug is in the shared core (window discovery / signal gating timing), NOT the KZones fork.

## Evidence gathered
- kwin 6.7.4, Wayland.
- Journal (v1.2.1 era, BEFORE the KZones fork, 21:27:31):
  `QML Dialog: trying to show an empty dialog` at main.qml:7 and :482 — the dialog was shown
  with no content. Appears during drag handling; candidate lead.
- Journal (v1.5.0): `Component failed to load: Cannot assign object of type "Connections"`
  — fixed in v1.5.1 (Connections must live inside the root Item, not under the Dialog).
- v1.5.1 journal also shows: `QML Connections: Detected function "onWindowClosed" ... no
  signal of the target matches the name` → Workspace.windowClosed does NOT exist on kwin
  6.7.4; that handler never fires (harmless but useless — the stuck-drag guard is dead).
- Signal connect form: `window.interactiveMoveResizeStarted.connect(...)` (no "on" prefix)
  is PROVEN working on this build (v1.3.x–v1.4.4 detected drags). KZones'
  `onInteractiveMoveResizeStarted` prefix style is UNPROVEN here.
- User's KZones settings: no zoneSelectorTriggerDistance override → KZones default 1 →
  75px trigger (`config*50+25`). kzones + magnetile are configured in kwinrc but NOT
  enabled → no script contention.

## Candidate root causes to investigate on develop
1. windowAdded fires before the client is fully initialized → connectWindow fails or the
   signal never fires for that client (permanent bail in old code; unconditional connect
   in v1.5.1 did not fix it → suspect deeper: client object replaced/invalidated?).
2. First show() after login: PlasmaCore.Dialog platform-window creation race on Wayland
   (the "trying to show an empty dialog" warning). Native snap = our hide() ran → next
   show() works. KZones' Dialog declares width/height declaratively at load; we set them
   in show() — try declaring size up front.
3. window.move gate at Started time — verify move is actually true on the first-ever drag.
4. Reproduce under journal: journalctl -f while doing the login repro; look for
   TypeErrors from connectWindow or the Started handler.

## Env notes
- System currently runs v1.2.1 from main (user installed it for comparison testing).
- kpackagetool6 --upgrade refuses downgrades → uninstall before installing older versions.
