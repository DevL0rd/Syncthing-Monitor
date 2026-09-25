#!/usr/bin/env bash
set -uo pipefail

failed=0
check() {
    if eval "$2" >/dev/null 2>&1; then
        echo "ok: $1"
    else
        echo "FAILED: $1"
        failed=1
    fi
}

plasma_script() {
    gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript "$1"
}

check "the widget is installed" "kpackagetool6 -t Plasma/Applet -l | grep -qx org.devl0rd.syncthingmonitor"
check "the shared components were copied into the widget" "test -f ~/.local/share/plasma/plasmoids/org.devl0rd.syncthingmonitor/contents/ui/lib/PopupShell.qml"
check "Plasma can read local configuration" "systemctl --user show plasma-plasmashell.service -p Environment | grep -q QML_XHR_ALLOW_FILE_READ=1"
check "the system update hook is registered" "test -f /usr/share/libalpm/hooks/syncthing-monitor-update.hook && test -x /usr/lib/syncthing-monitor/system-update && test -f /usr/lib/syncthing-monitor/lib.sh"
check "the installer is staged for updates" "test -x ~/.local/share/syncthing-monitor/installer/install.sh && test -f ~/.local/share/syncthing-monitor/installer/packaging/lib.sh"
check "the update finisher is enabled" "systemctl --user is-enabled syncthing-monitor-update.service"
check "Plasma runs" "systemctl --user is-active plasma-plasmashell.service"

since=$(date '+%Y-%m-%d %H:%M:%S')
check "the widget can be added to the desktop" "plasma_script 'desktops()[0].addWidget(\"org.devl0rd.syncthingmonitor\")'"
sleep 10
check "the widget is on the desktop" "plasma_script 'print(desktops()[0].widgets(\"org.devl0rd.syncthingmonitor\").length)' | grep -q \"'1\""
errors=$(journalctl --user -u plasma-plasmashell --since "$since" --no-pager -o cat | grep -F 'org.devl0rd.syncthingmonitor' | grep -iE 'error|not installed|not a type|unavailable' | sort -u)
check "Plasma logged no Syncthing Monitor QML errors" "[[ -z \"\$errors\" ]]"
[[ -n $errors ]] && echo "$errors"
plasma_script 'for (const widget of desktops()[0].widgets("org.devl0rd.syncthingmonitor")) widget.remove()' >/dev/null
sleep 5
exit "$failed"
