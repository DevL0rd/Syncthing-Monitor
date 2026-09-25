#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCH_PACKAGES=(kpackage knotifications qt6-declarative glib2 git)
FEDORA_PACKAGES=(kf6-kpackage kf6-knotifications qt6-qtdeclarative glib2 git libdnf5-plugin-actions)
SUSE_PACKAGES=(kf6-kpackage kf6-knotifications-imports qt6-declarative-imports glib2-tools git)
DEBIAN_PACKAGES=(kpackagetool6 qml6-module-org-kde-notifications qml6-module-qt-labs-folderlistmodel qml6-module-qtquick-shapes qml6-module-qtcore libglib2.0-bin git)
declare -A IMAGE_COMMANDS=(
    [kpackagetool6]="kf6-kpackage kpackage"
)
declare -A IMAGE_QML_MODULES=(
    [org/kde/notification]="kf6-knotifications knotifications"
    [Qt/labs/folderlistmodel]="qt6-qtdeclarative qt6-declarative"
    [QtQuick/Shapes]="qt6-qtdeclarative qt6-declarative"
    [QtCore]="qt6-qtdeclarative qt6-declarative"
)

image_package() {
    local fedora arch
    read -r fedora arch <<<"$1"
    if $STEAMOS; then
        printf '%s\n' "$arch"
    else
        printf '%s\n' "$fedora"
    fi
}

check_image() {
    local name missing=() packages=()
    for name in "${!IMAGE_COMMANDS[@]}"; do
        command -v "$name" >/dev/null && continue
        missing+=("$name")
        packages+=("$(image_package "${IMAGE_COMMANDS[$name]}")")
    done
    for name in "${!IMAGE_QML_MODULES[@]}"; do
        compgen -G "/usr/lib*/qt6/qml/$name/qmldir" >/dev/null && continue
        missing+=("the ${name//\//.} QML module")
        packages+=("$(image_package "${IMAGE_QML_MODULES[$name]}")")
    done
    ((${#missing[@]})) || return 0
    mapfile -t packages < <(printf '%s\n' "${packages[@]}" | LC_ALL=C sort -u)
    printf 'Error: Syncthing Monitor needs %s, which this system does not include.\n' "$(printf '%s, ' "${missing[@]}" | sed 's/, $//')" >&2
    if $STEAMOS; then
        printf 'SteamOS keeps its system read-only and the installer does not unlock it to add %s.\n' "${packages[*]}" >&2
        printf 'Update SteamOS and run ./install.sh again.\n' >&2
    elif command -v rpm-ostree >/dev/null; then
        printf 'The system is read-only, so add them with: rpm-ostree install %s\n' "${packages[*]}" >&2
        printf 'Then reboot and run ./install.sh again.\n' >&2
    else
        printf 'The system is read-only, so add %s to the system image, then run ./install.sh again.\n' "${packages[*]}" >&2
    fi
    exit 1
}

if $ATOMIC_SYSTEM; then
    check_image
elif command -v pacman >/dev/null; then
    update_as_root pacman -S --needed --noconfirm "${ARCH_PACKAGES[@]}"
elif command -v dnf >/dev/null; then
    update_as_root dnf install -y "${FEDORA_PACKAGES[@]}"
elif command -v zypper >/dev/null; then
    update_as_root zypper --non-interactive install "${SUSE_PACKAGES[@]}"
elif command -v apt-get >/dev/null; then
    update_as_root apt-get install -y "${DEBIAN_PACKAGES[@]}"
else
    printf 'Error: unsupported package manager. Install kpackagetool6, the KNotifications QML module and the Qt Quick Shapes, Qt.labs.folderlistmodel and QtCore QML modules, then run ./install.sh --skip-deps\n' >&2
    exit 1
fi
