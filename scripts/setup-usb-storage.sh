#!/bin/sh
# TOOL_NAME: USB storage helper
# TOOL_DESC: Prepare and mount USB storage with swap support
#
# Prepares an existing USB partition for use as data or overlay storage,
# optionally formats it, provisions a swap file, and registers persistent
# mounts via /etc/config/fstab. The workflow favours core BusyBox utilities
# so it works on stock OpenWrt 24.10 installations.

set -eu

usage() {
  cat <<'USAGE'
Usage: setup-usb-storage.sh [OPTIONS]

Options:
  --device <path>        Block device or partition (e.g. /dev/sda1)
  --partition <path>     Explicit partition path (overrides automatic guess)
  --mount <dir>          Mount point to create/update (default: /mnt/<partition>)
  --swap <size>          Swap size in MiB to allocate (default: 256, 0 disables)
  --fs <type>            Filesystem type when formatting (default: ext4)
  --format               Format the partition before mounting
  --install-packages     Ensure usbutils and luci-app-advanced-reboot are installed
  --dry-run              Show actions without executing them
  --help                 Display this message

Examples:
  setup-usb-storage.sh --device /dev/sda1 --mount /mnt/usb
  setup-usb-storage.sh --device /dev/sda --format --swap 512
USAGE
}

DEVICE=""
PARTITION=""
MOUNT_POINT=""
SWAP_SIZE=256
FS_TYPE="ext4"
DRY_RUN=0
DO_FORMAT=0
TARGET_PART=""
INSTALL_PACKAGES=0

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

strip_partition_suffix() {
  path=$1
  case $path in
    *p[0-9]*)
      printf '%s' "${path%p[0-9]*}"
      ;;
    *[0-9])
      printf '%s' "${path%[0-9]*}"
      ;;
    *)
      printf '%s' "$path"
      ;;
  esac
}

guess_partition_path() {
  disk=$1
  if [ -b "${disk}p1" ]; then
    printf '%s\n' "${disk}p1"
  elif [ -b "${disk}1" ]; then
    printf '%s\n' "${disk}1"
  else
    # Return the most common suffix; caller will validate existence later.
    case $disk in
      *mmcblk*|*nvme*) printf '%sp1\n' "$disk" ;;
      *) printf '%s1\n' "$disk" ;;
    esac
  fi
}

list_block_candidates() {
  ls -1 /dev 2>/dev/null \
    | egrep '^(sd[a-z][0-9]*|mmcblk[0-9]+(p[0-9]+)?|nvme[0-9]+n[0-9]+(p[0-9]+)?)$' \
    | while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      printf '/dev/%s\n' "$entry"
    done
}

