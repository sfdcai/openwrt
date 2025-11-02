#!/bin/sh
# TOOL_NAME: Command inventory
# TOOL_DESC: Capture available shell commands into a report file
#
# Scans BusyBox applets and executable files along $PATH to build a
# reference list of commands supported on the current system. The report
# is written to /tmp/openwrt-commands.txt by default and can optionally
# be printed to standard output as well.

set -eu

OUTPUT="/tmp/openwrt-commands.txt"
PRINT_STDOUT=0
INCLUDE_PATHS=""

usage() {
  cat <<'USAGE'
Command Inventory
=================

Usage: command-inventory.sh [options]

Options:
  --output <file>   Write the inventory to the specified file
  --print           Echo the inventory to stdout after saving
  --paths <list>    Override PATH scanning (colon separated)
  --help            Show this help message
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --output)
      if [ $# -lt 2 ]; then
        printf >&2 '--output requires a path.\n'
        exit 1
      fi
      OUTPUT=$2
      shift 2
      ;;
    --print)
      PRINT_STDOUT=1
      shift
      ;;
    --paths)
      if [ $# -lt 2 ]; then
        printf >&2 '--paths requires a colon-separated list.\n'
        exit 1
      fi
      INCLUDE_PATHS=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1
      ;;
  esac
done

list_busybox_commands() {
  if command -v busybox >/dev/null 2>&1; then
    busybox --list 2>/dev/null | sort
  fi
}

list_path_commands() {
  paths=$1
  for dir in $paths; do
    [ -d "$dir" ] || continue
    for file in "$dir"/*; do
      [ -f "$file" ] || [ -L "$file" ] || continue
      if [ -x "$file" ]; then
        basename "$file"
      fi
    done
  done | sort -u
}

collect_paths() {
  if [ -n "$INCLUDE_PATHS" ]; then
    printf '%s' "$INCLUDE_PATHS" | tr ':' ' '
  else
    printf '%s' "$PATH" | tr ':' ' '
  fi
}

write_report() {
  tmp=$(mktemp 2>/dev/null || mktemp -t cmdinv.XXXXXX)
  {
    printf '# OpenWrt command inventory generated on %s\n' "$(date 2>/dev/null || echo now)"
    printf '# Output file: %s\n' "$OUTPUT"

    if command -v busybox >/dev/null 2>&1; then
      printf '\n[BusyBox applets]\n'
      list_busybox_commands
    else
      printf '\n[BusyBox applets]\nBusyBox not available\n'
    fi

    printf '\n[Executables on PATH]\n'
    list_path_commands "$(collect_paths)"
  } >"$tmp"

  mkdir -p "$(dirname "$OUTPUT")"
  cp "$tmp" "$OUTPUT"
  rm -f "$tmp"
}

write_report

if [ "$PRINT_STDOUT" -eq 1 ]; then
  cat "$OUTPUT"
else
  printf 'Command inventory written to %s\n' "$OUTPUT"
fi
