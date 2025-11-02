#!/bin/sh
#
# OpenWrt Toolkit Menu
#
# This launcher discovers helper scripts stored in the local scripts/
# directory and presents a simple interactive menu for invoking them.
# Each managed script can optionally declare metadata in the form of the
# following comments near the top of the file:
#   # TOOL_NAME: Friendly script name
#   # TOOL_DESC: One-line description shown in the menu
# The launcher falls back to the script file name if no TOOL_NAME is
# provided and suppresses scripts that opt-out with "# TOOL_HIDDEN: true".
#
# This file is self-contained and does not modify any of the existing
# top-level helper scripts, allowing the newly enhanced tools to live in
# the dedicated scripts/ directory.

set -eu

SCRIPT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
MODULE_DIR="${SCRIPT_ROOT}/scripts"

# shellcheck disable=SC2039
usage() {
  cat <<'USAGE'
OpenWrt Toolkit
================

Usage: openwrt-toolkit.sh [--list | --run <name> | --help]

Options:
  --list          Print available tools and exit
  --run <name>    Execute the tool identified by its name (file stem)
  --help          Show this help message

Without arguments the toolkit will launch an interactive menu.
USAGE
}

require_module_dir() {
  if [ ! -d "$MODULE_DIR" ]; then
    printf >&2 'Error: scripts directory not found at %s\n' "$MODULE_DIR"
    exit 1
  fi
}

# shellcheck disable=SC2039
discover_tools() {
  require_module_dir
  # Format: name<TAB>description<TAB>path
  find "$MODULE_DIR" -maxdepth 1 -type f -name '*.sh' | while IFS= read -r script; do
    [ -f "$script" ] || continue
    if grep -q '^# TOOL_HIDDEN:[[:space:]]*true' "$script"; then
      continue
    fi
    name=$(grep -m1 '^# TOOL_NAME:' "$script" | sed 's/^# TOOL_NAME:[[:space:]]*//') || true
    desc=$(grep -m1 '^# TOOL_DESC:' "$script" | sed 's/^# TOOL_DESC:[[:space:]]*//') || true
    [ -n "$name" ] || name=$(basename "$script" .sh)
    [ -n "$desc" ] || desc="Run $(basename "$script")"
    printf '%s\t%s\t%s\n' "$name" "$desc" "$script"
  done | sort
}

list_tools() {
  discover_tools | while IFS="\t" read -r name desc _path; do
    printf '%-25s %s\n' "$name" "$desc"
  done
}

run_tool_by_stem() {
  stem=$1
  require_module_dir
  for script in "$MODULE_DIR/${stem}.sh" "$MODULE_DIR/${stem}"; do
    if [ -f "$script" ]; then
      sh "$script"
      return
    fi
  done
  printf >&2 'Error: tool "%s" not found in %s\n' "$stem" "$MODULE_DIR"
  exit 1
}

interactive_menu() {
  tools=$(discover_tools)
  if [ -z "$tools" ]; then
    printf >&2 'No tools found in %s\n' "$MODULE_DIR"
    exit 1
  fi

  while true; do
    printf '\nOpenWrt Toolkit Menu\n'
    printf '--------------------\n'
    idx=1
    printf '  %2s) %s\n' "Q" "Quit"
    printf '  %2s) %s\n' "R" "Refresh list"
    echo "$tools" | while IFS="\t" read -r name desc path; do
      printf '  %2d) %-22s %s\n' "$idx" "$name" "$desc"
      idx=$((idx + 1))
    done

    printf '\nSelect an option: '
    IFS= read -r choice || exit 0
    case $choice in
      [Qq])
        printf 'Exiting toolkit.\n'
        exit 0
        ;;
      [Rr])
        tools=$(discover_tools)
        continue
        ;;
      '')
        continue
        ;;
      *)
        if printf '%s' "$choice" | grep -Eq '^[0-9]+$'; then
          selected=$(echo "$tools" | sed -n "${choice}p") || true
          if [ -n "$selected" ]; then
            name=$(printf '%s' "$selected" | cut -f1)
            path=$(printf '%s' "$selected" | cut -f3)
            printf '\nRunning %s...\n\n' "$name"
            sh "$path"
            printf '\nCompleted %s.\n' "$name"
          else
            printf 'Invalid selection.\n'
          fi
        else
          printf 'Invalid selection.\n'
        fi
        ;;
    esac
  done
}

main() {
  if [ $# -eq 0 ]; then
    interactive_menu
    return
  fi

  case $1 in
    --help|-h)
      usage
      ;;
    --list)
      list_tools
      ;;
    --run)
      if [ $# -lt 2 ]; then
        printf >&2 '--run requires a tool name\n'
        exit 1
      fi
      run_tool_by_stem "$2"
      ;;
    *)
      printf >&2 'Unknown option: %s\n\n' "$1"
      usage
      exit 1
      ;;
  esac
}

main "$@"
