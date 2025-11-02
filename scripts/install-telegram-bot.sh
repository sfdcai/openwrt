#!/bin/sh
# TOOL_NAME: Telegram bot installer
# TOOL_DESC: Fetch and run the OpenWrt Telegram bot installer
#
# This helper downloads the installer script from the
# https://github.com/sfdcai/openwrt-telegram repository, saves it to a
# temporary directory, and executes it. You can override the branch or
# remote script name if required and perform a dry run to inspect the
# downloaded file before execution.

set -eu

REPO_OWNER="sfdcai"
REPO_NAME="openwrt-telegram"
DEFAULT_BRANCH="main"
DEFAULT_SCRIPT="install.sh"
RAW_BASE="https://raw.githubusercontent.com"

usage() {
  cat <<'USAGE'
Telegram Bot Installer
======================

Usage: install-telegram-bot.sh [options] [-- <args>]

Options:
  --branch <name>     Pull installer from a different branch (default: main)
  --script <name>     Use an alternate script filename (default: install.sh)
  --dry-run           Download without executing; print the saved location
  --print-url         Show the resolved download URL and exit
  --help              Display this message

Additional arguments placed after "--" are forwarded to the installer.
USAGE
}

download_file() {
  url=$1
  dest=$2
  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O "$dest" "$url"
  else
    printf >&2 'Error: Neither wget nor uclient-fetch is available.\n'
    exit 1
  fi
}

main() {
  branch=$DEFAULT_BRANCH
  script_name=$DEFAULT_SCRIPT
  dry_run=0
  print_url=0
  forwarded_args=""

  while [ $# -gt 0 ]; do
    case $1 in
      --branch)
        if [ $# -lt 2 ]; then
          printf >&2 '--branch requires a value.\n'
          exit 1
        fi
        branch=$2
        shift 2
        ;;
      --script)
        if [ $# -lt 2 ]; then
          printf >&2 '--script requires a value.\n'
          exit 1
        fi
        script_name=$2
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --print-url)
        print_url=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        forwarded_args="$*"
        break
        ;;
      *)
        printf >&2 'Unknown option: %s\n' "$1"
        usage
        exit 1
        ;;
    esac
  done

  download_url="${RAW_BASE}/${REPO_OWNER}/${REPO_NAME}/${branch}/${script_name}"

  if [ "$print_url" -eq 1 ]; then
    printf '%s\n' "$download_url"
    exit 0
  fi

  stamp=$(date '+%s' 2>/dev/null || echo 0)
  tmpdir="/tmp/openwrt-telegram-${stamp}.$$"
  mkdir -p "$tmpdir"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM HUP
  target="${tmpdir}/${script_name}"

  printf 'Downloading installer from %s\n' "$download_url"
  download_file "$download_url" "$target"

  if [ ! -s "$target" ]; then
    printf >&2 'Error: Downloaded installer is empty.\n'
    exit 1
  fi

  chmod +x "$target"

  if [ "$dry_run" -eq 1 ]; then
    printf 'Dry run: installer saved to %s\n' "$target"
    printf 'Inspect the file and rerun without --dry-run to execute.\n'
    return
  fi

  printf 'Executing Telegram bot installer...\n'
  if [ -n "$forwarded_args" ]; then
    # shellcheck disable=SC2086
    sh "$target" $forwarded_args
  else
    sh "$target"
  fi
  printf 'Telegram bot installer completed.\n'
}

main "$@"
