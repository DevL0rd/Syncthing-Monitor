#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 DevL0rd <dmhzmxn@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly PLASMOID_ID="org.devl0rd.syncthingmonitor"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly PLASMA_SERVICE="plasma-plasmashell.service"
readonly PLASMA_OVERRIDE_DIR="${CONFIG_HOME}/systemd/user/${PLASMA_SERVICE}.d"
readonly PLASMA_OVERRIDE="${PLASMA_OVERRIDE_DIR}/syncthing-monitor.conf"
readonly PLASMA_ENV_DIR="${CONFIG_HOME}/plasma-workspace/env"
readonly PLASMA_ENV_FILE="${PLASMA_ENV_DIR}/syncthing-monitor.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/packaging/lib.sh"
unregister_system_updates

command -v kpackagetool6 >/dev/null 2>&1 || {
    printf 'Error: kpackagetool6 is required.\n' >&2
    exit 1
}

if kpackagetool6 -t Plasma/Applet -r "${PLASMOID_ID}" >/dev/null 2>&1; then
    printf 'Uninstalled Syncthing Monitor.\n'
else
    printf 'Syncthing Monitor is not installed.\n'
fi

if [[ -e ${PLASMA_OVERRIDE} || -e ${PLASMA_ENV_FILE} ]]; then
    rm -f -- "${PLASMA_OVERRIDE}" "${PLASMA_ENV_FILE}"
    printf 'Removed the local configuration reads Syncthing Monitor enabled for Plasma.\n'
    systemctl --user daemon-reload 2>/dev/null || true
fi

rm -rf -- "${UPDATE_USER_STATE_DIR}"
for directory in "${PLASMA_OVERRIDE_DIR}" "${CONFIG_HOME}/systemd/user" "${CONFIG_HOME}/systemd" \
    "${PLASMA_ENV_DIR}" "${CONFIG_HOME}/plasma-workspace" "${DATA_HOME}/plasma/plasmoids" "${DATA_HOME}/plasma"; do
    if [[ -d ${directory} ]]; then
        rmdir --ignore-fail-on-non-empty -- "${directory}"
    fi
done
