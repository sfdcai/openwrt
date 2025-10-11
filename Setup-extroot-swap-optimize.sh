#!/bin/sh
# setup-extroot-swap-optimize.sh
# Interactive script to configure extroot (USB as /overlay), swap (file or zram),
# noatime optimization and install Argon LuCI theme (latest release) on OpenWrt.
# Tested on Linksys WRT1900ACS v2 (OpenWrt). Run as root.

set -e

LOG() { printf "[+] %s\n" "$1"; }
ERR() { printf "[!] %s\n" "$1"; }

# Helpers
exists() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  printf "%s [y/N]: " "$1"
  read ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect USB device (defaults to /dev/sda1 if present)
detect_usb() {
  if [ -b /dev/sda1 ]; then
    echo "/dev/sda1"
    return 0
  fi
  # fallback: list /dev/sd* and pick first partition
  for d in /dev/sd*1; do
    [ -b "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}

# Ensure required packages
ensure_packages() {
  opkg update
  for pkg in block-mount kmod-usb-storage kmod-fs-ext4 e2fsprogs usbutils fdisk; do
    if ! opkg list-installed | grep -q "^$pkg "; then
      LOG "Installing $pkg"
      opkg install "$pkg" || ERR "Failed to install $pkg (continue if already available)"
    fi
  done
}

# Format partition ext4
format_ext4() {
  dev="$1"
  LOG "Formatting $dev as ext4 (this will erase data)"
  umount "$dev" 2>/dev/null || true
  mkfs.ext4 -F "$dev"
}

# Mount to temporary mountpoint
mount_temp() {
  dev="$1"
  mnt="$2"
  mkdir -p "$mnt"
  mount "$dev" "$mnt"
}

# Copy overlay content
copy_overlay_to_usb() {
  mnt="$1"
  LOG "Copying current overlay to $mnt"
  # ensure overlay exists
  if [ -d /overlay ] && [ "$(ls -A /overlay 2>/dev/null)" ]; then
    tar -C /overlay -cf - . | tar -C "$mnt" -xvf -
  else
    LOG "/overlay is empty — creating minimal overlay structure"
    mkdir -p "$mnt/upper" "$mnt/work"
  fi
}

# Update /etc/config/fstab for extroot
configure_fstab_extroot() {
  uuid="$1"
  cat > /etc/config/fstab <<EOF
config global
	option  anon_swap       '0'
	option  anon_mount      '0'
	option  auto_swap       '1'
	option  auto_mount      '1'
	option  delay_root      '5'
	option  check_fs        '0'

config mount
	option target  '/overlay'
	option uuid    '$uuid'
	option fstype  'ext4'
	option enabled '1'
	option enabled_fsck '1'
EOF
  LOG "/etc/config/fstab updated for extroot"
}

# Enable fstab and reboot
enable_fstab_and_reboot() {
  /etc/init.d/fstab enable || true
  LOG "Rebooting now..."
  reboot
}

# Create swapfile
create_swapfile() {
  mnt="$1"
  size_mb="$2"
  swapfile="$mnt/swapfile"
  LOG "Creating swapfile $swapfile of ${size_mb}MB"
  dd if=/dev/zero of="$swapfile" bs=1M count="$size_mb" || true
  mkswap "$swapfile"
  swapon "$swapfile"
  # add to fstab as swap
  uci -q delete fstab.@swap[0]
  uci set fstab.swap0=device="$swapfile"
  uci set fstab.swap0.enabled='1'
  uci commit fstab
  /etc/init.d/fstab restart || true
  LOG "Swapfile enabled"
}

# Setup zram
setup_zram() {
  if ! opkg list-installed | grep -q zram-swap; then
    LOG "Installing zram-swap"
    opkg update
    opkg install zram-swap || ERR "Failed to install zram-swap"
  fi
  /etc/init.d/zram-swap enable || true
  /etc/init.d/zram-swap start || true
  LOG "zram-swap started"
}

# Add noatime option to ext4 fstab entry (on /etc/config/fstab we don't specify mount options easily)
# We'll also add a /etc/fstab entry to ensure noatime for /overlay device after block mount
add_noatime_to_fstab() {
  # Find device by uuid and write to /etc/fstab
  uuid="$1"
  devline=$(blkid -U "$uuid" 2>/dev/null || true)
  if [ -n "$devline" ]; then
    # Write /etc/fstab static line
    echo "UUID=$uuid /overlay ext4 defaults,noatime 0 1" > /etc/fstab
    LOG "/etc/fstab written with noatime for UUID $uuid"
  else
    ERR "Could not resolve UUID to device — skipping /etc/fstab noatime write"
  fi
}

# Install Argon theme (fetch latest release from GitHub - jerrykuku/luci-theme-argon)
install_argon_theme_latest() {
  LOG "Attempting to fetch latest Argon Luci theme release from GitHub"
  apiurl="https://api.github.com/repos/jerrykuku/luci-theme-argon/releases/latest"
  tmpjson="/tmp/argon_release.json"
  wget -qO "$tmpjson" "$apiurl" || { ERR "Failed to fetch GitHub API"; return 1; }
  # Extract asset URLs for luci-theme-argon and luci-app-argon-config
  # Try to find .ipk or .apk assets
  theme_url=$(grep -o 'https://[^" ]*luci-theme-argon[^" ]*' "$tmpjson" | head -n1)
  app_url=$(grep -o 'https://[^" ]*luci-app-argon-config[^" ]*' "$tmpjson" | head -n1)
  if [ -z "$theme_url" ]; then
    ERR "Could not find theme asset in release JSON"
    return 1
  fi
  cd /tmp
  LOG "Downloading $theme_url"
  wget --no-check-certificate -qO luci-theme-argon.pkg "$theme_url" || ERR "download failed"
  if [ -n "$app_url" ]; then
    LOG "Downloading $app_url"
    wget --no-check-certificate -qO luci-app-argon-config.pkg "$app_url" || true
  fi
  # attempt install
  for f in luci-*.pkg luci-*.ipk luci-*.apk; do
    [ -f "$f" ] && { opkg install "$f" || true; }
  done
  LOG "Attempted Argon installation - check LuCI -> System -> Language and Style"
}

# MAIN MENU
main_menu() {
  echo "OpenWrt Extroot + Swap + Optimizer - Interactive"
  echo "Detected USB device: $(detect_usb || echo 'none')"
  echo "Current mounts:"
  df -h
  echo
  echo "Choose actions (type numbers separated by spaces):"
  echo "1) Configure extroot (copy overlay -> USB and switch to /overlay)"
  echo "2) Format USB as ext4 (destructive)"
  echo "3) Create swapfile on USB (select size)"
  echo "4) Enable zram-swap"
  echo "5) Add noatime optimization to /etc/fstab"
  echo "6) Install Argon LuCI theme (latest release)"
  echo "7) Apply basic performance tweaks (disable unused services, install useful packages)"
  echo "8) Exit"

  read -p "Selection: " sel
  for choice in $sel; do
    case "$choice" in
      1)
        dev=$(detect_usb) || { ERR "No USB detected"; exit 1; }
        LOG "Will prepare extroot on $dev"
        ensure_packages
        mount_tmp="/mnt/usb"
        format_choice="no"
        if confirm "Do you want to FORMAT $dev (this will erase it)?"; then
          format_choice="yes"
        fi
        if [ "$format_choice" = "yes" ]; then
          format_ext4 "$dev"
        fi
        mount_temp "$dev" "$mount_tmp"
        copy_overlay_to_usb "$mount_tmp"
        # get uuid
        if exists blkid; then
          uuid=$(blkid -s UUID -o value "$dev" || true)
        else
          uuid=$(cat /proc/partitions | grep -m1 $(basename "$dev") || true)
        fi
        if [ -z "$uuid" ]; then
          # try block info
          uuid=$(block info | grep $(basename "$dev") -A1 | grep UUID | sed -n 's/.*UUID="\([^"]*\)".*/\1/p' || true)
        fi
        if [ -z "$uuid" ]; then
          ERR "Could not determine UUID — aborting extroot configuration"
        else
          configure_fstab_extroot "$uuid"
          LOG "Extroot configured. Enable fstab and reboot to switch to USB overlay"
          if confirm "Reboot now?"; then
            enable_fstab_and_reboot
          fi
        fi
        ;;
      2)
        dev=$(detect_usb) || { ERR "No USB detected"; exit 1; }
        if confirm "Really FORMAT $dev as ext4? All data will be lost"; then
          ensure_packages
          format_ext4 "$dev"
          LOG "Done. You should now copy overlay or mount it where you need"
        fi
        ;;
      3)
        dev=$(detect_usb) || { ERR "No USB detected"; exit 1; }
        mount_tmp="/mnt/usb"
        mount_temp "$dev" "$mount_tmp"
        echo "Choose swap size in MB (recommended 256 or 512). Enter number:"
        read size_mb
        create_swapfile "$mount_tmp" "$size_mb"
        ;;
      4)
        setup_zram
        ;;
      5)
        dev=$(detect_usb) || { ERR "No USB detected"; exit 1; }
        if exists blkid; then
          uuid=$(blkid -s UUID -o value "$dev" || true)
        else
          uuid=$(block info | grep $(basename "$dev") -A1 | grep UUID | sed -n 's/.*UUID="\([^"]*\)".*/\1/p' || true)
        fi
        if [ -n "$uuid" ]; then
          add_noatime_to_fstab "$uuid"
        else
          ERR "Cannot find UUID for noatime"
        fi
        ;;
      6)
        install_argon_theme_latest
        ;;
      7)
        LOG "Applying basic performance tweaks"
        # Example: disable unused services (customize as needed)
        /etc/init.d/uhttpd disable || true
        /etc/init.d/rpcd disable || true
        # Install useful lightweight packages
        opkg update
        opkg install luci-app-opkg luci-app-statistics collectd-mod-network luci-app-nlbwmon || true
        LOG "Tweaks applied. Review services and installed packages."
        ;;
      8)
        LOG "Exit requested"
        exit 0
        ;;
      *)
        ERR "Unknown option $choice"
        ;;
    esac
  done
}

# Run main menu
main_menu
