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
MODULE_DIRS="scripts legacy"

# shellcheck disable=SC2039
usage() {
  cat <<'USAGE'
OpenWrt Toolkit
================

Usage: openwrt-toolkit.sh [--list | --run <name> | --help]

Options:
  --list          Print available tools and exit
  --run <name>    Execute the tool identified by its name (file stem)
                  Use prefixes such as "legacy/<tool>" for legacy items
  --help          Show this help message

Without arguments the toolkit will launch an interactive menu.
USAGE
}

require_module_dirs() {
  for dir in $MODULE_DIRS; do
    if [ -d "${SCRIPT_ROOT}/${dir}" ]; then
      return
    fi
  done
  printf >&2 'Error: no script directories found under %s\n' "$SCRIPT_ROOT"
  exit 1
}

# shellcheck disable=SC2039
discover_tools() {
  require_module_dirs
  # Format: display<TAB>description<TAB>path<TAB>key
  for dir in $MODULE_DIRS; do
    module_dir="${SCRIPT_ROOT}/${dir}"
    [ -d "$module_dir" ] || continue
    find "$module_dir" -maxdepth 1 -type f -name '*.sh' | while IFS= read -r script; do
      [ -f "$script" ] || continue
      if grep -q '^# TOOL_HIDDEN:[[:space:]]*true' "$script"; then
        continue
      fi
      stem=$(basename "$script" .sh)
      display=$(grep -m1 '^# TOOL_NAME:' "$script" | sed 's/^# TOOL_NAME:[[:space:]]*//') || true
      desc=$(grep -m1 '^# TOOL_DESC:' "$script" | sed 's/^# TOOL_DESC:[[:space:]]*//') || true
      [ -n "$desc" ] || desc="Run $(basename "$script")"
      key="$stem"
      if [ "$dir" = "legacy" ]; then
        [ -n "$display" ] || display="Legacy: $stem"
        key="legacy/$stem"
        case $desc in
          Legacy*) ;;
          *) desc="Legacy script: $desc" ;;
        esac
      else
        [ -n "$display" ] || display="$stem"
      fi
      printf '%s\t%s\t%s\t%s\n' "$display" "$desc" "$script" "$key"
    done
  done | sort
}

list_tools() {
  discover_tools | while IFS='	' read -r display desc _path _key; do
    printf '%s - %s\n' "$display" "$desc"
  done
}

run_tool_by_stem() {
  stem=$1
  require_module_dirs
  match=$(discover_tools | while IFS='	' read -r display _desc path key; do
    if [ "$key" = "$stem" ]; then
      printf '%s\t%s\n' "$display" "$path"
      break
    fi
  done)
  if [ -z "$match" ]; then
    printf >&2 'Error: tool "%s" not found. Use --list to view options.\n' "$stem"
    exit 1
  fi
  display=$(printf '%s' "$match" | cut -f1)
  path=$(printf '%s' "$match" | cut -f2)
  printf 'Running %s...\n\n' "$display"
  sh "$path"
  printf '\nCompleted %s.\n' "$display"
}

interactive_menu() {
  tools=$(discover_tools)
  if [ -z "$tools" ]; then
    printf >&2 'No tools found under %s (searched: %s)\n' "$SCRIPT_ROOT" "$MODULE_DIRS"
    exit 1
  fi

  while true; do
    printf '\nOpenWrt Toolkit Menu\n'
    printf '--------------------\n'
    idx=1
    printf '  %2s) %s\n' "Q" "Quit"
    printf '  %2s) %s\n' "R" "Refresh list"
    printf '%s\n' "$tools" | while IFS='	' read -r display desc path key; do
      printf '  %2d) %s - %s\n' "$idx" "$display" "$desc"
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
            display=$(printf '%s' "$selected" | cut -f1)
            path=$(printf '%s' "$selected" | cut -f3)
            printf '\nRunning %s...\n\n' "$display"
            sh "$path"
            printf '\nCompleted %s.\n' "$display"
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
