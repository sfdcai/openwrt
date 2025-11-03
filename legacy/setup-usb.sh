#!/bin/sh
#
# OpenWrt 24.10+ Extroot + opkg Fix Utility (Menu Driven)
# Features:
#   - Auto detect and format USB
#   - Create proper overlay structure
#   - Configure fstab and overlay mount
#   - Fix opkg HTTPS update issues
#   - Minimal design (no backups, no rollback)
#
# Author: Amit + GPT-5 Optimization
# Version: 3.1 (2025-10)
#

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

# ===== Paths =====
USB_MOUNT="/mnt"
OVERLAY_UPPER="$USB_MOUNT/upper"
OVERLAY_WORK="$USB_MOUNT/work"
FSTAB_FILE="/etc/config/fstab"
OPKG_FEEDS="/etc/opkg/distfeeds.conf"

# ===== Functions =====

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
    read -p "Enter the USB device path (e.g., /dev/sda1): " USB_DEVICE
    if [ ! -b "$USB_DEVICE" ]; then
        print_error "Invalid device: $USB_DEVICE"
        return 1
    fi
    print_success "Using USB device: $USB_DEVICE"
}

format_usb() {
    print_warn "⚠️ This will ERASE all data on $USB_DEVICE."
    read -p "Do you want to format $USB_DEVICE as ext4? (yes/no): " CONFIRM
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
    print_info "Starting extroot setup..."

    # Get UUID
    USB_UUID=$(block info | grep "$USB_DEVICE" | sed 's/.*UUID="\([^"]*\)".*/\1/')
    [ -z "$USB_UUID" ] && { print_error "Could not detect UUID for $USB_DEVICE"; return 1; }

    print_success "Detected UUID: $USB_UUID"

    # Mount
    mkdir -p "$USB_MOUNT"
    umount "$USB_MOUNT" 2>/dev/null || true
    mount "$USB_DEVICE" "$USB_MOUNT"
    print_success "USB mounted at $USB_MOUNT"

    # Overlay dirs
    mkdir -p "$OVERLAY_UPPER" "$OVERLAY_WORK"
    print_success "Overlay structure prepared."

    # Copy existing overlay
    if [ -d "/overlay" ] && [ "$(ls -A /overlay 2>/dev/null)" ]; then
        print_info "Copying current overlay to USB..."
        cp -a /overlay/* "$OVERLAY_UPPER/" 2>/dev/null || true
        print_success "Overlay data copied."
    fi

    # Test overlay mount
    umount /overlay 2>/dev/null || true
    mount -t overlay overlay -o lowerdir=/,upperdir="$OVERLAY_UPPER",workdir="$OVERLAY_WORK" /overlay && \
        print_success "Overlay mounted successfully." || \
        { print_error "Overlay test mount failed."; return 1; }

    # Update fstab
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

    print_success "fstab configured successfully."

    # Add USB wait
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

fix_opkg() {
    print_info "Fixing opkg HTTPS issues..."

    ntpd -q -p pool.ntp.org || print_warn "NTP sync failed, continuing."

    sed -i 's/https:/http:/g' "$OPKG_FEEDS"
    opkg update || { print_error "HTTP update failed."; return 1; }

    opkg install ca-certificates || print_error "Failed to install ca-certificates."
    sed -i 's/http:/https:/g' "$OPKG_FEEDS"
    opkg update && print_success "opkg HTTPS verified!" || print_warn "HTTPS check failed."
}

show_info() {
    echo
    echo "System Info:"
    echo "============"
    df -h | grep overlay || echo "Overlay not mounted yet."
    block info | grep UUID || echo "No block device UUID found."
    echo
    echo "fstab content:"
    echo "---------------"
    cat "$FSTAB_FILE"
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
    echo "4) Fix opkg HTTPS & install certs"
    echo "5) Show system info"
    echo "6) Reboot"
    echo "0) Exit"
    echo "=============================================="
    echo
}

while true; do
    show_menu
    read -p "Select an option: " CHOICE
    case "$CHOICE" in
        1) auto_detect_usb ;;
        2) format_usb ;;
        3) setup_extroot ;;
        4) fix_opkg ;;
        5) show_info ;;
        6) print_info "Rebooting..."; reboot ;;
        0) print_info "Exiting."; exit 0 ;;
        *) print_warn "Invalid option. Try again." ;;
    esac
    echo
done
