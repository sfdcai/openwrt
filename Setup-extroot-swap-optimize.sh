#!/bin/sh
#
# Advanced OpenWrt extroot and swap helper
# ----------------------------------------
# Adds command line options, swap management, filesystem checks, and
# optional dry-run support to the basic extroot automation script.

set -eu

# ===== Colours =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { printf "%s[INFO]%s %s\n" "$BLUE" "$NC" "$1"; }
success() { printf "%s[SUCCESS]%s %s\n" "$GREEN" "$NC" "$1"; }
warn()    { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$1"; }
error()   { printf "%s[ERROR]%s %s\n" "$RED" "$NC" "$1" >&2; }

# ===== Defaults =====
USB_DEVICE="/dev/sda1"
USB_MOUNT="/mnt"
OVERLAY_UPPER="$USB_MOUNT/upper"
OVERLAY_WORK="$USB_MOUNT/work"
TEST_MOUNT="$USB_MOUNT/test-overlay"
FSTAB_FILE="/etc/config/fstab"
BACKUP_DIR="/etc/config"
SWAP_FILE="$USB_MOUNT/swapfile"
SWAP_SIZE_MB=512
CREATE_SWAP=1
KEEP_MOUNT=0
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: Setup-extroot-swap-optimize.sh [options]

Options:
  -d, --device PATH        Block device to use for extroot (default: /dev/sda1)
  -m, --mount PATH         Temporary mount point for preparing the device (default: /mnt)
      --swap-file PATH     Path for the swap file (default: /mnt/swapfile)
      --swap-size MB       Swap file size in megabytes (default: 512)
      --no-swap            Skip swap file creation
      --keep-mounted       Leave the USB device mounted after completion
      --dry-run            Show the actions without executing them
  -h, --help               Show this help message

Examples:
  Setup-extroot-swap-optimize.sh --device /dev/sdb1 --swap-size 1024
  Setup-extroot-swap-optimize.sh --no-swap --dry-run
EOF
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        info "[DRY-RUN] $*"
        return 0
    fi

    "$@"
}

safe_umount() {
    if [ "$DRY_RUN" -eq 1 ]; then
        info "[DRY-RUN] umount $1"
        return 0
    fi
    umount "$1" >/dev/null 2>&1 || true
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root."
        exit 1
    fi
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -d|--device)
                [ $# -lt 2 ] && { error "Missing value for $1"; exit 1; }
                USB_DEVICE="$2"
                shift 2
                ;;
            -m|--mount)
                [ $# -lt 2 ] && { error "Missing value for $1"; exit 1; }
                USB_MOUNT="$2"
                OVERLAY_UPPER="$USB_MOUNT/upper"
                OVERLAY_WORK="$USB_MOUNT/work"
                TEST_MOUNT="$USB_MOUNT/test-overlay"
                shift 2
                ;;
            --swap-file)
                [ $# -lt 2 ] && { error "Missing value for $1"; exit 1; }
                SWAP_FILE="$2"
                shift 2
                ;;
            --swap-size)
                [ $# -lt 2 ] && { error "Missing value for $1"; exit 1; }
                SWAP_SIZE_MB="$2"
                shift 2
                ;;
            --no-swap)
                CREATE_SWAP=0
                shift
                ;;
            --keep-mounted)
                KEEP_MOUNT=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

validate_inputs() {
    if [ ! -b "$USB_DEVICE" ] && [ "$DRY_RUN" -eq 0 ]; then
        error "$USB_DEVICE is not a valid block device."
        exit 1
    fi

    if ! printf '%s' "$SWAP_SIZE_MB" | grep -qE '^[0-9]+$'; then
        error "Swap size must be an integer value."
        exit 1
    fi
}

mount_device() {
    info "Mounting $USB_DEVICE at $USB_MOUNT"
    run_cmd mkdir -p "$USB_MOUNT"
    safe_umount "$USB_MOUNT"
    safe_umount "$USB_DEVICE"
    run_cmd mount "$USB_DEVICE" "$USB_MOUNT"
    success "USB device mounted at $USB_MOUNT"
}

prepare_overlay_dirs() {
    info "Preparing overlay directories"
    run_cmd mkdir -p "$OVERLAY_UPPER" "$OVERLAY_WORK"
    success "Overlay directories ready"
}

