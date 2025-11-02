#!/bin/sh
#
# OpenWrt Toolkit Menu
#
# Presents an interactive launcher for helper scripts stored under
# scripts/ (modern modules) and legacy/ (historic utilities). Legacy
# entries are accessible through a dedicated submenu so that new helpers
# remain front and centre while backwards compatibility is preserved.

set -eu

SCRIPT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
MODULE_DIRS="scripts legacy"
TAB="$(printf '\t')"

# shellcheck disable=SC2039
usage() {
  cat <<'USAGE'
OpenWrt Toolkit
================

Usage: openwrt-toolkit.sh [--list | --run <name> | --help]

Options:
  --list          Print available tools grouped by category
  --run <name>    Execute a tool (use legacy/<name> for legacy items)
  --help          Show this help message

Without arguments the toolkit launches an interactive menu.
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
  modern_tmp=$(mktemp 2>/dev/null || mktemp -t modern.XXXXXX)
  legacy_tmp=$(mktemp 2>/dev/null || mktemp -t legacy.XXXXXX)

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
      if [ "$dir" = "legacy" ]; then
        [ -n "$display" ] || display="$stem"
        key="legacy/$stem"
        printf '%s\t%s\t%s\t%s\n' "$display" "Legacy script: $desc" "$script" "$key" >>"$legacy_tmp"
      else
        [ -n "$display" ] || display="$stem"
        key="$stem"
        printf '%s\t%s\t%s\t%s\n' "$display" "$desc" "$script" "$key" >>"$modern_tmp"
      fi
    done
  done

  if [ -s "$modern_tmp" ]; then
    while IFS= read -r line; do
      printf 'modern\t%s\n' "$line"
    done <"$modern_tmp" | sort
  fi
  if [ -s "$legacy_tmp" ]; then
    while IFS= read -r line; do
      printf 'legacy\t%s\n' "$line"
    done <"$legacy_tmp" | sort
  fi

  rm -f "$modern_tmp" "$legacy_tmp"
}

list_tools() {
  tools=$(discover_tools)
  if [ -z "$tools" ]; then
    printf 'No tools discovered.\n'
    return
  fi

  modern_tmp=$(mktemp 2>/dev/null || mktemp -t modern.XXXXXX)
  legacy_tmp=$(mktemp 2>/dev/null || mktemp -t legacy.XXXXXX)

  printf '%s\n' "$tools" | while IFS="$TAB" read -r category display desc _path key; do
    case $category in
      modern)
        printf '%s\t%s\t%s\n' "$display" "$desc" "$key" >>"$modern_tmp"
        ;;
      legacy)
        printf '%s\t%s\t%s\n' "$display" "$desc" "$key" >>"$legacy_tmp"
        ;;
    esac
  done

  if [ -s "$modern_tmp" ]; then
    printf 'Modern scripts:\n'
    while IFS="$TAB" read -r display desc key; do
      printf '  %s - %s (run: %s)\n' "$display" "$desc" "$key"
    done <"$modern_tmp"
  fi

  if [ -s "$legacy_tmp" ]; then
    printf '\nLegacy scripts:\n'
    while IFS="$TAB" read -r display desc key; do
      printf '  %s - %s (run: %s)\n' "$display" "$desc" "$key"
    done <"$legacy_tmp"
  fi

  rm -f "$modern_tmp" "$legacy_tmp"
}

run_tool_by_stem() {
  stem=$1
  match=$(discover_tools | while IFS="$TAB" read -r category display _desc path key; do
    if [ "$key" = "$stem" ]; then
      printf '%s\t%s\n' "$display" "$path"
      break
    fi
    if [ "$category" = "legacy" ] && [ "$key" = "legacy/$stem" ]; then
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

legacy_menu() {
  legacy_tools=$1
  if [ -z "$legacy_tools" ]; then
    printf 'No legacy scripts available.\n'
    return
  fi

  while true; do
    printf '\nLegacy scripts\n'
    printf '--------------\n'
    printf '  %2s) %s\n' "B" "Back to main menu"
    idx=1
    printf '%s\n' "$legacy_tools" | while IFS="$TAB" read -r display desc path key; do
      printf '  %2d) %s - %s\n' "$idx" "$display" "$desc"
      idx=$((idx + 1))
    done

    printf '\nSelect an option: '
    IFS= read -r choice || return
    case $choice in
      [Bb])
        return
        ;;
      '')
        continue
        ;;
      *)
        if printf '%s' "$choice" | grep -Eq '^[0-9]+$'; then
          selected=$(echo "$legacy_tools" | sed -n "${choice}p") || true
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

interactive_menu() {
  while true; do
    tools=$(discover_tools)
    if [ -z "$tools" ]; then
      printf >&2 'No tools found under %s (searched: %s)\n' "$SCRIPT_ROOT" "$MODULE_DIRS"
      exit 1
    fi

    modern_tmp=$(mktemp 2>/dev/null || mktemp -t modern.XXXXXX)
    legacy_tmp=$(mktemp 2>/dev/null || mktemp -t legacy.XXXXXX)

    printf '%s\n' "$tools" | while IFS="$TAB" read -r category display desc path key; do
      case $category in
        modern)
          printf '%s\t%s\t%s\t%s\n' "$display" "$desc" "$path" "$key" >>"$modern_tmp"
          ;;
        legacy)
          printf '%s\t%s\t%s\t%s\n' "$display" "$desc" "$path" "$key" >>"$legacy_tmp"
          ;;
      esac
    done

    modern_tools=$(cat "$modern_tmp" 2>/dev/null)
    legacy_tools=$(cat "$legacy_tmp" 2>/dev/null)
    rm -f "$modern_tmp" "$legacy_tmp"

    printf '\nOpenWrt Toolkit Menu\n'
    printf '--------------------\n'
    printf '  %2s) %s\n' "Q" "Quit"
    printf '  %2s) %s\n' "R" "Refresh list"
    if [ -n "$legacy_tools" ]; then
      printf '  %2s) %s\n' "L" "Legacy scripts..."
    fi

    idx=1
    if [ -n "$modern_tools" ]; then
      printf '%s\n' "$modern_tools" | while IFS="$TAB" read -r display desc path key; do
        printf '  %2d) %s - %s\n' "$idx" "$display" "$desc"
        idx=$((idx + 1))
      done
    else
      printf '  -- No modern scripts discovered --\n'
    fi

    printf '\nSelect an option: '
    IFS= read -r choice || exit 0
    case $choice in
      [Qq])
        printf 'Exiting toolkit.\n'
        exit 0
        ;;
      [Rr])
        continue
        ;;
      [Ll])
        legacy_menu "$legacy_tools"
        continue
        ;;
      '')
        continue
        ;;
      *)
        if printf '%s' "$choice" | grep -Eq '^[0-9]+$'; then
          selected=$(echo "$modern_tools" | sed -n "${choice}p") || true
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
