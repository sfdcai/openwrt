#!/bin/sh

# Script to install Argon theme on OpenWrt
# Handles dependencies, downloads, installations, and common errors

echo "Starting Argon theme installation..."

# Function to check command success
check_status() {
    if [ $1 -ne 0 ]; then
        echo "Error: $2"
        exit 1
    fi
}

# Step 1: Check internet connectivity
echo "Checking internet connectivity..."
ping -c 2 google.com > /dev/null 2>&1
check_status $? "No internet connection. Please check your network and try again."

# Step 2: Update package lists
echo "Updating package lists..."
opkg update
check_status $? "opkg update failed. Run /root/fix-opkg.sh or check repositories."

# Step 3: Install dependencies
echo "Installing luci and luci-compat..."
opkg install luci luci-compat
check_status $? "Failed to install luci or luci-compat. Check opkg output."

# Step 4: Create temporary directory
echo "Creating temporary directory..."
mkdir -p /tmp/argon
cd /tmp/argon
check_status $? "Failed to create or access /tmp/argon."

# Step 5: Download Argon theme and config packages
echo "Downloading Argon theme and config packages..."
wget -O luci-theme-argon_2.3.1_all.ipk https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.3.1/luci-theme-argon_2.3.1_all.ipk
check_status $? "Failed to download luci-theme-argon. Check URL or internet."
wget -O luci-app-argon-config_0.9_all.ipk https://github.com/jerrykuku/luci-app-argon-config/releases/download/v0.9/luci-app-argon-config_0.9_all.ipk
check_status $? "Failed to download luci-app-argon-config. Check URL or internet."

# Step 6: Verify downloads
echo "Verifying downloaded files..."
[ -f luci-theme-argon_2.3.1_all.ipk ] || { echo "Error: luci-theme-argon_2.3.1_all.ipk not found."; exit 1; }
[ -f luci-app-argon-config_0.9_all.ipk ] || { echo "Error: luci-app-argon-config_0.9_all.ipk not found."; exit 1; }

# Step 7: Install Argon theme
echo "Installing luci-theme-argon..."
opkg install luci-theme-argon_2.3.1_all.ipk
check_status $? "Failed to install luci-theme-argon. Check dependencies."

# Step 8: Install Argon config (optional)
echo "Installing luci-app-argon-config..."
opkg install luci-app-argon-config_0.9_all.ipk
if [ $? -ne 0 ]; then
    echo "Warning: luci-app-argon-config failed to install. Theme will work, but customization may be limited."
else
    echo "luci-app-argon-config installed successfully."
fi

# Step 9: Handle post-install error (missing /etc/uci-defaults/30_luci-theme-argon)
echo "Setting Argon as default theme..."
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
check_status $? "Failed to set Argon as default theme."

# Step 10: Clear LuCI cache
echo "Clearing LuCI cache..."
rm -rf /tmp/luci-*
check_status $? "Failed to clear LuCI cache."

# Step 11: Verify installation
echo "Verifying installation..."
opkg list-installed | grep -q luci-theme-argon
check_status $? "luci-theme-argon not installed correctly."
echo "luci-theme-argon is installed."

# Step 12: Clean up
echo "Cleaning up..."
cd /tmp
rm -rf /tmp/argon
check_status $? "Failed to clean up /tmp/argon."

echo "Argon theme installation completed!"
echo "Access LuCI at http://192.168.1.1, go to System > System > Language and Style, and select 'argon'."
echo "If luci-app-argon-config is installed, customize at System > Argon Config."
