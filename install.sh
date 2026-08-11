#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 DevL0rd <dmhzmxn@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PLASMOID="${SCRIPT_DIR}/plasmoid/org.devl0rd.syncthingmonitor"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly PLASMA_SERVICE="plasma-plasmashell.service"
readonly PLASMA_OVERRIDE_DIR="${CONFIG_HOME}/systemd/user/${PLASMA_SERVICE}.d"
readonly PLASMA_OVERRIDE="${PLASMA_OVERRIDE_DIR}/syncthing-monitor.conf"
readonly PLASMA_ENV_DIR="${CONFIG_HOME}/plasma-workspace/env"
readonly PLASMA_ENV_FILE="${PLASMA_ENV_DIR}/syncthing-monitor.sh"
write_config_file() {
    local path="$1"
    local contents="$2"

    if [[ -f "${path}" && ! -L "${path}" && "$(<"${path}")" == "${contents}" ]]; then
        return 1
    fi
    if [[ -L "${path}" ]]; then
        printf 'Error: refusing to overwrite symbolic link %s.\n' "${path}" >&2
        exit 1
    fi

    mkdir -p -- "$(dirname -- "${path}")"
    printf '%s\n' "${contents}" > "${path}"
    chmod 0644 "${path}"
    return 0
}

configure_local_file_access() {
    local override_contents
    local env_contents

    override_contents=$'[Service]\nEnvironment=QML_XHR_ALLOW_FILE_READ=1'
    env_contents='export QML_XHR_ALLOW_FILE_READ=1'

    if command -v systemctl >/dev/null 2>&1 \
        && systemctl --user show "${PLASMA_SERVICE}" >/dev/null 2>&1; then
        if write_config_file "${PLASMA_OVERRIDE}" "${override_contents}"; then
            printf 'Enabled local configuration reads for Plasma.\n'
        fi
        systemctl --user daemon-reload
        return 0
    fi

    if write_config_file "${PLASMA_ENV_FILE}" "${env_contents}"; then
        printf 'Enabled local configuration reads for Plasma.\n'
    fi
}

command -v kpackagetool6 >/dev/null 2>&1 || {
    printf 'Error: kpackagetool6 is required.\n' >&2
    exit 1
}

[[ -f "${PLASMOID}/metadata.json" && -f "${PLASMOID}/contents/ui/main.qml" ]] || {
    printf 'Error: the Syncthing Monitor package is incomplete.\n' >&2
    exit 1
}

configure_local_file_access

if kpackagetool6 -t Plasma/Applet -u "${PLASMOID}" >/dev/null 2>&1; then
    printf 'Updated Syncthing Monitor.\n'
else
    kpackagetool6 -t Plasma/Applet -i "${PLASMOID}" >/dev/null
    printf 'Installed Syncthing Monitor.\n'
fi

printf 'Add "Syncthing Monitor" from Plasma\047s Add Widgets menu.\n'
printf 'Restarting Plasma...\n'
systemctl --user restart "${PLASMA_SERVICE}"
