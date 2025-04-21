Below is a `README.md` file for the `fix-opkg.sh` script you requested. It provides clear instructions and context for using the script on your OpenWrt router (like your Linksys device running OpenWrt 24.10.0 on `mvebu/cortexa9`). The `README.md` is written in Markdown format, suitable for viewing on GitHub, a personal repository, or any Markdown-supported platform.

---

# OpenWrt opkg Fix Script

## Overview

The `fix-opkg.sh` script resolves common `opkg update` errors on OpenWrt routers caused by SSL verification issues or incorrect system time. It automates:
- Synchronizing the system time using NTP.
- Temporarily switching `opkg` repositories to HTTP.
- Updating package lists and installing `ca-certificates`.
- Restoring HTTPS repositories for secure package downloads.
- Verifying the fix.

This script is designed for OpenWrt 24.10.0 (and similar versions) on devices like Linksys routers with `mvebu/cortexa9` architecture but should work on other OpenWrt setups.

## Prerequisites

- **OpenWrt Router**: Running OpenWrt (e.g., version 24.10.0).
- **Internet Access**: The router must be connected to the internet (test with `ping google.com`).
- **SSH Access**: Ability to log in to the router via SSH (e.g., `ssh root@192.168.1.1`).
- **Root Privileges**: The script must be run as `root`.

## Usage

1. **Log in to Your Router**:
   ```
   ssh root@192.168.1.1
   ```

2. **Create the Script**:
   - Copy the `fix-opkg.sh` script to your router.
   - Create the file:
     ```
     vi /root/fix-opkg.sh
     ```
   - Paste the script content, save, and exit (`:wq`).

   Alternatively, transfer the script from your computer:
   ```
   scp fix-opkg.sh root@192.168.1.1:/root/
   ```

3. **Make the Script Executable**:
   ```
   chmod +x /root/fix-opkg.sh
   ```

4. **Run the Script**:
   ```
   /root/fix-opkg.sh
   ```

5. **Check Output**:
   - The script displays progress (time sync, `opkg update`, etc.).
   - On success, it confirms that `opkg update` works with HTTPS.
   - If errors occur, review the output for details.

6. **Optional Cleanup**:
   If storage is limited, remove the script after use:
   ```
   rm /root/fix-opkg.sh
   ```

## Script Details

The script performs the following steps:
1. **Time Sync**: Uses `ntpd` to set the correct time via `pool.ntp.org`.
2. **Backup Config**: Saves `/etc/opkg/distfeeds.conf` as `distfeeds.conf.bak`.
3. **Switch to HTTP**: Modifies `opkg` repositories from `https` to `http`.
4. **Update and Install**: Runs `opkg update` and installs `ca-certificates`.
5. **Restore HTTPS**: Reverts repositories to `https`.
6. **Verify**: Runs `opkg update` again to ensure SSL works.

## Example Output

```
Starting OpenWrt opkg fix...
Synchronizing system time...
Time synchronized successfully.
Mon Apr 14 12:34:56 UTC 2025
Backing up /etc/opkg/distfeeds.conf...
Switching opkg repositories to HTTP...
Running opkg update with HTTP...
opkg update successful.
Installing ca-certificates...
ca-certificates installed successfully.
Restoring HTTPS in opkg repositories...
Verifying opkg update with HTTPS...
opkg update with HTTPS successful. Setup complete!
Script completed. Your router's opkg should now work correctly.
```

## Troubleshooting

