#!/usr/bin/env bash
set -uo pipefail

checkout="$1"
home=/home/tester
locations=("$home" /etc /usr/lib/syncthing-monitor /usr/share/libalpm/hooks /var/lib/syncthing-monitor)
references=$(grep -rF --exclude-dir=.cache -- "$checkout" "${locations[@]}" 2>/dev/null \
    | grep -vxF -e "$home/.config/systemd/user/syncthing-monitor-update.service:Environment=\"SYNCTHING_MONITOR_SOURCE_DIR=$checkout\"" \
        -e "/var/lib/syncthing-monitor/source:$checkout" || true)
if [[ -n $references ]]; then
    printf 'The installed files still reference the checkout at %s:\n%s\n' "$checkout" "$references"
    exit 1
fi
echo "Only the update source records the checkout at $checkout"
