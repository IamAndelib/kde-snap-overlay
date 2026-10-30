---
name: Bug report
about: Something the popup, the preview or the snap does wrong
labels: bug
---

**What happened, and what did you expect?**

**Steps to reproduce**
1.
2.

**Setup**
- Plasma / KWin version (`kwin_wayland --version`):
- Script version (System Settings → Window Management → KWin Scripts):
- Wayland or X11:
- Monitors (count, resolutions, scaling, how they are arranged):
- Panels (which edge, which monitor):
- Separate virtual desktops per monitor (System Settings → Virtual Desktops): yes / no
- Any non-default settings from the README's Configuration table:

**Log**
Turn on the script's log, reproduce, and paste the lines:

```sh
kwriteconfig6 --file kwinrc --group Script-kde-snap-overlay --key debugLog true
qdbus6 org.kde.KWin /KWin reconfigure
journalctl --user -b | grep kde-snap-overlay
```
