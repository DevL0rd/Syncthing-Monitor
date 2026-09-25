#!/usr/bin/env bash
set -uo pipefail

cd /opt/install-test/snapshots || exit 1
NOISE='\./\.config/plasma-org\.kde\.plasma\.desktop-appletsrc$|\./\.local/state/(UserFeedback\.|kglobalshortcutsstaterc)|\./\.local/share/flatpak(/|$)'
failed=0
for snapshot in system etc home-files home-folders session; do
    changes=$(diff before/$snapshot after/$snapshot | sed -n 's/^\([<>]\) /\1 /p' | grep -vE "^[<>] ([0-9a-f]{64}  )?($NOISE)" || true)
    if [[ -n $changes ]]; then
        printf 'Uninstalling changed %s:\n%s\n' "$snapshot" "$changes"
        failed=1
    fi
done
if [[ -e /var/lib/syncthing-monitor ]]; then
    echo "Uninstalling left /var/lib/syncthing-monitor behind"
    failed=1
fi
((failed == 0)) && echo "Uninstalling left the system as it was"
exit "$failed"
