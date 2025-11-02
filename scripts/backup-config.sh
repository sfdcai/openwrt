#!/bin/sh
# TOOL_NAME: Configuration backup
# TOOL_DESC: Archive system configuration snapshots to /tmp
#
# Creates a timestamped archive containing /etc/config along with optional
# UCI and package listings so the snapshot can be restored or audited later.

set -eu

CONFIG_DIR="/etc/config"
DEFAULT_DIR="/tmp"
BACKUP_PREFIX="openwrt-config"

usage() {
  cat <<'USAGE'
Configuration Backup Utility
============================

Usage: backup-config.sh [options]

Options:
  --output <file>        Custom output path instead of /tmp/openwrt-config-*.tar.gz
  --include-uci          Capture `uci show` output alongside configuration files
  --include-packages     Record `opkg list-installed` output in the archive
  --keep-temp            Do not delete the staging directory (for debugging)
  --help                 Display this message
USAGE
}

main() {
  output=""
  include_uci=0
  include_packages=0
  keep_temp=0

  while [ $# -gt 0 ]; do
    case $1 in
      --output)
        if [ $# -lt 2 ]; then
          printf >&2 '--output requires a path.\n'
          exit 1
        fi
        output=$2
        shift 2
        ;;
      --include-uci)
        include_uci=1
        shift
        ;;
      --include-packages)
        include_packages=1
        shift
        ;;
      --keep-temp)
        keep_temp=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        printf >&2 'Unknown option: %s\n' "$1"
        usage
        exit 1
        ;;
    esac
  done

  if [ ! -d "$CONFIG_DIR" ]; then
    printf >&2 'Error: configuration directory %s not found.\n' "$CONFIG_DIR"
    exit 1
  fi

  timestamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%s')
  if [ -z "$output" ]; then
    output="${DEFAULT_DIR}/${BACKUP_PREFIX}-${timestamp}.tar.gz"
  fi

  tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t cfgbackup)
  if [ "$keep_temp" -ne 1 ]; then
    trap 'rm -rf "$tmpdir"' EXIT INT TERM HUP
  fi

  staging="$tmpdir/config"
  mkdir -p "$staging"
  printf 'Copying configuration files from %s\n' "$CONFIG_DIR"
  cp -a "$CONFIG_DIR" "$staging"/etc-config

  if [ "$include_uci" -eq 1 ]; then
    printf 'Capturing UCI configuration snapshot\n'
    if command -v uci >/dev/null 2>&1; then
      uci show > "$tmpdir/uci-export.txt"
    else
      printf 'Warning: uci command not available; skipping export.\n'
    fi
  fi

  if [ "$include_packages" -eq 1 ]; then
    printf 'Recording installed packages\n'
    if command -v opkg >/dev/null 2>&1; then
      opkg list-installed > "$tmpdir/opkg-installed.txt"
    else
      printf 'Warning: opkg command not available; skipping package list.\n'
    fi
  fi

  mkdir -p "$(dirname "$output")"
  printf 'Creating archive %s\n' "$output"
  tar -C "$tmpdir" -czf "$output" .

  if [ "$keep_temp" -eq 1 ]; then
    printf 'Temporary files kept at %s\n' "$tmpdir"
  fi

  printf 'Backup complete: %s\n' "$output"
}

main "$@"
