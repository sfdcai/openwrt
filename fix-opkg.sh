#!/bin/sh

# Script to fix opkg update issues after flashing OpenWrt
# 1. Sets correct system time
# 2. Switches opkg to HTTP, updates, installs ca-certificates
# 3. Reverts to HTTPS and verifies

echo "Starting OpenWrt opkg fix..."

# Step 1: Sync system time with NTP
echo "Synchronizing system time..."
ntpd -q -p pool.ntp.org
if [ $? -eq 0 ]; then
    echo "Time synchronized successfully."
    date
else
    echo "Failed to sync time. Proceeding anyway..."
fi

# Step 2: Backup opkg feeds configuration
echo "Backing up /etc/opkg/distfeeds.conf..."
cp /etc/opkg/distfeeds.conf /etc/opkg/distfeeds.conf.bak

# Step 3: Switch opkg repositories to HTTP
echo "Switching opkg repositories to HTTP..."
sed -i 's/https:/http:/g' /etc/opkg/distfeeds.conf

# Step 4: Run opkg update
echo "Running opkg update with HTTP..."
opkg update
if [ $? -eq 0 ]; then
    echo "opkg update successful."
else
    echo "opkg update failed. Check internet connection or repositories."
    exit 1
fi

# Step 5: Install ca-certificates
echo "Installing ca-certificates..."
opkg install ca-certificates
if [ $? -eq 0 ]; then
    echo "ca-certificates installed successfully."
else
    echo "Failed to install ca-certificates. Check opkg update output."
    exit 1
fi

# Step 6: Restore HTTPS in opkg feeds
echo "Restoring HTTPS in opkg repositories..."
sed -i 's/http:/https:/g' /etc/opkg/distfeeds.conf

# Step 7: Verify opkg update with HTTPS
echo "Verifying opkg update with HTTPS..."
opkg update
if [ $? -eq 0 ]; then
    echo "opkg update with HTTPS successful. Setup complete!"
else
    echo "opkg update with HTTPS failed. Check SSL configuration."
    exit 1
fi

echo "Script completed. Your router's opkg should now work correctly."
