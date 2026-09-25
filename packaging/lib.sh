#!/usr/bin/env bash

UPDATE_ID="syncthing-monitor"
UPDATE_TITLE="Syncthing Monitor"
UPDATE_UNIT="$UPDATE_ID-update.service"
UPDATE_LOGIN_UNIT="$UPDATE_ID-login-update.service"
UPDATE_LIB_DIR="/usr/lib/$UPDATE_ID"
UPDATE_STATE_DIR="/var/lib/$UPDATE_ID"
UPDATE_USER_STATE_DIR="$HOME/.local/state/$UPDATE_ID"
UPDATE_PENDING="$UPDATE_USER_STATE_DIR/update-pending"
UPDATE_GIT_ENV=(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15")
UPDATE_LEGACY_HOOK="/etc/pacman.d/hooks/$UPDATE_ID-update.hook"
declare -A UPDATE_HOOKS=(
    [pacman]="$UPDATE_ID-update.hook /usr/share/libalpm/hooks/$UPDATE_ID-update.hook 644"
    [dnf]="$UPDATE_ID-update.actions /etc/dnf/libdnf5-plugins/actions.d/$UPDATE_ID-update.actions 644"
    [zypper]="$UPDATE_ID-update.zypp /usr/lib/zypp/plugins/commit/$UPDATE_ID-update 755"
    [apt-get]="$UPDATE_ID-update.apt /etc/apt/apt.conf.d/99$UPDATE_ID-update 644"
)

ATOMIC_SYSTEM=false
STEAMOS=false
if [[ $(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}") == steamos ]]; then
    ATOMIC_SYSTEM=true
    STEAMOS=true
elif [[ -e /run/ostree-booted ]]; then
    ATOMIC_SYSTEM=true
fi

update_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

package_manager() {
    local manager
    for manager in pacman dnf zypper apt-get; do
        if command -v "$manager" >/dev/null; then
            printf '%s\n' "$manager"
            return 0
        fi
    done
    return 1
}

package_owns() {
    case "$(package_manager)" in
    pacman) pacman -Qoq "$1" >/dev/null 2>&1 ;;
    dnf | zypper) rpm -qf "$1" >/dev/null 2>&1 ;;
    apt-get) dpkg -S "$1" >/dev/null 2>&1 ;;
    *) return 0 ;;
    esac
}

remove_empty_directory() {
    [[ -d $1 && -z $(ls -A "$1") ]] || return 0
    if [[ $1 == "$HOME"/* ]]; then
        rmdir "$1"
    elif ! package_owns "$1"; then
        update_as_root rmdir "$1"
    fi
}

install_update_hook() {
    local checkout="$1" manager="$2" source target mode
    read -r source target mode <<<"${UPDATE_HOOKS[$manager]}"
    update_as_root install -Dm644 "$checkout/packaging/lib.sh" "$UPDATE_LIB_DIR/lib.sh"
    update_as_root install -Dm"$mode" "$checkout/packaging/$source" "$target"
    if [[ $manager == pacman ]] && grep -qa 'NetworkAccess' /usr/lib/libalpm.so.* 2>/dev/null; then
        update_as_root sed -i '/^Exec = /a NetworkAccess = allowed' "$target"
    fi
    if [[ -e $UPDATE_LEGACY_HOOK ]]; then
        update_as_root rm -f "$UPDATE_LEGACY_HOOK"
    fi
}

enable_update_unit() {
    local checkout="$1" installer="$2" unit="$3"
    local units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$units"
    sed -e "s|@CHECKOUT@|$checkout|g" \
        -e "s|@INSTALLER@|$installer/install.sh|g" \
        -e "s|@INSTALL_SUPPORT@|$installer/packaging|g" \
        "$checkout/packaging/$unit.in" >"$units/$unit"
    systemctl --user daemon-reload
    systemctl --user enable "$unit" >/dev/null 2>&1
}

disable_update_unit() {
    local unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$1"
    [[ -e $unit ]] || return 1
    systemctl --user disable "$1" >/dev/null 2>&1 || true
    rm -f "$unit"
}

register_system_updates() {
    local checkout="$1" aur="$2" installer="$3" manager
    if [[ $aur == true ]] || ! git -C "$checkout" rev-parse --git-dir >/dev/null 2>&1; then
        unregister_system_updates
        return 0
    fi
    echo "Registering $UPDATE_TITLE with system updates..."
    if $ATOMIC_SYSTEM; then
        enable_update_unit "$checkout" "$installer" "$UPDATE_LOGIN_UNIT"
        return 0
    fi
    if ! manager=$(package_manager); then
        echo "No supported package manager found, so update with: git pull && ./install.sh"
        unregister_system_updates
        return 0
    fi
    update_as_root install -Dm755 "$checkout/packaging/system-update" "$UPDATE_LIB_DIR/system-update"
    install_update_hook "$checkout" "$manager"
    printf '%s\n%s\n' "$checkout" "$(id -un)" | update_as_root install -Dm644 /dev/stdin "$UPDATE_STATE_DIR/source"
    enable_update_unit "$checkout" "$installer" "$UPDATE_UNIT"
}

unregister_system_updates() {
    local entry source target mode reload=false
    for entry in "${UPDATE_HOOKS[@]}" "- $UPDATE_LEGACY_HOOK -"; do
        read -r source target mode <<<"$entry"
        if [[ -e $target ]]; then
            update_as_root rm -f "$target"
            remove_empty_directory "$(dirname "$target")"
        fi
    done
    if [[ -e $UPDATE_STATE_DIR || -e $UPDATE_LIB_DIR ]]; then
        update_as_root rm -rf "$UPDATE_STATE_DIR" "$UPDATE_LIB_DIR"
    fi
    disable_update_unit "$UPDATE_UNIT" && reload=true
    disable_update_unit "$UPDATE_LOGIN_UNIT" && reload=true
    if $reload; then
        systemctl --user daemon-reload
    fi
    rm -f "$UPDATE_PENDING"
    rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/syncthing-monitor/installer"
    remove_empty_directory "${XDG_DATA_HOME:-$HOME/.local/share}/syncthing-monitor"
}

checkout_git() {
    env "${UPDATE_GIT_ENV[@]}" git -C "$1" "${@:2}"
}

pull_checkout() {
    local checkout="$1"
    checkout_git "$checkout" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 || return 1
    if ! checkout_git "$checkout" fetch --quiet; then
        echo "Could not fetch updates for $checkout."
        return 1
    fi
    [[ $(checkout_git "$checkout" rev-list --count 'HEAD..@{upstream}') -gt 0 ]] || return 1
    [[ -z $(checkout_git "$checkout" status --porcelain --untracked-files=no) ]] || return 1
    [[ $(checkout_git "$checkout" rev-list --count '@{upstream}..HEAD') -eq 0 ]] || return 1
    checkout_git "$checkout" merge --ff-only --quiet '@{upstream}' \
        && checkout_git "$checkout" submodule update --init --recursive --quiet
}

notify_updated() {
    rm -f "$UPDATE_PENDING"
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify "$UPDATE_TITLE" 0 system-software-update "$UPDATE_TITLE updated" "$1" '[]' '{}' 10000 >/dev/null 2>&1 || true
}
