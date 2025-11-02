#!/bin/sh

# Flexible installer for the Argon LuCI theme
# -------------------------------------------
# Adds version selection, offline installation support, and better validation.

set -eu

DEFAULT_THEME_VERSION="2.3.1"
DEFAULT_CONFIG_VERSION="0.9"
PING_TARGET="openwrt.org"

THEME_VERSION="$DEFAULT_THEME_VERSION"
CONFIG_VERSION="$DEFAULT_CONFIG_VERSION"
THEME_URL=""
CONFIG_URL=""
WORK_DIR=""
USER_WORK_DIR=""
KEEP_DOWNLOADS=0
SKIP_NETWORK_CHECK=0
OFFLINE_DIR=""

COLOR_INFO='\033[0;34m'
COLOR_SUCCESS='\033[0;32m'
COLOR_WARN='\033[1;33m'
COLOR_ERROR='\033[0;31m'
COLOR_RESET='\033[0m'

log() {
    printf "%s[INFO]%s %s\n" "$COLOR_INFO" "$COLOR_RESET" "$1"
}

log_success() {
    printf "%s[SUCCESS]%s %s\n" "$COLOR_SUCCESS" "$COLOR_RESET" "$1"
}

log_warn() {
    printf "%s[WARN]%s %s\n" "$COLOR_WARN" "$COLOR_RESET" "$1"
}

log_error() {
    printf "%s[ERROR]%s %s\n" "$COLOR_ERROR" "$COLOR_RESET" "$1" >&2
}

usage() {
    cat <<'EOF'
Usage: install-argon.sh [options]

Install the Argon LuCI theme and optional configuration package.

Options:
  -t, --theme-version VERSION   Theme package version (default: 2.3.1)
  -c, --config-version VERSION  Config package version (default: 0.9)
      --theme-url URL           Override download URL for the theme package
      --config-url URL          Override download URL for the config package
      --offline-dir PATH        Use pre-downloaded IPK files from PATH
      --work-dir PATH           Directory for temporary downloads (default: /tmp/argon-install.<pid>)
      --keep-downloads          Preserve downloaded files after installation
      --skip-network-check      Skip connectivity test (useful for offline installs)
  -h, --help                    Show this help message

Examples:
  install-argon.sh
  install-argon.sh --theme-version 2.3.2 --config-version 0.9.1
  install-argon.sh --offline-dir /mnt/usb/ipk --skip-network-check
EOF
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root."
        exit 1
    fi
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Required command '$1' is not available."
        exit 1
    fi
}

cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ] && [ "$KEEP_DOWNLOADS" -eq 0 ] && [ "$WORK_DIR" != "$USER_WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

download_with_fallback() {
    local url="$1"
    local dest="$2"

    if command -v wget >/dev/null 2>&1; then
        if ! wget -O "$dest" "$url"; then
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! curl -L -o "$dest" "$url"; then
            return 1
        fi
    else
        log_error "Neither wget nor curl is available for downloads."
        return 1
    fi

    return 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--theme-version)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                THEME_VERSION="$2"
                shift 2
                ;;
            -c|--config-version)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                CONFIG_VERSION="$2"
                shift 2
                ;;
            --theme-url)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                THEME_URL="$2"
                shift 2
                ;;
            --config-url)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                CONFIG_URL="$2"
                shift 2
                ;;
            --offline-dir)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                OFFLINE_DIR="$2"
                shift 2
                ;;
            --work-dir)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                USER_WORK_DIR="$2"
                shift 2
                ;;
            --keep-downloads)
                KEEP_DOWNLOADS=1
                shift
                ;;
            --skip-network-check)
                SKIP_NETWORK_CHECK=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

validate_offline_dir() {
    if [ -z "$OFFLINE_DIR" ]; then
        return
    fi

    if [ ! -d "$OFFLINE_DIR" ]; then
        log_error "Offline directory $OFFLINE_DIR does not exist."
        exit 1
    fi
}

compute_urls() {
    if [ -z "$THEME_URL" ]; then
        THEME_URL="https://github.com/jerrykuku/luci-theme-argon/releases/download/v${THEME_VERSION}/luci-theme-argon_${THEME_VERSION}_all.ipk"
    fi

    if [ -z "$CONFIG_URL" ]; then
        CONFIG_URL="https://github.com/jerrykuku/luci-app-argon-config/releases/download/v${CONFIG_VERSION}/luci-app-argon-config_${CONFIG_VERSION}_all.ipk"
    fi
}

