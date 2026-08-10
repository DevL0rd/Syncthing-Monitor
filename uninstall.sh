#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 DevL0rd <dmhzmxn@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly PLASMOID_ID="org.devl0rd.syncthingmonitor"

command -v kpackagetool6 >/dev/null 2>&1 || {
    printf 'Error: kpackagetool6 is required.\n' >&2
    exit 1
}

if kpackagetool6 -t Plasma/Applet -r "${PLASMOID_ID}" >/dev/null 2>&1; then
    printf 'Uninstalled Syncthing Monitor.\n'
else
    printf 'Syncthing Monitor is not installed.\n'
fi