copy_overlay_contents() {
    if [ -d "/overlay" ] && [ "$(ls -A /overlay 2>/dev/null)" ]; then
        info "Copying current overlay contents"
        run_cmd cp -a /overlay/* "$OVERLAY_UPPER/"
        success "Overlay data copied"
    else
        warn "No existing overlay data to copy"
    fi
}

test_overlay_mount() {
    info "Testing overlay mount at $TEST_MOUNT"
    run_cmd mkdir -p "$TEST_MOUNT"
    run_cmd mount -t overlay overlay -o "lowerdir=/,upperdir=$OVERLAY_UPPER,workdir=$OVERLAY_WORK" "$TEST_MOUNT"
    if [ "$DRY_RUN" -eq 0 ]; then
        if mount | grep -q "$TEST_MOUNT"; then
            success "Overlay mount test succeeded"
        else
            error "Overlay mount verification failed"
            exit 1
        fi
        run_cmd umount "$TEST_MOUNT"
        run_cmd rmdir "$TEST_MOUNT"
    fi
}

backup_fstab() {
    [ "$DRY_RUN" -eq 1 ] && return
    if [ -f "$FSTAB_FILE" ]; then
        local backup="$BACKUP_DIR/fstab.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$FSTAB_FILE" "$backup"
        info "fstab backup saved to $backup"
    fi
}

configure_fstab() {
    info "Writing fstab entry"
    backup_fstab
    cat <<EOF | run_cmd tee "$FSTAB_FILE" >/dev/null
config global
        option anon_swap '0'
        option anon_mount '0'
        option auto_swap '1'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '1'

config mount
        option target '/overlay'
        option uuid '$USB_UUID'
        option fstype 'ext4'
        option options 'rw,noatime,nodiratime,data=writeback'
        option enabled '1'
        option enabled_fsck '1'
EOF
    success "fstab updated"
}

get_uuid() {
    block info | grep "$USB_DEVICE" | sed 's/.*UUID="\([^"]*\)".*/\1/'
}

ensure_uuid() {
    if [ "$DRY_RUN" -eq 1 ]; then
        USB_UUID="DRY-RUN-UUID"
        warn "Dry-run mode: skipping UUID lookup."
        return
    fi
    info "Reading UUID from $USB_DEVICE"
    USB_UUID=$(get_uuid)
    if [ -z "$USB_UUID" ]; then
        error "Unable to determine UUID for $USB_DEVICE"
        exit 1
    fi
    success "USB UUID: $USB_UUID"
}

append_swap_to_fstab() {
    [ "$CREATE_SWAP" -eq 1 ] || return
    if [ "$DRY_RUN" -eq 0 ] && grep -q "option device '$SWAP_FILE'" "$FSTAB_FILE" 2>/dev/null; then
        warn "Swap entry already exists in fstab. Skipping append."
        return
    fi
    cat <<EOF | run_cmd tee -a "$FSTAB_FILE" >/dev/null

config swap
        option device '$SWAP_FILE'
        option enabled '1'
        option priority '1'
EOF
    success "Swap entry added to fstab"
}

create_swap_file() {
    [ "$CREATE_SWAP" -eq 1 ] || { warn "Swap creation skipped."; return; }
    info "Creating swap file at $SWAP_FILE (${SWAP_SIZE_MB}MB)"
    run_cmd dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB"
    run_cmd chmod 600 "$SWAP_FILE"
    run_cmd mkswap "$SWAP_FILE"
    if [ "$DRY_RUN" -eq 0 ]; then
        swapon "$SWAP_FILE" >/dev/null 2>&1 && success "Swap activated" || warn "Swap activation deferred"
    fi
}

apply_optimisations() {
    info "Applying filesystem and kernel tuning"
    if command -v tune2fs >/dev/null 2>&1; then
        if ! run_cmd tune2fs -o journal_data_writeback "$USB_DEVICE"; then
            warn "tune2fs optimisation failed."
        fi
    fi
    if command -v sysctl >/dev/null 2>&1; then
        if ! run_cmd sysctl -w vm.swappiness=10; then
            warn "Unable to set vm.swappiness."
        fi
        if ! run_cmd sysctl -w vm.vfs_cache_pressure=200; then
            warn "Unable to set vm.vfs_cache_pressure."
        fi
    fi
    success "Optimisation commands issued"
}

enable_services() {
    info "Enabling fstab init script"
    run_cmd /etc/init.d/fstab enable

    if ! grep -q "sleep 5" /etc/rc.local 2>/dev/null; then
        run_cmd sed -i '/^exit 0$/i sleep 5' /etc/rc.local
        success "Boot delay added to rc.local"
    else
        warn "Boot delay already configured"
    fi
}

cleanup_mounts() {
    if [ "$KEEP_MOUNT" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        safe_umount "$USB_MOUNT"
    fi
}

summary() {
    echo
    echo "Summary"
    echo "-------"
    echo "USB device : $USB_DEVICE"
    echo "UUID       : $USB_UUID"
    echo "Upper dir  : $OVERLAY_UPPER"
    echo "Work dir   : $OVERLAY_WORK"
    echo "Swap file  : $( [ "$CREATE_SWAP" -eq 1 ] && echo "$SWAP_FILE" || echo 'disabled')"
    echo "fstab      : $FSTAB_FILE"
    echo
    warn "Reboot is required to activate the new extroot."
    info "After reboot run: mount | grep overlay"
    info "               df -h | grep overlay"
}

main() {
    parse_args "$@"
    ensure_root
    validate_inputs

    info "Starting extroot + swap configuration"
    ensure_uuid
    mount_device
    prepare_overlay_dirs
    copy_overlay_contents
    test_overlay_mount
    configure_fstab
    append_swap_to_fstab
    create_swap_file
    apply_optimisations
    enable_services
    cleanup_mounts
    summary
}

main "$@"