ensure_connectivity() {
    if [ "$SKIP_NETWORK_CHECK" -eq 1 ]; then
        log_warn "Skipping network connectivity test."
        return
    fi

    log "Checking internet connectivity via $PING_TARGET..."
    if ping -c 2 "$PING_TARGET" >/dev/null 2>&1; then
        log_success "Network connectivity verified."
    else
        log_error "Unable to reach $PING_TARGET. Use --skip-network-check if installing offline."
        exit 1
    fi
}

opkg_install() {
    local description="$1"
    shift
    if ! opkg install "$@"; then
        log_error "Failed to install $description"
        exit 1
    fi
    log_success "$description installed."
}

prepare_workdir() {
    if [ -n "$USER_WORK_DIR" ]; then
        mkdir -p "$USER_WORK_DIR"
        WORK_DIR="$USER_WORK_DIR"
    else
        WORK_DIR="/tmp/argon-install.$$"
        mkdir -p "$WORK_DIR"
    fi
}

copy_from_offline() {
    local package_name="$1"
    local destination="$2"
    local source_path="$OFFLINE_DIR/$package_name"

    if [ ! -f "$source_path" ]; then
        log_error "Offline package $source_path not found."
        exit 1
    fi

    cp "$source_path" "$destination"
}

download_packages() {
    local theme_file="luci-theme-argon_${THEME_VERSION}_all.ipk"
    local config_file="luci-app-argon-config_${CONFIG_VERSION}_all.ipk"

    if [ -n "$OFFLINE_DIR" ]; then
        log "Using offline packages from $OFFLINE_DIR"
        copy_from_offline "$theme_file" "$WORK_DIR/$theme_file"
        if [ -f "$OFFLINE_DIR/$config_file" ]; then
            copy_from_offline "$config_file" "$WORK_DIR/$config_file"
        else
            log_warn "Offline config package not found. Continuing without luci-app-argon-config."
        fi
        return
    fi

    log "Downloading Argon theme version $THEME_VERSION"
    if ! download_with_fallback "$THEME_URL" "$WORK_DIR/$theme_file"; then
        log_error "Failed to download theme package from $THEME_URL"
        exit 1
    fi

    log "Downloading Argon config version $CONFIG_VERSION"
    if ! download_with_fallback "$CONFIG_URL" "$WORK_DIR/$config_file"; then
        log_warn "Config package download failed. Theme will be installed without configuration UI."
        rm -f "$WORK_DIR/$config_file"
    fi
}

install_theme_and_config() {
    local theme_file="$WORK_DIR/luci-theme-argon_${THEME_VERSION}_all.ipk"
    local config_file="$WORK_DIR/luci-app-argon-config_${CONFIG_VERSION}_all.ipk"

    if [ ! -f "$theme_file" ]; then
        log_error "Theme package $theme_file not found."
        exit 1
    fi

    opkg_install "luci-theme-argon" "$theme_file"

    if [ -f "$config_file" ]; then
        if opkg install "$config_file" >/dev/null 2>&1; then
            log_success "luci-app-argon-config installed."
        else
            log_warn "Failed to install luci-app-argon-config. You can retry manually using: opkg install $config_file"
        fi
    else
        log_warn "Config package not available. Skipping."
    fi
}

configure_luci() {
    log "Setting Argon as the default LuCI theme"
    uci set luci.main.mediaurlbase='/luci-static/argon'
    uci commit luci
    log_success "LuCI default theme updated to Argon."
}

clear_cache() {
    log "Clearing LuCI cache"
    rm -rf /tmp/luci-*
}

verify_install() {
    if opkg list-installed | grep -q "luci-theme-argon"; then
        log_success "Argon theme installation verified."
    else
        log_error "luci-theme-argon not found in installed packages."
        exit 1
    fi
}

main() {
    trap cleanup EXIT INT TERM

    parse_args "$@"
    require_root
    require_command opkg
    require_command uci
    validate_offline_dir
    compute_urls

    if [ -z "$OFFLINE_DIR" ]; then
        ensure_connectivity
    fi

    log "Refreshing package lists"
    opkg update

    log "Ensuring LuCI dependencies are present"
    opkg_install "LuCI core packages" luci luci-compat

    prepare_workdir

    download_packages

    install_theme_and_config

    configure_luci

    clear_cache

    verify_install

    log_success "Argon theme installation completed."
    log "Access LuCI at http://192.168.1.1 (System → System → Language and Style) to confirm the Argon theme."
}

main "$@"
