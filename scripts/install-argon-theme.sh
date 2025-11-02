#!/bin/sh
# TOOL_NAME: Install Argon Theme
# TOOL_DESC: Install or update the LuCI Argon theme with validation
#
# Provides a safe, configurable installation process for the
# luci-theme-argon package. The script supports offline packages,
# version pinning, and simple post-install checks to confirm that
# the theme is available to LuCI after installation.

set -eu

PKG_NAME="luci-theme-argon"
LOG_PREFIX="[install-argon]"

usage() {
  cat <<'USAGE'
Usage: install-argon-theme.sh [OPTIONS]

Options:
  --version <ver>     Pin to a specific version string
  --offline <path>    Install from a local .ipk package instead of opkg
  --force-reinstall   Reinstall even if the package is present
  --dry-run           Print actions without executing them
  --quiet             Reduce log output
  --help              Show this help message
USAGE
}

DRY_RUN=0
QUIET=0
FORCE=0
VERSION=""
OFFLINE_PKG=""

log() {
  level=$1
  shift
  if [ "$QUIET" -eq 1 ] && [ "$level" = INFO ]; then
    return
  fi
  printf '%s [%s] %s\n' "$LOG_PREFIX" "$level" "$*"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY "$*"
  else
    log CMD "$*"
    if ! "$@"; then
      log ERROR "Command failed: $*"
      exit 1
    fi
  fi
}

package_installed() {
  command -v opkg >/dev/null 2>&1 || return 1
  opkg status "$PKG_NAME" 2>/dev/null | grep -q '^Status: install ok installed'
}

ensure_dependencies() {
  if ! command -v opkg >/dev/null 2>&1; then
    log ERROR "opkg binary not available"
    exit 1
  fi
}

update_repos() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY "opkg update"
    return
  fi
  log INFO "Refreshing package lists"
  opkg update
}

install_online() {
  args="install"
  [ "$FORCE" -eq 1 ] && args="install --force-reinstall"
  if [ -n "$VERSION" ]; then
    pkg="${PKG_NAME}=${VERSION}"
  else
    pkg="$PKG_NAME"
  fi
  run opkg $args "$pkg"
}

install_offline() {
  if [ ! -f "$OFFLINE_PKG" ]; then
    log ERROR "Offline package $OFFLINE_PKG not found"
    exit 1
  fi
  run opkg install "$OFFLINE_PKG"
}

post_checks() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log DRY "Skipping post-install checks"
    return
  fi
  if ! package_installed; then
    log ERROR "$PKG_NAME is not installed after the operation"
    exit 1
  fi
  if [ -d /www/luci-static/argon ]; then
    log INFO "Argon assets present in /www/luci-static/argon"
  else
    log WARNING "Argon assets not found; LuCI may need a restart"
  fi
  log INFO "LuCI themes currently available:"
  if command -v uci >/dev/null 2>&1; then
    uci show luci.themes 2>/dev/null || log WARNING "Unable to query luci.themes"
  else
    log WARNING "uci command unavailable"
  fi
}

while [ $# -gt 0 ]; do
  case $1 in
    --version)
      VERSION=$2; shift 2 ;;
    --offline)
      OFFLINE_PKG=$2; shift 2 ;;
    --force-reinstall)
      FORCE=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --quiet)
      QUIET=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1 ;;
  esac
done

ensure_dependencies

if [ "$FORCE" -eq 0 ] && [ -z "$OFFLINE_PKG" ] && package_installed; then
  log INFO "$PKG_NAME already installed; use --force-reinstall to override"
  exit 0
fi

if [ -n "$OFFLINE_PKG" ]; then
  install_offline
else
  update_repos
  install_online
fi

post_checks
