#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 DevL0rd <dmhzmxn@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR
readonly SOURCE_DIR="${SYNCTHING_MONITOR_SOURCE_DIR:-${INSTALL_DIR}}"
readonly INSTALLER_RUNTIME="${XDG_DATA_HOME:-${HOME}/.local/share}/syncthing-monitor/installer"
readonly INSTALL_SUPPORT="${SYNCTHING_MONITOR_INSTALL_SUPPORT:-${INSTALL_DIR}/packaging}"
readonly PLASMOID="${SOURCE_DIR}/plasmoid/org.devl0rd.syncthingmonitor"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly PLASMA_SERVICE="plasma-plasmashell.service"
readonly PLASMA_OVERRIDE_DIR="${CONFIG_HOME}/systemd/user/${PLASMA_SERVICE}.d"
readonly PLASMA_OVERRIDE="${PLASMA_OVERRIDE_DIR}/syncthing-monitor.conf"
readonly PLASMA_ENV_DIR="${CONFIG_HOME}/plasma-workspace/env"
readonly PLASMA_ENV_FILE="${PLASMA_ENV_DIR}/syncthing-monitor.sh"

stage_installer() {
    [[ -f "${SOURCE_DIR}/install.sh" && -f "${SOURCE_DIR}/packaging/lib.sh" ]] || {
        printf 'Error: the Syncthing Monitor installer source is incomplete: %s\n' "${SOURCE_DIR}" >&2
        exit 1
    }
    [[ "${SOURCE_DIR}" == "${INSTALLER_RUNTIME}" ]] && return 0

    local parent temporary previous
    parent="$(dirname -- "${INSTALLER_RUNTIME}")"
    mkdir -p -- "${parent}"
    temporary="$(mktemp -d "${parent}/.installer.XXXXXX")"
    previous="${parent}/.installer.previous.$$"
    mkdir -p -- "${temporary}/packaging"
    install -m755 "${SOURCE_DIR}/install.sh" "${temporary}/install.sh"
    install -m644 "${SOURCE_DIR}/packaging/lib.sh" "${temporary}/packaging/lib.sh"
    if [[ -e "${INSTALLER_RUNTIME}" ]]; then
        mv -- "${INSTALLER_RUNTIME}" "${previous}"
    fi
    mv -- "${temporary}" "${INSTALLER_RUNTIME}"
    rm -rf -- "${previous}"
}

stage_installer
source "${INSTALL_SUPPORT}/lib.sh"

AUR=false
SKIP_DEPS=false
SYSTEM_UPDATE=false
LOGIN_UPDATE=false
[[ ${SYNCTHING_MONITOR_AUR:-} == @(1|true|yes) ]] && AUR=true
for argument in "$@"; do
    case "${argument}" in
    --aur) AUR=true ;;
    --skip-deps) SKIP_DEPS=true ;;
    --system-update) SYSTEM_UPDATE=true ;;
    --login-update) LOGIN_UPDATE=true ;;
    -h | --help)
        printf 'Usage: ./install.sh [--skip-deps] [--aur]\n'
        printf 'Installs Syncthing Monitor and what it needs and, for a git checkout, updates it with every system update.\n'
        printf '  --skip-deps  Do not install dependencies with the system package manager.\n'
        printf '  --aur        Installed by a package (also SYNCTHING_MONITOR_AUR=true); no dependencies are installed and no update hook is registered.\n'
        exit 0
        ;;
    *) printf 'Unknown option: %s\n' "${argument}" >&2; exit 1 ;;
    esac
done
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

if ${LOGIN_UPDATE}; then
    pull_checkout "${SOURCE_DIR}" || exit 0
    stage_installer
    exec env SYNCTHING_MONITOR_SOURCE_DIR="${SOURCE_DIR}" SYNCTHING_MONITOR_INSTALL_SUPPORT="${INSTALLER_RUNTIME}/packaging" \
        "${INSTALLER_RUNTIME}/install.sh" --system-update
fi

if ! ${AUR} && ! ${SKIP_DEPS} && ! ${SYSTEM_UPDATE}; then
    "${SOURCE_DIR}/packaging/dependencies.sh"
fi

command -v kpackagetool6 >/dev/null 2>&1 || {
    printf 'Error: kpackagetool6 is required.\n' >&2
    exit 1
}

[[ -f "${PLASMOID}/metadata.json" && -f "${PLASMOID}/contents/ui/main.qml" ]] || {
    printf 'Error: the Syncthing Monitor package is incomplete.\n' >&2
    exit 1
}

[[ -e "${SOURCE_DIR}/shared/common/PopupShell.qml" ]] || {
    printf 'Error: shared/common (Plasma-Shared submodule) is empty.\n' >&2
    printf 'Run: git submodule update --init --recursive\n' >&2
    exit 1
}

mkdir -p "${PLASMOID}/contents/ui/lib"
cp "${SOURCE_DIR}/shared/common/"*.qml "${SOURCE_DIR}/shared/common/"*.js "${PLASMOID}/contents/ui/lib/"

configure_local_file_access

if kpackagetool6 -t Plasma/Applet -u "${PLASMOID}" >/dev/null 2>&1; then
    printf 'Updated Syncthing Monitor.\n'
else
    kpackagetool6 -t Plasma/Applet -i "${PLASMOID}" >/dev/null
    printf 'Installed Syncthing Monitor.\n'
fi

if ${SYSTEM_UPDATE}; then
    notify_updated "Syncthing Monitor is up to date. Restart Plasma or log out and back in to load the updated widget."
    exit 0
fi
register_system_updates "${SOURCE_DIR}" "${AUR}" "${INSTALLER_RUNTIME}"

printf 'Add "Syncthing Monitor" from Plasma\047s Add Widgets menu.\n'
printf 'Restarting Plasma...\n'
systemctl --user restart "${PLASMA_SERVICE}"
