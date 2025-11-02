#!/bin/sh
#
# OpenWrt 24.10+ Extroot + Maintenance Utility (Interactive)
# ----------------------------------------------------------
# Adds swap management, filesystem optimisation helpers, and additional
# safety checks to the original menu-driven workflow.

set -e

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ===== Paths and Defaults =====
USB_DEVICE=""
USB_MOUNT="/mnt"
OVERLAY_UPPER="$USB_MOUNT/upper"
OVERLAY_WORK="$USB_MOUNT/work"
SWAP_FILE_DEFAULT="$USB_MOUNT/swapfile"
SWAP_SIZE_MB_DEFAULT=512
FSTAB_FILE="/etc/config/fstab"
OPKG_FEEDS="/etc/opkg/distfeeds.conf"

# ===== Helpers =====

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root."
        exit 1
    fi
}

ensure_usb_selected() {
    if [ -z "$USB_DEVICE" ]; then
        print_warn "No USB device selected yet. Choose option 1 first."
        return 1
    fi
    return 0
}

ensure_mountpoint() {
    mkdir -p "$USB_MOUNT"
    if ! mountpoint -q "$USB_MOUNT"; then
        mount "$USB_DEVICE" "$USB_MOUNT"
        print_info "Mounted $USB_DEVICE at $USB_MOUNT"
    fi
}

append_unique_block() {
    # $1 -> pattern, $2 -> block
    local pattern="$1"
    local block="$2"

    if grep -q "$pattern" "$FSTAB_FILE" 2>/dev/null; then
        return 0
    fi

    printf '\n%s\n' "$block" >> "$FSTAB_FILE"
}

# ===== Core Actions =====

auto_detect_usb() {
    print_info "Detecting available USB partitions..."
    USB_LIST=$(lsblk -lnpo NAME,SIZE,TYPE | grep 'part' | grep '/dev/sd' | awk '{print $1 " (" $2 ")"}')
    if [ -z "$USB_LIST" ]; then
        print_error "No USB partitions detected!"
        return 1
    fi

    echo "Available USB devices:"
    echo "$USB_LIST"
    echo
    read -r -p "Enter the USB device path (e.g., /dev/sda1): " USB_DEVICE
    if [ ! -b "$USB_DEVICE" ]; then
        print_error "Invalid device: $USB_DEVICE"
        USB_DEVICE=""
        return 1
    fi
    print_success "Using USB device: $USB_DEVICE"
}

format_usb() {
    ensure_usb_selected || return 1

    print_warn "⚠️  This will ERASE all data on $USB_DEVICE."
    read -r -p "Do you want to format $USB_DEVICE as ext4? (yes/no): " CONFIRM
    if [ "$CONFIRM" = "yes" ]; then
        umount "$USB_DEVICE" 2>/dev/null || true
        print_info "Formatting $USB_DEVICE as ext4..."
        mkfs.ext4 -F "$USB_DEVICE"
        print_success "$USB_DEVICE formatted successfully."
    else
        print_info "Skipping format step."
    fi
}

