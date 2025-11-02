# OpenWrt Modular Toolkit

A menu-driven launcher (`openwrt-toolkit.sh`) plus a growing catalog of focused
maintenance scripts simplify post-flash setup, diagnostics, and day-to-day care
for OpenWrt systems. Modules live under `scripts/` and are automatically
discovered; original helper scripts are preserved inside `legacy/` and remain
accessible from the same launcher with a `legacy/` prefix.

## Quick Start
Download, unpack, and launch the toolkit directly on your router with a
single command (defaults to `/tmp` to avoid permanent storage use):

```sh
sh -c 'cd /tmp && rm -rf openwrt-main \
  && wget -qO- https://github.com/sfdcai/openwrt/archive/refs/heads/main.tar.gz \
  | tar xz && cd openwrt-main \
  && chmod +x openwrt-toolkit.sh scripts/*.sh legacy/*.sh \
  && ./openwrt-toolkit.sh'
```

From the menu you can run any helper interactively, refresh the list after
adding new modules, or jump into the **Legacy scripts** submenu to access the
original utilities. The CLI also supports scripting:

```sh
./openwrt-toolkit.sh --list              # show everything the launcher found
./openwrt-toolkit.sh --run fix-opkg      # execute scripts/fix-opkg.sh
./openwrt-toolkit.sh --run legacy/setup-usb  # execute legacy/setup-usb.sh
```

## Repository Layout
```
openwrt-toolkit.sh      # Launcher that enumerates scripts/ and legacy/
scripts/                # Modern modular helpers (auto-discovered)
legacy/                 # Original scripts retained for compatibility
```

### Modular helpers (`scripts/`)
| Tool | Highlights |
| --- | --- |
| `fix-opkg` | Repairs `opkg` feeds with backup/restore, HTTP-only mode, and dry-run execution. |
| `install-argon-theme` | Installs or updates the Argon LuCI theme with checksum verification. |
| `setup-usb-storage` | Prepares USB disks, swap files, and mounts for overlay or data use. |
| `extroot-manager` | Validates overlay mounts and toggles extroot entries with safe testing flows. |
| `network-diagnostics` | Captures connectivity, DNS, and routing diagnostics into timestamped reports. |
| `backup-config` | Creates archives of `/etc/config`, optional UCI exports, and package manifests. |
| `system-health-report` | Summarises load, memory, storage, network, and package update status. |
| `install-telegram-bot` | Downloads and runs the installer from [`sfdcai/openwrt-telegram`](https://github.com/sfdcai/openwrt-telegram). |
| `command-inventory` | Writes a sorted list of BusyBox applets and PATH executables to aid script portability. |
| `wifi-maintenance` | Reloads Wi-Fi, inspects radios, and surfaces relevant log excerpts. |

Each script documents extra flags via `--help` and declares `# TOOL_NAME` and
`# TOOL_DESC` metadata so the launcher can present friendly descriptions.

### Legacy helpers (`legacy/`)
The original maintenance scripts remain available and show up in the launcher as
`legacy/<name>` entries accessed via the dedicated submenu:

| Tool | Notes |
| --- | --- |
| `legacy/fix-opkg` | Historical OPKG repair script kept for parity with older guides. |
| `legacy/install-argon` | Previous Argon installation workflow with minimal dependencies. |
| `legacy/setup-usb` | Earlier USB storage provisioning script. |
| `legacy/Setup-extroot-swap-optimize` | Comprehensive extroot and swap tuning helper. |

If you rely on other legacy files in the repository (e.g. the configuration
manager or Telegram service scripts) you can continue to invoke them directly;
they are not relocated to avoid breaking existing automation.

## Telegram bot integration
`scripts/install-telegram-bot.sh` fetches the latest installer from the
[`sfdcai/openwrt-telegram`](https://github.com/sfdcai/openwrt-telegram)
repository. Use `--branch`, `--script`, or `--dry-run` to override the download
source and inspect the installer before execution:

```sh
./openwrt-toolkit.sh --run install-telegram-bot --branch main --dry-run
```

Additional arguments placed after a literal `--` are forwarded to the upstream
installer once downloaded:

```sh
./openwrt-toolkit.sh --run install-telegram-bot -- --token abc123
```

## Capture available commands
Use `./openwrt-toolkit.sh --run command-inventory` to generate
`/tmp/openwrt-commands.txt`, a reference of BusyBox applets and standalone
executables on the current firmware image. The report makes it easy to confirm
which tools exist on OpenWrt 24.10 before writing new automation. Add
`--print` to stream the inventory directly to the terminal.

For quick offline reference, the repository ships with
[`docs/openwrt-commands.txt`](docs/openwrt-commands.txt), a captured inventory
from a stock 24.10 build that informed the command choices used throughout the
modern scripts.

## Extend the toolkit
1. Drop a new executable shell script in `scripts/` (or add metadata to a legacy
   script to improve its menu label).
2. Add optional `# TOOL_NAME:` and `# TOOL_DESC:` comments near the top.
3. Re-run `openwrt-toolkit.sh` and choose **Refresh list** from the menu or rerun
   `--list` to confirm discovery.

Version control and test your modules locally before copying them to the router
for predictable upgrades.

## Validation
Static linting verifies the launcher and all shipped modules:

```sh
sh -n openwrt-toolkit.sh scripts/*.sh legacy/*.sh
```
