#!/bin/sh
# TOOL_NAME: System health report
# TOOL_DESC: Summarise key OpenWrt metrics and service status
#
# Provides a quick overview of system load, storage utilisation, network
# connectivity, and package status to simplify troubleshooting sessions.

set -eu

LOG_LINES=20
PING_TARGET="openwrt.org"

usage() {
  cat <<'USAGE'
System Health Report
====================

Usage: system-health-report.sh [options]

Options:
  --logs <lines>    Number of recent logread lines to display (default: 20)
  --ping <host>     Test reachability of a different host (default: openwrt.org)
  --help            Display this message
USAGE
}

print_section() {
  printf '\n=== %s ===\n' "$1"
}

main() {
  log_lines=$LOG_LINES
  ping_target=$PING_TARGET

  while [ $# -gt 0 ]; do
    case $1 in
      --logs)
        if [ $# -lt 2 ]; then
          printf >&2 '--logs requires a number.\n'
          exit 1
        fi
        log_lines=$2
        shift 2
        ;;
      --ping)
        if [ $# -lt 2 ]; then
          printf >&2 '--ping requires a host name or IP.\n'
          exit 1
        fi
        ping_target=$2
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

  print_section "System"
  date
  if command -v uname >/dev/null 2>&1; then
    uname -a
  fi
  if command -v uptime >/dev/null 2>&1; then
    uptime
  fi

  print_section "Resources"
  if command -v free >/dev/null 2>&1; then
    free
  else
    egrep 'Mem|Swap' /proc/meminfo 2>/dev/null || printf 'meminfo not available\n'
  fi
  df

  print_section "Network"
  if command -v ip >/dev/null 2>&1; then
    ip addr show
  else
    ifconfig 2>/dev/null || printf 'ip/ifconfig unavailable\n'
  fi
  if command -v ping >/dev/null 2>&1; then
    printf '\nPing test (%s):\n' "$ping_target"
    ping -c 4 "$ping_target" 2>&1
  else
    printf 'ping utility not available; skipping test.\n'
  fi

  if command -v opkg >/dev/null 2>&1; then
    print_section "Package updates"
    opkg list-upgradable || printf 'Unable to query upgrades.\n'
  fi

  if command -v logread >/dev/null 2>&1; then
    print_section "Recent logread"
    logread | tail -n "$log_lines"
  fi

  print_section "Completed"
  printf 'System health report generated successfully.\n'
}

main "$@"