setup_extroot() {
    ensure_usb_selected || return 1

    print_info "Starting extroot setup..."

    USB_UUID=$(block info | grep "$USB_DEVICE" | sed 's/.*UUID="\([^"]*\)".*/\1/')
    if [ -z "$USB_UUID" ]; then
        print_error "Could not detect UUID for $USB_DEVICE"
        return 1
    fi
    print_success "Detected UUID: $USB_UUID"

    ensure_mountpoint

    mkdir -p "$OVERLAY_UPPER" "$OVERLAY_WORK"
    print_success "Overlay structure prepared."

    if [ -d "/overlay" ] && [ "$(ls -A /overlay 2>/dev/null)" ]; then
        print_info "Copying current overlay to USB..."
        cp -a /overlay/* "$OVERLAY_UPPER/" 2>/dev/null || true
        print_success "Overlay data copied."
    fi

    umount /overlay 2>/dev/null || true
    if mount -t overlay overlay -o "lowerdir=/,upperdir=$OVERLAY_UPPER,workdir=$OVERLAY_WORK" /overlay; then
        print_success "Overlay mounted successfully."
    else
        print_error "Overlay test mount failed."
        return 1
    fi

    print_info "Writing fstab..."
    cat > "$FSTAB_FILE" <<EOF
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

    print_success "fstab configured for extroot."

    if ! grep -q "sleep 5" /etc/rc.local 2>/dev/null; then
        sed -i '/^exit 0$/i sleep 5' /etc/rc.local
        print_success "Added boot delay for USB initialization."
    fi

    /etc/init.d/fstab enable
    print_success "fstab service enabled."

    print_warn "✅ Extroot setup completed! Reboot to activate."
    echo "After reboot, verify with:"
    echo "  mount | grep overlay"
    echo "  df -h | grep overlay"
}

ensure_swap_entry() {
    local swap_path="$1"
    append_unique_block "option device '$swap_path'" "config swap\n        option device '$swap_path'\n        option enabled '1'\n        option priority '1'"
}

create_swap() {
    ensure_usb_selected || return 1

    ensure_mountpoint

    local swap_file="$SWAP_FILE_DEFAULT"
    local swap_size="$SWAP_SIZE_MB_DEFAULT"

    read -r -p "Swap file path [$swap_file]: " input_path
    if [ -n "$input_path" ]; then
        swap_file="$input_path"
    fi

    read -r -p "Swap size in MB [$swap_size]: " input_size
    if [ -n "$input_size" ]; then
        if echo "$input_size" | grep -qE '^[0-9]+$'; then
            swap_size="$input_size"
        else
            print_error "Invalid size."
            return 1
        fi
    fi

    if [ -f "$swap_file" ]; then
        print_warn "Existing swap file found. It will be recreated."
        swapoff "$swap_file" 2>/dev/null || true
    fi

    print_info "Creating swap file ($swap_size MB) at $swap_file"
    dd if=/dev/zero of="$swap_file" bs=1M count="$swap_size"
    chmod 600 "$swap_file"
    mkswap "$swap_file"
    swapon "$swap_file" || print_warn "Swap activation failed."

    ensure_swap_entry "$swap_file"
    print_success "Swap file configured."
}

optimize_system() {
    if ! ensure_usb_selected; then
        print_warn "Select a USB device first to run optimisation commands."
        return 0
    fi
    print_info "Applying filesystem optimisations..."

    if command -v tune2fs >/dev/null 2>&1; then
        tune2fs -o journal_data_writeback "$USB_DEVICE" >/dev/null 2>&1 || true
    fi

    if command -v sysctl >/dev/null 2>&1; then
        sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
        sysctl -w vm.vfs_cache_pressure=200 >/dev/null 2>&1 || true
    fi

    print_success "Optimisation commands applied."
}

fix_opkg() {
    print_info "Fixing opkg HTTPS issues..."

    ntpd -q -p pool.ntp.org || print_warn "NTP sync failed, continuing."

    sed -i 's/https:/http:/g' "$OPKG_FEEDS"
    if opkg update; then
        print_success "opkg update (HTTP) completed."
    else
        print_error "HTTP update failed."
        return 1
    fi

    if opkg install ca-certificates; then
        print_success "ca-certificates installed."
    else
        print_error "Failed to install ca-certificates."
    fi

    sed -i 's/http:/https:/g' "$OPKG_FEEDS"
    if opkg update; then
        print_success "opkg update (HTTPS) verified."
    else
        print_warn "HTTPS update failed to verify."
    fi
}

show_info() {
    echo
    echo "System Info:"
    echo "============"
    df -h | grep overlay || echo "Overlay not mounted yet."
    block info | grep UUID || echo "No block device UUID found."
    swapon --show || echo "No swap active."
    echo
    echo "fstab content:"
    echo "---------------"
    cat "$FSTAB_FILE"
}

show_summary() {
    echo
    echo "Current Configuration Summary"
    echo "------------------------------"
    echo "Selected USB device : ${USB_DEVICE:-<not selected>}"
    mountpoint -q "$USB_MOUNT" && echo "USB mount point     : $USB_MOUNT" || echo "USB mount point     : not mounted"
    [ -d "$OVERLAY_UPPER" ] && echo "Overlay upper dir   : $OVERLAY_UPPER" || echo "Overlay upper dir   : missing"
    [ -d "$OVERLAY_WORK" ] && echo "Overlay work dir    : $OVERLAY_WORK" || echo "Overlay work dir    : missing"
    SWAP_INFO=$(swapon --show 2>/dev/null | awk 'NR>1 {print $1" ("$3")"}')
    if [ -n "$SWAP_INFO" ]; then
        echo "Active swap         : $SWAP_INFO"
    else
        echo "Active swap         : none"
    fi
}

# ===== Menu =====
show_menu() {
    echo
    echo "=============================================="
    echo " OpenWrt 24.10+ System Utility"
    echo "=============================================="
    echo "1) Auto-detect USB device"
    echo "2) Format USB (ext4)"
    echo "3) Setup Extroot (overlay)"
    echo "4) Create or refresh swap file"
    echo "5) Fix opkg HTTPS & install certs"
    echo "6) Apply optimisation tweaks"
    echo "7) Show system info"
    echo "8) Show configuration summary"
    echo "9) Reboot"
    echo "0) Exit"
    echo "=============================================="
    echo
}

main_loop() {
    while true; do
        show_menu
        read -r -p "Select an option: " CHOICE
        case "$CHOICE" in
            1) auto_detect_usb ;;
            2) format_usb ;;
            3) setup_extroot ;;
            4) create_swap ;;
            5) fix_opkg ;;
            6) optimize_system ;;
            7) show_info ;;
            8) show_summary ;;
            9) print_info "Rebooting..."; reboot ;;
            0) print_info "Exiting."; exit 0 ;;
            *) print_warn "Invalid option. Try again." ;;
        esac
        echo
    done
}

require_root
main_loop
