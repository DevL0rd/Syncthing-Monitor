#!/usr/bin/env bash
set -uo pipefail

checkout="$1"
home=/home/tester
source_copy="$home/.local/share/syncthing-monitor/source"
locations=("$home" /etc /usr/lib/syncthing-monitor /usr/share/libalpm/hooks /var/lib/syncthing-monitor)
references=$(grep -rF --exclude-dir=.cache -- "$checkout" "${locations[@]}" 2>/dev/null | grep -vF "$source_copy/" || true)
if [[ -n $references ]]; then
    printf 'The installed files still reference the checkout at %s:\n%s\n' "$checkout" "$references"
    exit 1
fi
echo "Nothing installed references the checkout at $checkout"
