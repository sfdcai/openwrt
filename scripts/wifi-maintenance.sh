#!/bin/sh
# TOOL_NAME: Wi-Fi maintenance helper
# TOOL_DESC: Inspect radios, restart wireless, and review recent logs
#
# Provides quick Wi-Fi related checks suitable for stock OpenWrt builds.
# It can print interface status, reload the wireless stack, and display
# recent log entries associated with hostapd or wireless drivers.

set -eu

ACTION="status"
TARGET_RADIO=""
LOG_LINES=20

usage() {
  cat <<'USAGE'
Wi-Fi Maintenance Helper
========================

Usage: wifi-maintenance.sh [options]

Options:
  --status           Show wireless interfaces and associated stations (default)
  --restart          Reload wireless using the wifi helper
  --radio <name>     Limit status output to a specific radio (e.g. radio0)
  --logs <lines>     Show the latest logread lines mentioning wifi/hostapd
  --help             Display this message
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --status)
      ACTION="status"
      shift
      ;;
    --restart)
      ACTION="restart"
      shift
      ;;
    --radio)
      if [ $# -lt 2 ]; then
        printf >&2 '--radio requires an identifier such as radio0.\n'
        exit 1
      fi
      TARGET_RADIO=$2
      shift 2
      ;;
    --logs)
      if [ $# -lt 2 ]; then
        printf >&2 '--logs requires a numeric value.\n'
        exit 1
      fi
      LOG_LINES=$2
      shift 2
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

show_status() {
  if command -v uci >/dev/null 2>&1; then
    printf 'Configured wireless interfaces:\n'
    if [ -n "$TARGET_RADIO" ]; then
      uci show wireless | grep "${TARGET_RADIO}" 2>/dev/null || printf '  No entries for %s\n' "$TARGET_RADIO"
    else
      uci show wireless 2>/dev/null || printf '  Unable to query wireless config.\n'
    fi
  fi

  if command -v iwinfo >/dev/null 2>&1; then
    printf '\nActive interfaces:\n'
    iwinfo 2>/dev/null || printf '  iwinfo command produced no data.\n'
  else
    printf 'iwinfo command not available.\n'
  fi

  if [ "$LOG_LINES" -gt 0 ] && command -v logread >/dev/null 2>&1; then
    printf '\nRecent Wi-Fi log entries (last %s lines):\n' "$LOG_LINES"
    logread | egrep 'wifi|hostapd|wpa' | tail -n "$LOG_LINES" 2>/dev/null || printf '  No matching log entries found.\n'
  fi
}

restart_wifi() {
  if ! command -v wifi >/dev/null 2>&1; then
    printf 'wifi helper not available; cannot restart wireless.\n'
    exit 1
  fi
  printf 'Reloading wireless configuration...\n'
  if wifi reload 2>/dev/null; then
    printf 'wifi reload command executed.\n'
    return
  fi
  if wifi up 2>/dev/null; then
    printf 'wifi up command executed.\n'
    return
  fi
  printf 'Failed to reload wireless; check system logs.\n'
  exit 1
}

case $ACTION in
  status)
    show_status
    ;;
  restart)
    restart_wifi
    if [ -n "$TARGET_RADIO" ] || [ "$LOG_LINES" -gt 0 ]; then
      printf '\nPost-restart status:\n'
      show_status
    fi
    ;;
  *)
    usage
    exit 1
    ;;
 esac