- **No Internet**: If `ping google.com` fails, check your router’s network configuration.
- **Time Sync Failure**: Ensure `pool.ntp.org` is accessible or try another NTP server (e.g., `time.google.com`).
- **opkg Update Fails**: Verify repository URLs in `/etc/opkg/distfeeds.conf`. Check the OpenWrt forum (https://forum.openwrt.org/) for mirror URLs.
- **Storage Issues**: Check free space with `df -h`. Clear temporary files with `rm -rf /tmp/*`.
- **Restore Backup**: If the script fails, restore the original config:
  ```
  mv /etc/opkg/distfeeds.conf.bak /etc/opkg/distfeeds.conf
  ```

## Notes

- **Security**: The script uses HTTP temporarily but reverts to HTTPS for secure package downloads. Avoid leaving HTTP enabled.
- **Compatibility**: Tested on OpenWrt 24.10.0 (`mvebu/cortexa9`, `armv7l`). For other versions, check repository URLs.
- **Storage**: The script is small (~1 KB). Keep it on your computer or a USB drive for reuse after flashing.
- **Router Model**: Tailored for Linksys routers but generic. Specify your model (e.g., WRT1900ACS) for targeted support.

## License

This script is provided as-is, free to use and modify. No warranty is implied.

## Support

For issues, consult:
- OpenWrt Forum: https://forum.openwrt.org/
- OpenWrt Bug Tracker: https://bugs.openwrt.org/

---

### How to Add the `README.md`

1. **Create on Router** (if you want it there temporarily):
   ```
   vi /root/README.md
   ```
   Paste the content above, save, and exit (`:wq`).

2. **Store Locally** (recommended):
   - Save the `README.md` and `fix-opkg.sh` in a folder on your computer (e.g., `~/openwrt-scripts/`).
   - Example:
     ```
     mkdir ~/openwrt-scripts
     cd ~/openwrt-scripts
     touch README.md fix-opkg.sh
     ```
   - Copy the `README.md` content into `README.md` and the script into `fix-opkg.sh` using your preferred editor.

3. **Transfer to Router** (when needed):
   ```
   scp ~/openwrt-scripts/fix-opkg.sh root@192.168.1.1:/root/
   ```

4. **Optional Git Repository**:
   If you use GitHub or another Git service:
   - Initialize a repository:
     ```
     git init
     git add README.md fix-opkg.sh
     git commit -m "Add OpenWrt opkg fix script and README"
     ```
   - Push to your remote repository for easy access.

### Notes
- The `README.md` is self-contained and explains everything for future use, even if you share it with others.
- If you flash your router often, keeping `README.md` and `fix-opkg.sh` together in a local folder or repo simplifies setup.
- If you share your Linksys model (e.g., WRT1900ACS), I can add model-specific notes to the `README.md`.

# OpenWrt Argon Theme Installation Script

## Overview

The `install-argon.sh` script automates the installation of the Argon theme (`luci-theme-argon`) and its configuration app (`luci-app-argon-config`) on OpenWrt routers. The Argon theme provides a modern, customizable interface for the LuCI web administration panel. The script handles:

- Checking internet connectivity.
- Updating package lists and installing dependencies (`luci`, `luci-compat`).
- Downloading and installing Argon theme packages from GitHub.
- Setting Argon as the default theme.
- Clearing LuCI caches and cleaning up temporary files.
- Error handling for common issues (e.g., connectivity, dependencies, download failures, post-install errors).

This script is tailored for OpenWrt 24.10.0 on Linksys routers with `mvebu/cortexa9` architecture (`armv7l`) but is compatible with other OpenWrt setups with minor adjustments.

## Prerequisites

- **OpenWrt Router**: Running OpenWrt 24.10.0 or a similar stable release.

- **Internet Access**: Router must have internet connectivity (test with `ping google.com`).

- **SSH Access**: Ability to log in via SSH (e.g., `ssh root@192.168.1.1`).

- **Root Privileges**: Script must be executed as the `root` user.

- **Storage Space**: Approximately 1-2 MB free on `/overlay` (check with `df -h`).

- **opkg Functionality**: Ensure `opkg update` works. If it fails, run the `fix-opkg.sh` script (see Troubleshooting).

- **Backup (Recommended)**: Back up your configuration before making changes:

  ```bash
  sysupgrade -b /tmp/backup.tar.gz
  ```

## Installation

1. **Log in to Your Router**:

   ```bash
   ssh root@192.168.1.1
   ```

2. **Create the Script**:

   ```bash
   vi /root/install-argon.sh
   ```

   Paste the `install-argon.sh` script content, save, and exit (`:wq`).

   Alternatively, transfer the script from your computer:

   ```bash
   scp ~/openwrt-scripts/install-argon.sh root@192.168.1.1:/root/
   ```

3. **Make the Script Executable**:

   ```bash
   chmod +x /root/install-argon.sh
   ```

4. **Run the Script**:

   ```bash
   /root/install-argon.sh
   ```

5. **Apply the Theme**:

   - Open the LuCI web interface (e.g., http://192.168.1.1).
   - Navigate to **System &gt; System &gt; Language and Style**.
   - Set **Design** to `argon`.
   - Click **Save & Apply**.
   - Refresh the browser to view the Argon theme.

6. **Optional: Customize the Theme**: If `luci-app-argon-config` is installed:

   - Go to **System &gt; Argon Config** in LuCI.
   - Adjust settings (e.g., dark mode, background images, transparency).
   - Save and apply changes.

7. **Verify Installation**: Check installed packages:

   ```bash
   opkg list-installed | grep argon
   ```

   Expected output:

   ```
   luci-app-argon-config - 0.9
   luci-theme-argon - 2.3.1
   ```

## Script Details

The `install-argon.sh` script performs the following steps:

1. **Connectivity Check**: Pings `google.com` to ensure internet access.
2. **Package Update**: Runs `opkg update` to refresh package lists.
3. **Dependency Installation**: Installs `luci` and `luci-compat` for LuCI compatibility.
4. **Download**: Fetches `luci-theme-argon_2.3.1_all.ipk` and `luci-app-argon-config_0.9_all.ipk` from GitHub, using `-O` to avoid redirected filenames.
5. **Installation**: Installs both packages, handling dependencies.
6. **Theme Configuration**: Sets Argon as the default theme via `uci` to bypass post-install errors (e.g., missing `/etc/uci-defaults/30_luci-theme-argon`).
7. **Cache Clearing**: Removes `/tmp/luci-*` to ensure the theme loads correctly.
8. **Verification**: Confirms installation with `opkg list-installed`.
9. **Cleanup**: Deletes temporary files in `/tmp/argon`.

### Error Handling

- Validates internet connectivity and command success.
- Checks for downloaded files and exits with clear error messages if missing.
- Handles optional `luci-app-argon-config` installation failures gracefully.
- Bypasses known post-install errors by manually setting theme defaults.
- Provides actionable error messages for debugging.

## Example Output

```bash
Starting Argon theme installation...
Checking internet connectivity...
Updating package lists...
Installing luci and luci-compat...
Creating temporary directory...
Downloading Argon theme and config packages...
Verifying downloaded files...
Installing luci-theme-argon...
Installing luci-app-argon-config...
luci-app-argon-config installed successfully.
Setting Argon as default theme...
Clearing LuCI cache...
Verifying installation...
luci-theme-argon is installed.
Cleaning up...
Argon theme installation completed!
Access LuCI at http://192.168.1.1, go to System > System > Language and Style, and select 'argon'.
If luci-app-argon-config is installed, customize at System > Argon Config.
```

## Troubleshooting

- **No Internet Connection**:

  - Test connectivity:

    ```bash
    ping google.com
    ```

  - Check network settings or restart the router:

    ```bash
    /etc/init.d/network restart
    ```

- **opkg Update Fails**:

  - Run the `fix-opkg.sh` script to resolve SSL or time issues:

    ```bash
    /root/fix-opkg.sh
    ```

  - Verify repository URLs in `/etc/opkg/distfeeds.conf`.

- **Dependency Errors (e.g., luci-compat)**:

  - Manually install `luci-compat`:

    ```bash
    wget http://downloads.openwrt.org/releases/24.10.0/packages/arm_cortex-a9_vfpv3-d16/luci/luci-compat_0.12.1-1_all.ipk
    opkg install luci-compat_0.12.1-1_all.ipk
    ```

  - Retry the script.

- **Theme Not Displaying**:

  - Clear browser cache or try a different browser.

  - Restart the LuCI web server:

    ```bash
    /etc/init.d/uhttpd restart
    ```

  - Verify theme files:

    ```bash
    ls /usr/lib/lua/luci/view/themes/argon
    ```

  - Ensure `argon` is selected in **System &gt; System &gt; Language and Style**.

- **Download Failures**:

  - Check for newer versions at:

    - https://github.com/jerrykuku/luci-theme-argon/releases
    - https://github.com/jerrykuku/luci-app-argon-config/releases

  - Update the script’s `wget` URLs with the latest `.ipk` files.

  - Example for a new version (e.g., v2.3.2):

    ```bash
    wget -O luci-theme-argon_2.3.2_all.ipk https://github.com/jerrykuku/luci-theme-argon/releases/download/v2.3.2/luci-theme-argon_2.3.2_all.ipk
    ```

- **Post-Install Error**:

  - If you see `/etc/uci-defaults/30_luci-theme-argon: No such file or directory`, it’s harmless. The script manually sets the theme via `uci`.

  - Verify:

    ```bash
    uci get luci.main.mediaurlbase
    ```

    Expected: `/luci-static/argon`.

- **Storage Issues**:

  - Check free space:

    ```bash
    df -h
    ```

  - Free up space by removing unused packages or temporary files:

    ```bash
    opkg remove <package_name>
    rm -rf /tmp/*
    ```

- **Command Typos**:

  - Ensure commands are entered correctly (e.g., avoid `luci-compatopkg` or extra `install` keywords).

  - Example correct sequence:

    ```bash
    opkg install luci luci-compat
    opkg install luci-theme-argon_2.3.1_all.ipk
    ```

## Script Maintenance

To keep the script up-to-date with future Argon theme releases or OpenWrt versions:

- **Check for New Versions**:
  - Visit https://github.com/jerrykuku/luci-theme-argon/releases and https://github.com/jerrykuku/luci-app-argon-config/releases.
  - Update the `wget` URLs in `install-argon.sh` with the latest `.ipk` files (e.g., replace `v2.3.1` with `v2.3.2`).
- **Verify OpenWrt Compatibility**:
  - For newer OpenWrt releases (e.g., 25.x), check dependency changes in the OpenWrt forum or package repository.
  - Update `luci-compat` version in the troubleshooting section if needed.
- **Test After Updates**:
  - Run the updated script on a test router or backup your configuration before executing.

## Notes

- **OpenWrt Version**: Tested on OpenWrt 24.10.0 (`mvebu/cortexa9`, `armv7l`). For other versions, verify repository URLs and package compatibility.
- **Architecture**: Uses `all` packages (`luci-theme-argon`, `luci-app-argon-config`), compatible with `arm_cortex-a9_vfpv3-d16`.
- **Storage**: Script (\~1 KB) and packages (\~400 KB total) are lightweight. Monitor `/overlay` space.
- **Security**: Downloads from trusted GitHub releases by @jerrykuku. Always verify URLs.
- **Automation**: Pair with `fix-opkg.sh` for a complete post-flash setup. Store both scripts locally (e.g., `~/openwrt-scripts/`) for reuse.
- **Router Model**: Tailored for Linksys routers. Specify your model (e.g., WRT1900ACS) for model-specific guidance.
- **Customization**: Use `luci-app-argon-config` for dark mode, background images, or transparency settings.

## License

This script is provided as-is, free to use and modify. No warranty is implied.

## Support

For assistance:

- **OpenWrt Forum**: https://forum.openwrt.org/t/theme-argon-main-thread/91817
- **OpenWrt Bug Tracker**: https://bugs.openwrt.org/
- **Argon Theme Repository**: https://github.com/jerrykuku/luci-theme-argon
- **Argon Config Repository**: https://github.com/jerrykuku/luci-app-argon-config
