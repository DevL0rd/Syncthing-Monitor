#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 DevL0rd <dmhzmxn@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PLASMOID="${SCRIPT_DIR}/plasmoid/org.devl0rd.syncthingmonitor"

command -v kpackagetool6 >/dev/null 2>&1 || {
    printf 'Error: kpackagetool6 is required.\n' >&2
    exit 1
}

[[ -f "${PLASMOID}/metadata.json" && -f "${PLASMOID}/contents/ui/main.qml" ]] || {
    printf 'Error: the Syncthing Monitor package is incomplete.\n' >&2
    exit 1
}

if kpackagetool6 -t Plasma/Applet -u "${PLASMOID}" >/dev/null 2>&1; then
    printf 'Updated Syncthing Monitor.\n'
else
    kpackagetool6 -t Plasma/Applet -i "${PLASMOID}" >/dev/null
    printf 'Installed Syncthing Monitor.\n'
fi

printf 'Add "Syncthing Monitor" from Plasma\047s Add Widgets menu.\n'
