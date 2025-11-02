#!/bin/sh
# TOOL_NAME: USB storage helper
# TOOL_DESC: Prepare and mount USB storage with swap support
#
# This script assists with preparing a USB device for use as a storage
# expansion or extroot precursor. It can create partitions, format the
# device, provision swap, and add entries to /etc/config/fstab.

set -eu

usage() {
  cat <<'USAGE'
Usage: setup-usb-storage.sh [OPTIONS]

Options:
  --device <path>     Block device (e.g. /dev/sda)
  --mount <dir>       Mount point to create/update
  --swap <size>       Swap size in MiB to allocate (0 to disable)
  --fs <type>         Filesystem type for the data partition (default: ext4)
  --dry-run           Show actions without executing them
  --help              Display this message

Example:
  setup-usb-storage.sh --device /dev/sda --mount /mnt/usb --swap 512
USAGE
}

DEVICE=""
MOUNT_POINT=""
SWAP_SIZE=256
FS_TYPE="ext4"
DRY_RUN=0

log() {
  printf '[setup-usb] %s\n' "$*"
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

while [ $# -gt 0 ]; do
  case $1 in
    --device)
      DEVICE=$2; shift 2 ;;
    --mount)
      MOUNT_POINT=$2; shift 2 ;;
    --swap)
      SWAP_SIZE=$2; shift 2 ;;
    --fs)
      FS_TYPE=$2; shift 2 ;;
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

if [ -z "$DEVICE" ]; then
  printf >&2 'Error: --device is required\n'
  usage
  exit 1
fi

if [ -z "$MOUNT_POINT" ]; then
  MOUNT_POINT="/mnt/$(basename "$DEVICE")"
  log "Using default mount point $MOUNT_POINT"
fi

prepare_partitions() {
  if ! command -v parted >/dev/null 2>&1; then
    log "parted not available; skipping partitioning"
    return
  fi
  run parted -s "$DEVICE" mklabel gpt
  run parted -s "$DEVICE" mkpart primary "$FS_TYPE" 1MiB 100%
}

format_partition() {
  part="${DEVICE}1"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: mkfs.$FS_TYPE $part"
  else
    if ! command -v "mkfs.$FS_TYPE" >/dev/null 2>&1; then
      log "mkfs.$FS_TYPE not found"
      exit 1
    fi
    run "mkfs.$FS_TYPE" "$part"
  fi
}

provision_swap() {
  [ "$SWAP_SIZE" -gt 0 ] 2>/dev/null || return
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: Creating swapfile of ${SWAP_SIZE}MiB on $MOUNT_POINT"
    return
  fi
  run mkdir -p "$MOUNT_POINT"
  swapfile="$MOUNT_POINT/swapfile"
  run dd if=/dev/zero of="$swapfile" bs=1M count="$SWAP_SIZE"
  run chmod 600 "$swapfile"
  run mkswap "$swapfile"
  if command -v swapon >/dev/null 2>&1; then
    run swapon "$swapfile"
  fi
  if command -v uci >/dev/null 2>&1; then
    log "Registering swapfile in /etc/config/fstab"
    run uci -q delete fstab.swap || true
    run uci set fstab.swap=swap
    run uci set fstab.swap.enabled='1'
    run uci set fstab.swap.device="$swapfile"
    run uci commit fstab
  fi
}

mount_filesystem() {
  part="${DEVICE}1"
  run mkdir -p "$MOUNT_POINT"
  run mount "$part" "$MOUNT_POINT"
  if command -v uci >/dev/null 2>&1; then
    log "Persisting mount in /etc/config/fstab"
    run uci -q delete fstab.usb || true
    run uci set fstab.usb=mount
    run uci set fstab.usb.target="$MOUNT_POINT"
    run uci set fstab.usb.device="$part"
    run uci set fstab.usb.enabled='1'
    run uci commit fstab
  fi
}

summarise() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run complete"
  else
    log "USB storage setup finished"
    df -h "$MOUNT_POINT" 2>/dev/null || true
  fi
}

prepare_partitions
format_partition
mount_filesystem
provision_swap
summarise