prompt_for_partition() {
  log "No device provided; attempting interactive selection."
  stamp=$(date '+%s' 2>/dev/null || echo 0)
  candidates_file="/tmp/setup-usb-candidates-${stamp}.$$"
  list_block_candidates >"$candidates_file"
  count=$(sed -n '$=' "$candidates_file")
  [ -n "$count" ] || count=0

  if [ "$count" -eq 0 ] 2>/dev/null; then
    rm -f "$candidates_file"
    printf >&2 'Error: no block devices detected. Connect the USB storage and rerun.\n'
    exit 1
  fi

  printf 'Detected storage devices:\n'
  idx=1
  while IFS= read -r part; do
    [ -n "$part" ] || continue
    printf '  %2d) %s\n' "$idx" "$part"
    idx=$((idx + 1))
  done <"$candidates_file"

  while true; do
    candidate=""
    printf '\nSelect a device [1-%s], enter a path, or type q to cancel: ' "$count"
    IFS= read -r answer || {
      rm -f "$candidates_file"
      exit 1
    }

    case $answer in
      [Qq])
        rm -f "$candidates_file"
        log "Aborted by user."
        exit 0
        ;;
      '')
        continue
        ;;
      *[!0-9]*)
        candidate=$(printf '%s' "$answer" | tr -d ' \t')
        ;;
      *)
        if [ "$answer" -ge 1 ] 2>/dev/null && [ "$answer" -le "$count" ] 2>/dev/null; then
          candidate=$(sed -n "${answer}p" "$candidates_file")
        else
          printf 'Invalid selection.\n'
          continue
        fi
        ;;
    esac

    [ -n "$candidate" ] || continue

    case $candidate in
      /dev/*)
        chosen=$candidate
        ;;
      *)
        if [ -b "/dev/$candidate" ]; then
          chosen="/dev/$candidate"
        else
          printf 'Path %s is not recognised.\n' "$candidate"
          candidate=""
          continue
        fi
        ;;
    esac

    if ensure_block_present "$chosen"; then
      PARTITION=$chosen
      DEVICE=$(strip_partition_suffix "$chosen")
      log "Selected partition $PARTITION"
      rm -f "$candidates_file"
      return
    fi

    printf '%s is not a block device.\n' "$chosen"
  done
}

while [ $# -gt 0 ]; do
  case $1 in
    --device)
      DEVICE=$2
      shift 2
      ;;
    --partition)
      PARTITION=$2
      shift 2
      ;;
    --mount)
      MOUNT_POINT=$2
      shift 2
      ;;
    --swap)
      SWAP_SIZE=$2
      shift 2
      ;;
    --fs)
      FS_TYPE=$2
      shift 2
      ;;
    --format)
      DO_FORMAT=1
      shift
      ;;
    --install-packages)
      INSTALL_PACKAGES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1
      ;;
  esac
done

case $SWAP_SIZE in
  ''|*[!0-9]*)
    printf >&2 'Error: --swap expects a numeric size in MiB.\n'
    exit 1
    ;;
  *)
    :
    ;;
esac

resolve_targets() {
  if [ -n "$PARTITION" ]; then
    TARGET_PART=$PARTITION
    if [ -z "$DEVICE" ]; then
      DEVICE=$(strip_partition_suffix "$PARTITION")
    fi
  else
    if [ -z "$DEVICE" ]; then
      printf >&2 'Error: unable to determine device path.\n'
      exit 1
    fi
    case $DEVICE in
      *[0-9])
        TARGET_PART=$DEVICE
        DEVICE=$(strip_partition_suffix "$DEVICE")
        ;;
      *)
        TARGET_PART=$(guess_partition_path "$DEVICE")
        ;;
    esac
  fi
}

ensure_block_present() {
  path=$1
  if [ ! -b "$path" ]; then
    return 1
  fi
  return 0
}

format_partition() {
  if [ "$DO_FORMAT" -eq 0 ]; then
    log "Skipping filesystem format; use --format to wipe $TARGET_PART if required."
    return
  fi
  mkfs_tool="mkfs.$FS_TYPE"
  if ! command -v "$mkfs_tool" >/dev/null 2>&1; then
    log "$mkfs_tool not found. Install the appropriate filesystem utilities (e.g. e2fsprogs)."
    exit 1
  fi
  run "$mkfs_tool" "$TARGET_PART"
}

mount_filesystem() {
  if [ -z "$MOUNT_POINT" ]; then
    name=$(basename "$TARGET_PART")
    MOUNT_POINT="/mnt/$name"
    log "Using default mount point $MOUNT_POINT"
  fi
  run mkdir -p "$MOUNT_POINT"
  run mount "$TARGET_PART" "$MOUNT_POINT"
  if command -v uci >/dev/null 2>&1; then
    log "Persisting mount in /etc/config/fstab"
    run uci -q delete fstab.usb || true
    run uci set fstab.usb=mount
    run uci set fstab.usb.target="$MOUNT_POINT"
    run uci set fstab.usb.device="$TARGET_PART"
    run uci set fstab.usb.enabled='1'
    run uci commit fstab
  fi
}

provision_swap() {
  [ "$SWAP_SIZE" -gt 0 ] 2>/dev/null || return
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

summarise() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry-run complete"
  else
    log "USB storage setup finished"
    df "$MOUNT_POINT" 2>/dev/null || true
  fi
}

ensure_usb_support_packages() {
  if [ "$INSTALL_PACKAGES" -ne 1 ]; then
    return
  fi
  if ! command -v opkg >/dev/null 2>&1; then
    log "opkg not available; skipping USB support package installation."
    return
  fi

  missing_packages=""
  for pkg in usbutils luci-app-advanced-reboot; do
    if ! opkg list-installed "$pkg" 2>/dev/null | grep -q "^$pkg -"; then
      missing_packages="$missing_packages $pkg"
    fi
  done

  if [ -z "$missing_packages" ]; then
    log "USB support packages already installed."
    return
  fi

  run opkg update
  for pkg in $missing_packages; do
    run opkg install "$pkg"
  done
}

if [ -z "$DEVICE" ] && [ -z "$PARTITION" ]; then
  prompt_for_partition
fi

resolve_targets
if ! ensure_block_present "$TARGET_PART"; then
  log "Partition $TARGET_PART not found. Create it on another system or specify --partition."
  exit 1
fi
ensure_usb_support_packages
format_partition
mount_filesystem
provision_swap
summarise
