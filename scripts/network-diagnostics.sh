#!/bin/sh
# TOOL_NAME: Network diagnostics
# TOOL_DESC: Gather connectivity and latency diagnostics
#
# Collects quick network troubleshooting information, including
# interface status, DNS lookups, and optional ping/trace tests.

set -eu

default_ping_target="8.8.8.8"
default_trace_target="openwrt.org"
PING_COUNT=4
TRACE=0
TARGET="$default_ping_target"
TRACE_TARGET="$default_trace_target"
DNS_NAME=""

usage() {
  cat <<'USAGE'
Usage: network-diagnostics.sh [OPTIONS]

Options:
  --target <host>     Host or IP to ping (default: 8.8.8.8)
  --count <n>         Number of ICMP echo requests (default: 4)
  --trace [host]      Perform traceroute (optional custom host)
  --dns <name>        Resolve DNS for the provided hostname
  --help              Show this help text
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --target)
      TARGET=$2; shift 2 ;;
    --count)
      PING_COUNT=$2; shift 2 ;;
    --trace)
      TRACE=1
      if [ $# -gt 1 ]; then
        next=$2
        if [ "${next#-}" = "$next" ]; then
          TRACE_TARGET=$next
          shift 2
          continue
        fi
      fi
      shift ;;
    --dns)
      DNS_NAME=$2; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1 ;;
  esac
done

log_section() {
  printf '\n=== %s ===\n' "$1"
}

log_section "System"
uname -a 2>/dev/null || true

date 2>/dev/null || true

log_section "Interfaces"
if command -v ip >/dev/null 2>&1; then
  ip address show
else
  ifconfig -a 2>/dev/null || true
fi

if command -v iw >/dev/null 2>&1; then
  log_section "Wireless"
  iw dev 2>/dev/null || true
fi

log_section "Routing"
if command -v ip >/dev/null 2>&1; then
  ip route show
else
  route -n 2>/dev/null || true
fi

log_section "DNS"
cat /etc/resolv.conf 2>/dev/null || true
if [ -n "$DNS_NAME" ] && command -v nslookup >/dev/null 2>&1; then
  nslookup "$DNS_NAME" || true
fi

if command -v ping >/dev/null 2>&1; then
  log_section "Ping $TARGET"
  ping -c "$PING_COUNT" "$TARGET" || true
else
  printf 'ping command not available\n'
fi

if [ "$TRACE" -eq 1 ]; then
  log_section "Traceroute to $TRACE_TARGET"
  if command -v traceroute >/dev/null 2>&1; then
    traceroute "$TRACE_TARGET" || true
  elif command -v mtr >/dev/null 2>&1; then
    mtr -rw "$TRACE_TARGET" || true
  else
    printf 'No traceroute or mtr command available\n'
  fi
fi

log_section "Firewall"
if command -v fw4 >/dev/null 2>&1; then
  fw4 status 2>/dev/null || true
elif command -v fw3 >/dev/null 2>&1; then
  fw3 status 2>/dev/null || true
fi

log_section "Done"
