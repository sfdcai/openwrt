#!/bin/sh
# TOOL_NAME: Fix OPKG feeds
# TOOL_DESC: Repair and update package feeds with optional backups
#
# This script automates common recovery steps for the OpenWrt package
# manager. It can rebuild the feeds configuration, switch to HTTP-only
# mirrors, and optionally restore from a backup.

set -eu

LOG_PREFIX="[fix-opkg]"
DEFAULT_FEEDS="https://downloads.openwrt.org"
FEEDS_FILE="/etc/opkg/distfeeds.conf"
BACKUP_DIR="/etc/opkg/backups"
HTTP_ONLY=0

log() {
  level=$1
  shift
  printf '%s %s %s\n' "$LOG_PREFIX" "[$level]" "$*"
}

usage() {
  cat <<'USAGE'
Usage: fix-opkg.sh [OPTIONS]

Options:
  --feeds-url <url>    Override the base feeds URL (default: official)
  --feeds-file <path>  Custom distfeeds.conf path (default: /etc/opkg/distfeeds.conf)
  --ntp <server>       Sync time using the provided NTP server
  --http-only          Replace https feeds with http
  --restore <backup>   Restore feeds from a named backup in /etc/opkg/backups
  --dry-run            Show actions without modifying the system
  --quiet              Reduce log verbosity
  --help               Show this help message
USAGE
}

QUIET=0
DRY_RUN=0
FEEDS_URL=$DEFAULT_FEEDS
NTP_SERVER=""
RESTORE_NAME=""

while [ $# -gt 0 ]; do
  case $1 in
    --feeds-url)
      FEEDS_URL=$2; shift 2 ;;
    --feeds-file)
      FEEDS_FILE=$2; shift 2 ;;
    --ntp)
      NTP_SERVER=$2; shift 2 ;;
    --http-only)
      HTTP_ONLY=1; shift ;;
    --restore)
      RESTORE_NAME=$2; shift 2 ;;
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

maybe_log() {
  if [ "$QUIET" -eq 0 ]; then
    log INFO "$@"
  fi
}

sync_time() {
  [ -n "$NTP_SERVER" ] || return
  if ! command -v ntpd >/dev/null 2>&1; then
    maybe_log "ntpd not found; skipping time sync"
    return
  fi
  maybe_log "Synchronising clock with $NTP_SERVER"
  run ntpd -q -n -p "$NTP_SERVER"
}

create_backup() {
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo timestamp)
  name="${RESTORE_NAME:-feeds-$ts}"
  dest="$BACKUP_DIR/$name"
  if [ -f "$FEEDS_FILE" ]; then
    maybe_log "Saving backup to $dest"
    run mkdir -p "$BACKUP_DIR"
    run cp "$FEEDS_FILE" "$dest"
  else
    maybe_log "Feeds file $FEEDS_FILE not found; skipping backup"
  fi
}

restore_backup() {
  [ -n "$RESTORE_NAME" ] || return
  src="$BACKUP_DIR/$RESTORE_NAME"
  if [ ! -f "$src" ]; then
    log ERROR "Backup $RESTORE_NAME not found in $BACKUP_DIR"
    exit 1
  fi
  maybe_log "Restoring feeds from $src"
  run cp "$src" "$FEEDS_FILE"
}

release_version() {
  if [ -f /etc/openwrt_release ]; then
    grep DISTRIB_RELEASE /etc/openwrt_release | cut -d'=' -f2 | tr -d '"' | head -n1
  else
    echo "snapshots"
  fi
}

target_id() {
  if command -v ubus >/dev/null 2>&1; then
    ubus call system board 2>/dev/null | sed -n 's/.*"target":"\([^"]*\)".*/\1/p' | head -n1
  fi
}

rewrite_feeds() {
  version=$(release_version)
  target=$(target_id)
  maybe_log "Rewriting feeds to use base URL $FEEDS_URL (version: $version)"
  tmp=$(mktemp)
  {
    if [ -n "$target" ]; then
      printf 'src/gz openwrt_core %s/releases/%s/targets/%s/packages\n' "$FEEDS_URL" "$version" "$target"
    fi
    printf 'src/gz openwrt_base %s/releases/%s/packages/%s\n' "$FEEDS_URL" "$version" "$(uname -m 2>/dev/null || echo generic)"
    printf 'src/gz openwrt_luci %s/releases/%s/packages/%s\n' "$FEEDS_URL" "$version" "$(uname -m 2>/dev/null || echo generic)"
    printf 'src/gz openwrt_packages %s/releases/%s/packages/%s\n' "$FEEDS_URL" "$version" "$(uname -m 2>/dev/null || echo generic)"
    printf 'src/gz openwrt_routing %s/releases/%s/packages/%s\n' "$FEEDS_URL" "$version" "$(uname -m 2>/dev/null || echo generic)"
    printf 'src/gz openwrt_telephony %s/releases/%s/packages/%s\n' "$FEEDS_URL" "$version" "$(uname -m 2>/dev/null || echo generic)"
  } >"$tmp"
  if [ "$HTTP_ONLY" -eq 1 ]; then
    maybe_log "Switching feeds to HTTP"
    sed -i 's|https://|http://|g' "$tmp"
  fi
  run mkdir -p "$(dirname "$FEEDS_FILE")"
  run cp "$tmp" "$FEEDS_FILE"
  rm -f "$tmp"
}

refresh_package_lists() {
  if ! command -v opkg >/dev/null 2>&1; then
    maybe_log "opkg not found; skipping update"
    return
  fi
  maybe_log "Updating package lists"
  run opkg update
}

main() {
  sync_time
  if [ -n "$RESTORE_NAME" ]; then
    restore_backup
  else
    create_backup
    rewrite_feeds
  fi
  refresh_package_lists
  maybe_log "OPKG repair routine complete"
}

main "$@"
