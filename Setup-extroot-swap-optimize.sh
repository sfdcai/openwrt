#!/bin/sh
#
# Complete OpenWrt Extroot Setup Script
# Follows the proper overlay structure requirements
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
USB_DEVICE="/dev/sda1"
USB_MOUNT="/mnt"
OVERLAY_UPPER="/mnt/upper"
OVERLAY_WORK="/mnt/work"
FSTAB_FILE="/etc/config/fstab"

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_info "Starting complete extroot setup..."

# Step 1: Get USB UUID
print_info "Getting USB device UUID..."
USB_UUID=$(block info | grep "$USB_DEVICE" | sed 's/.*UUID="\([^"]*\)".*/\1/')
if [ -z "$USB_UUID" ]; then
    print_error "Could not get UUID for $USB_DEVICE"
    exit 1
fi
print_success "USB UUID: $USB_UUID"

# Step 2: Ensure proper overlay structure on USB
print_info "Setting up proper overlay structure on USB..."

# Unmount if already mounted
umount "$USB_MOUNT" 2>/dev/null || true

# Mount USB temporarily
print_info "Mounting USB device..."
mount "$USB_DEVICE" "$USB_MOUNT"
if [ $? -ne 0 ]; then
    print_error "Failed to mount USB device"
    exit 1
fi
print_success "USB device mounted at $USB_MOUNT"

# Create overlay directories (mandatory)
print_info "Creating mandatory overlay directories..."
mkdir -p "$OVERLAY_UPPER"
mkdir -p "$OVERLAY_WORK"

if [ -d "$OVERLAY_UPPER" ] && [ -d "$OVERLAY_WORK" ]; then
    print_success "Overlay directories created"
else
    print_error "Failed to create overlay directories"
    exit 1
fi

# Step 3: Copy system files correctly
print_info "Copying overlay contents to upper directory..."
if [ -d "/overlay" ] && [ "$(ls -A /overlay 2>/dev/null)" ]; then
    cp -a /overlay/* "$OVERLAY_UPPER/" 2>/dev/null || true
    print_success "Overlay contents copied"
else
    print_info "No existing overlay contents to copy"
fi

# Show USB structure
print_info "USB structure:"
ls -la "$USB_MOUNT"

# Step 4: Test overlay mount manually
print_info "Testing overlay mount manually..."
umount /overlay 2>/dev/null || true

# Test the overlay mount
mount -t overlay overlay -o lowerdir=/,upperdir="$OVERLAY_UPPER",workdir="$OVERLAY_WORK" /overlay

if [ $? -eq 0 ]; then
    print_success "Manual overlay mount successful"
    
    # Check if overlay is working
    if mount | grep -q overlay; then
        print_success "Overlay is mounted and working"
        df -h | grep overlay
    else
        print_error "Overlay mount failed"
        exit 1
    fi
else
    print_error "Manual overlay mount failed"
    exit 1
fi

# Step 5: Update /etc/config/fstab
print_info "Updating fstab configuration..."

# Backup original fstab
cp "$FSTAB_FILE" "$FSTAB_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Create proper fstab configuration
cat > "$FSTAB_FILE" << EOF
config global
        option anon_swap '0'
        option anon_mount '0'
        option auto_swap '1'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '0'

config mount
        option target '/overlay'
        option uuid '$USB_UUID'
        option fstype 'ext4'
        option options 'noatime,nodiratime,data=writeback'
        option enabled '1'
        option enabled_fsck '0'

EOF

print_success "Fstab updated with correct UUID: $USB_UUID"

# Step 6: Add USB wait at boot
print_info "Adding USB wait at boot..."
if ! grep -q "sleep 5" /etc/rc.local 2>/dev/null; then
    sed -i '/^exit 0$/i sleep 5' /etc/rc.local
    print_success "Boot delay added"
else
    print_info "Boot delay already configured"
fi

# Step 7: Enable fstab
print_info "Enabling fstab service..."
/etc/init.d/fstab enable

print_success "Extroot setup completed successfully!"
print_info "Configuration summary:"
echo "  USB Device: $USB_DEVICE"
echo "  UUID: $USB_UUID"
echo "  Upper Dir: $OVERLAY_UPPER"
echo "  Work Dir: $OVERLAY_WORK"
echo "  Fstab: $FSTAB_FILE"

print_warning "IMPORTANT: Reboot your router now to activate extroot!"
print_info "After reboot, check with:"
echo "  mount | grep overlay"
echo "  df -h | grep overlay"
echo "  ls -la /overlay/"

print_info "To reboot now, run: reboot"
