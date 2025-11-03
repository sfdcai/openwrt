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

hint_for_command() {
  cmd=$1
  case $cmd in
    mount)
      log "Hint: mount failed. Ensure the partition is formatted and not already in use."
      ;;
    mkfs.*)
      log "Hint: format utilities may be missing. Install e2fsprogs or confirm the device is writable."
      ;;
    dd)
      log "Hint: creating the swapfile failed. Check available space on the mount point."
      ;;
    opkg)
      log "Hint: opkg reported an error. Verify network connectivity and repository availability."
      ;;
  esac
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY: $*"
  else
    log "CMD: $*"
    if ! "$@"; then
      status=$?
      log "ERROR($status): Command failed -> $*"
      hint_for_command "$1"
      exit "$status"
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

format_size() {
  blocks=$1
  if [ -z "$blocks" ]; then
    printf 'unknown'
    return
  fi
  awk -v b="$blocks" 'BEGIN {
    mib = b / 1024;
    if (mib >= 1024) {
      printf "%.2f GiB", mib / 1024;
    } else if (mib >= 1) {
      printf "%.0f MiB", mib;
    } else {
      printf "%.0f KiB", b;
    }
  }'
}

read_device_attribute() {
  base=$1
  if [ -z "$base" ]; then
    printf 'unknown'
    return
  fi

  for attr in model name vendor; do
    file="/sys/block/$base/device/$attr"
    if [ -r "$file" ]; then
      value=$(cat "$file" 2>/dev/null | tr '\n' ' ')
      value=$(printf '%s' "$value" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
      if [ -n "$value" ]; then
        printf '%s' "$value"
        return
      fi
    fi
  done

  printf 'unknown'
}

collect_candidates() {
  output=$1
  : >"$output"
  if [ ! -r /proc/partitions ]; then
    return
  fi

  awk '{print $4":"$3}' /proc/partitions 2>/dev/null \
    | while IFS=':' read -r name blocks; do
        case $name in
          sd[a-z][0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*)
            path="/dev/$name"
            [ -b "$path" ] || continue
            size=$(format_size "$blocks")
            mount_point=$(awk -v dev="$path" '$1 == dev {print $2; exit}' /proc/mounts 2>/dev/null)
            [ -n "$mount_point" ] || mount_point="unmounted"
            parent=$(strip_partition_suffix "$path")
            parent_base=$(basename "$parent")
            model=$(read_device_attribute "$parent_base")
            printf '%s|%s|%s|%s\n' "$path" "$size" "$mount_point" "$model" >>"$output"
            ;;
        esac
      done
}

prompt_for_partition() {
  log "No device provided; attempting interactive selection."
  stamp=$(date '+%s' 2>/dev/null || echo 0)
  candidates_file="/tmp/setup-usb-candidates-${stamp}.$$"
  collect_candidates "$candidates_file"
  count=$(sed -n '$=' "$candidates_file" 2>/dev/null || echo 0)
  [ -n "$count" ] || count=0

  if [ "$count" -eq 0 ] 2>/dev/null; then
    rm -f "$candidates_file"
    printf >&2 'Error: no block devices detected. Connect the USB storage and rerun.\n'
    exit 1
  fi

  printf 'Detected storage devices:\n'
  idx=1
  while IFS='|' read -r part size mount_point model; do
    [ -n "$part" ] || continue
    mount_desc=$mount_point
    case $mount_desc in
      ''|unmounted)
        mount_desc='not mounted'
        ;;
      *)
        mount_desc="mounted at $mount_desc"
        ;;
    esac
    if [ -n "$model" ] && [ "$model" != "unknown" ]; then
      printf '  %2d) %s (%s, %s, %s)\n' "$idx" "$part" "$size" "$mount_desc" "$model"
    else
      printf '  %2d) %s (%s, %s)\n' "$idx" "$part" "$size" "$mount_desc"
    fi
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
          candidate_line=$(sed -n "${answer}p" "$candidates_file" 2>/dev/null)
          candidate=$(printf '%s' "$candidate_line" | cut -d '|' -f1)
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

    printf '%s is not a usable block device.\n' "$chosen"
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
  if [ ! -e "$path" ]; then
    log "Device $path not found. Verify the USB drive is connected."
    return 1
  fi
  if [ ! -b "$path" ]; then
    type=$(ls -ld "$path" 2>/dev/null | awk '{print $1}')
    [ -n "$type" ] || type='unknown type'
    log "$path exists but is $type instead of a block device."
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
