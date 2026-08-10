# Linux Syncthing Monitor

Linux Syncthing Monitor is a compact Plasma 6 panel widget for checking and
controlling a local Syncthing instance without keeping the web interface open.

The panel icon has a small status dot: green when every folder is up to date,
yellow while Syncthing is working, and red when Syncthing is unavailable or a
folder needs attention.

## Features

- Overall sync status, progress, transfer rates, and local data size
- Consolidated attention inbox for folder failures, Syncthing errors, and new
  device or folder invitations
- Expandable folder rows with paths, modes, sizes, peers, recent changes, and
  failed items
- On-demand current and upcoming file queue for actively syncing folders
- Per-folder rescan, pause, resume, and open-folder controls
- Remote-device connection, completion, version, address, transfer, last-seen,
  and previous connection-duration details
- Pause and resume controls for remote devices
- Guarded pause-all control and one-click resume-all
- Configurable offline-device grace period with overdue status indication
- Optional Plasma notifications for completed syncs, errors, invitations, and
  overdue devices
- Persisted last-successful-sync time
- One-click access to the Syncthing web interface
- Event-driven updates with lightweight periodic refreshes while open
- Automatic discovery of the local Syncthing address and API key

## Requirements

- Plasma 6
- Syncthing running as the current user

The automatic connection supports Syncthing configurations in the standard
state, config, and data directories. A remote or nonstandard instance can be
configured from the widget's **Connection** settings.

The default offline warning grace period is 24 hours. Set it to zero to keep
offline devices informational indefinitely. Notification categories can be
enabled or disabled independently in the same settings page.

## Install

```bash
git clone https://github.com/DevL0rd/Linux-Syncthing-Monitor.git
cd Linux-Syncthing-Monitor
./install.sh
```

Then open Plasma's **Add Widgets** menu and add **Syncthing Monitor** to a
panel. The installer enables the Qt permission needed to discover Syncthing's
local configuration and restarts Plasma once if the running session needs the
new setting. This permission applies to Plasma's QML process and is retained
when the widget is uninstalled because other widgets may also rely on it.
Middle-clicking the panel icon requests a rescan of every folder.

## Uninstall

```bash
./uninstall.sh
```

Removing the widget does not modify Syncthing or its configuration.

## License

Linux Syncthing Monitor is released under the GPL-3.0-or-later license.
