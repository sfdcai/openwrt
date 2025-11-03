#!/bin/sh
# FINAL OpenWrt USB Extroot Setup (safe for reuse)
# Works on Linksys WRT1900ACS v2 – 2025-11-03

set -e
echo "=== OpenWrt USB Extroot Final Installer ==="

# --- 0) prerequisites ---
for PKG in block-mount e2fsprogs kmod-usb-storage kmod-fs-ext4 parted; do
  opkg status "$PKG" >/dev/null 2>&1 || { echo "Installing $PKG..."; opkg update >/dev/null 2>&1; opkg install "$PKG"; }
done

# --- 1) detect USB ---
USB=$(ls /dev/sd* 2>/dev/null | grep -E '^/dev/sd[a-z]$' | head -n1)
[ -z "$USB" ] && { echo "No /dev/sdX found."; exit 1; }
PART="${USB}1"
echo "[OK] USB detected: $USB"

# --- 2) ensure single ext4 partition ---
if [ ! -e "$PART" ]; then
  echo "Creating new partition..."
  umount ${USB}?* 2>/dev/null || true
  parted -s "$USB" mklabel msdos
  parted -s "$USB" mkpart primary ext4 1MiB 100%
  sleep 2
fi

# --- 3) format if not ext4 ---
FSTYPE=$(block info "$PART" 2>/dev/null | sed -n 's/.*TYPE="\([^"]*\)".*/\1/p')
if [ "$FSTYPE" != "ext4" ]; then
  echo "Formatting $PART as ext4..."
  mkfs.ext4 -F "$PART"
fi

# --- 4) mount and overlay dirs ---
mkdir -p /mnt/usb
mount "$PART" /mnt/usb
mkdir -p /mnt/usb/upper /mnt/usb/work
if [ -z "$(ls -A /mnt/usb/upper 2>/dev/null)" ]; then
  echo "Copying current overlay..."
  cp -a /overlay/* /mnt/usb/upper/ || true
fi

# --- 5) get UUID robustly ---
UUID=$(block info "$PART" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
[ -z "$UUID" ] && UUID=$(tune2fs -l "$PART" 2>/dev/null | awk '/Filesystem UUID/ {print $3}')
[ -z "$UUID" ] && { echo "Could not detect UUID"; exit 1; }
echo "[OK] UUID=$UUID"

# --- 6) write fstab cleanly ---
cat > /etc/config/fstab <<EOF
config global
        option anon_mount '1'
        option check_fs '0'
        option check_media '1'

config mount
        option target '/overlay'
        option uuid '$UUID'
        option fstype 'ext4'
        option options 'rw,sync,noatime,nodiratime,data=writeback'
        option enabled '1'
        option enabled_fsck '1'
EOF
/etc/init.d/fstab enable

# --- 7) rc.local delay ---
grep -q "block mount" /etc/rc.local 2>/dev/null || sed -i '/^exit 0/i sleep 5\n/sbin/block mount || true\nmount -a || true\n' /etc/rc.local

# --- 8) install extroot-watch self-heal ---
cat > /etc/init.d/extroot-watch <<'INIT'
#!/bin/sh /etc/rc.common
START=16
USE_PROCD=1
start_service() {
  LOG=/tmp/extroot-watch.log
  echo "extroot-watch: $(date) start" >>"$LOG"
  if mount | grep -qE '^/dev/sd.1 on /overlay '; then
    echo "extroot-watch: already on USB" >>"$LOG"; return 0; fi
  for i in $(seq 1 10); do
    USB=$(ls /dev/sd* 2>/dev/null | grep -E '^/dev/sd[a-z]$' | head -n1)
    [ -n "$USB" ] && echo 1 > /sys/block/$(basename "$USB")/device/rescan 2>/dev/null || true
    /sbin/block mount >/dev/null 2>&1 || true
    sleep 2
    mount | grep -qE '^/dev/sd.1 on /overlay ' && { echo "extroot-watch: attached on try #$i" >>"$LOG"; return 0; }
  done
  echo "extroot-watch: failed, using internal overlay" >>"$LOG"
}
INIT
chmod +x /etc/init.d/extroot-watch
/etc/init.d/extroot-watch enable

# --- 9) done ---
sync
echo "[SUCCESS] USB extroot configured. Rebooting..."
sleep 5
reboot
