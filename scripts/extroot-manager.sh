#!/bin/sh
# TOOL_NAME: Extroot manager
# TOOL_DESC: Validate and maintain overlay/extroot setups
#
# Provides sanity checks and helper actions for systems using extroot.
# It verifies mount health, offers dry-run migration steps, and can
# toggle overlay configuration entries.

set -eu

usage() {
  cat <<'USAGE'
Usage: extroot-manager.sh [OPTIONS]

Options:
  --verify           Run integrity checks on the extroot
  --enable <uuid>    Enable extroot by UUID
  --disable          Disable extroot configuration
  --status           Show current mount and storage status
  --dry-run          Print actions without executing them
  --help             Show this help text
USAGE
}

DRY_RUN=0
ACTION="status"
ARGUMENT=""

while [ $# -gt 0 ]; do
  case $1 in
    --verify)
      ACTION="verify"; shift ;;
    --enable)
      ACTION="enable"; ARGUMENT=$2; shift 2 ;;
    --disable)
      ACTION="disable"; shift ;;
    --status)
      ACTION="status"; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1 ;;
  esac
done

log() {
  printf '[extroot] %s\n' "$*"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: $*"
  else
    log "CMD: $*"
    if ! "$@"; then
      log "ERROR: Command failed ($*)"
      exit 1
    fi
  fi
}

show_status() {
  log "Overlay mount: $(mount | grep 'overlayfs:/overlay' || echo 'not mounted')"
  log "Mounted filesystems:"
  mount
  log "Block device summary:"
  if [ -f /proc/partitions ]; then
    cat /proc/partitions
  else
    log "/proc/partitions not available"
  fi
}

verify_extroot() {
  if [ ! -d /overlay ]; then
    log "Overlay directory missing"
    exit 1
  fi
  if ! mount | grep -q 'overlayfs:/overlay'; then
    log "Overlay not mounted; extroot inactive"
    exit 1
  fi
  log "Overlay is active"
  log "Checking free space"
  df /overlay || true
  log "Scanning for fsck tools"
  if command -v e2fsck >/dev/null 2>&1 && [ -b /dev/root ]; then
    log "Consider running: e2fsck -n /dev/root"
  fi
}

enable_extroot() {
  if [ -z "$ARGUMENT" ]; then
    printf >&2 'Error: --enable requires a block UUID\n'
    exit 1
  fi
  if ! command -v uci >/dev/null 2>&1; then
    log "uci unavailable"
    exit 1
  fi
  run uci -q delete fstab.extroot || true
  run uci set fstab.extroot=mount
  run uci set fstab.extroot.target='/overlay'
  run uci set fstab.extroot.uuid="$ARGUMENT"
  run uci set fstab.extroot.enabled='1'
  run uci commit fstab
  log "Extroot enabled for UUID $ARGUMENT"
}

disable_extroot() {
  if ! command -v uci >/dev/null 2>&1; then
    log "uci unavailable"
    exit 1
  fi
  run uci -q delete fstab.extroot || true
  run uci commit fstab
  log "Extroot configuration removed"
}

case $ACTION in
  status)
    show_status ;;
  verify)
    verify_extroot ;;
  enable)
    enable_extroot ;;
  disable)
    disable_extroot ;;
  *)
    usage
    exit 1 ;;
esac
