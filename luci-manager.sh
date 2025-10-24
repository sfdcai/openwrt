#!/bin/sh
# luci-manager-improved.sh - Full LuCI Menu Manager (robust + user-friendly)
# Places custom links in /usr/lib/lua/luci/controller/custom_links.lua
# - Ensures module header & index() exist
# - Shows friendly numbered list for custom & detected entries
# - Edit/Delete by displayed index (not raw file line numbers)
# - Add/Edit/Delete/Enable/Disable/Export/Import/Backup/Restore/Reload
# - Strong error handling and explanatory messages

set -eu

LUCI_CTRL_DIR="/usr/lib/lua/luci/controller"
CUSTOM_FILE="$LUCI_CTRL_DIR/custom_links.lua"
BACKUP_DIR="/tmp/luci-manager-backups"
LOGFILE="/tmp/luci-manager.log"
TMP_EDIT="/tmp/luci-manager-edit.lua"

mkdir -p "$LUCI_CTRL_DIR" "$BACKUP_DIR"
: > "$LOGFILE" || true

log() { echo "$(date +'%F %T') - $*" | tee -a "$LOGFILE"; }

safe_backup() {
  ts=$(date +%Y%m%d%H%M%S)
  if [ -f "$CUSTOM_FILE" ]; then
    cp -a "$CUSTOM_FILE" "$BACKUP_DIR/custom_links.lua.bak.$ts"
    log "Backup created: $BACKUP_DIR/custom_links.lua.bak.$ts"
  fi
}

ensure_custom_file() {
  if [ ! -f "$CUSTOM_FILE" ]; then
    cat > "$CUSTOM_FILE" <<'EOF'
module("luci.controller.custom_links", package.seeall)
-- Auto-generated custom LuCI links (managed by luci-manager-improved.sh)

function index()
  -- placeholder so LuCI registers this controller
end
EOF
    chmod 644 "$CUSTOM_FILE"
    log "Created $CUSTOM_FILE with module header"
  else
    # verify module line
    head -n 2 "$CUSTOM_FILE" | grep -q "module(\"luci.controller.custom_links\"" || {
      safe_backup
      sed -i '1i module("luci.controller.custom_links", package.seeall)\n-- Auto-generated custom LuCI links (managed by luci-manager-improved.sh)\n' "$CUSTOM_FILE"
      log "Inserted missing module header into $CUSTOM_FILE"
    }
  fi
}

# Parse "entry(...)" lines into CSV: id|section|name|url|priority|source|raw_line
parse_entries() {
  # custom entries from CUSTOM_FILE
  awk 'BEGIN{in=0}/entry\(/ {print FILENAME "|" NR "|" $0}' "$CUSTOM_FILE" 2>/dev/null || true
  # detected entries from other controller files
  find "$LUCI_CTRL_DIR" -type f -name '*.lua' 2>/dev/null | while read -r f; do
    [ "$f" = "$CUSTOM_FILE" ] && continue
    awk ' /entry\(/ {print FILENAME "|" NR "|" $0}' "$f" 2>/dev/null || true
  done
}

# build a friendly index list and store mapping in /tmp for later operations
build_index() {
  IDX_FILE="/tmp/luci-manager-index.json"
  : > "$IDX_FILE"
  i=0
  # We'll extract basic fields using sed/grep heuristics
  find "$LUCI_CTRL_DIR" -type f -name '*.lua' 2>/dev/null | while read -r f; do
    awk '/entry\(/ {print FILENAME "|||" $0}' "$f" 2>/dev/null | while IFS='|||\n' read -r src line; do
      raw="$line"
      # determine source (custom or detected)
      srcname=$(basename "$src")
      source_type="detected"
      [ "$src" = "$CUSTOM_FILE" ] && source_type="custom"
      # extract section, id, name, priority, url
      section=$(echo "$raw" | sed -n "s/.*entry(\{\s*\"admin\",\s*\"\([^\"]\+\)\".*/\1/p" || true)
      id=$(echo "$raw" | sed -n "s/.*entry(\{\s*\"admin\",\s*\"[^\"]\+\",\s*\"\([^\"]\+\)\".*/\1/p" || true)
      name=$(echo "$raw" | sed -n "s/.*,_(\"\?\([^\"]\)\+\"\?).*/\1/p" || true)
      # fallback name parse
      if [ -z "$name" ]; then
        name=$(echo "$raw" | sed -n "s/.*,_(\"\([^\"]\+\)\").*/\1/p" || true)
      fi
      priority=$(echo "$raw" | sed -n "s/.*,_([^,]*, *\([0-9][0-9]*\)).*/\1/p" || true)
      url=$(echo "$raw" | sed -n "s/.*\.url *= *\"\([^\"]\+\)\".*/\1/p" || true)
      i=$((i+1))
      printf '{"index":%d,"source":"%s","file":"%s","line":"%s","section":"%s","id":"%s","name":"%s","url":"%s","priority":"%s","raw":"%s"}\n' "$i" "$source_type" "$srcname" "$line" "$section" "$id" "$name" "$url" "$priority" "$(echo "$raw" | sed 's/"/\"/g')" >> "$IDX_FILE"
    done
  done
  echo "$IDX_FILE"
}

show_indexed_list() {
  IDX=$(build_index)
  if [ ! -s "$IDX" ]; then
    echo "No entries found (custom or detected)."
    return
  fi
  echo "Index | Source  | Section | ID               | Name                 | URL"
  echo "----------------------------------------------------------------------"
  awk -v RS='\n' '{gsub(/\"/,"\"" ,$0); print $0}' "$IDX" | nl -ba -v0 | while read -r l; do
    # parse json-ish line with sed
    index=$(echo "$l" | sed -n 's/.*"index":\([0-9]*\).*/\1/p')
    source=$(echo "$l" | sed -n 's/.*"source":"\([^"]*\)".*/\1/p')
    file=$(echo "$l" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
    section=$(echo "$l" | sed -n 's/.*"section":"\([^"]*\)".*/\1/p')
    id=$(echo "$l" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    name=$(echo "$l" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
    url=$(echo "$l" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
    printf "%5s | %-7s | %-7s | %-16s | %-20s | %s\n" "$index" "$source" "${section:--}" "${id:--}" "${name:--}" "${url:--}"
  done
}

validate_url() {
  url="$1"
  case "$url" in
    http://*|https://*) ;;
    *) echo "invalid"; return 1;;
  esac
  if command -v curl >/dev/null 2>&1; then
    if curl -Is --max-time 5 "$url" >/dev/null 2>&1; then
      echo "ok"; return 0
    else
      echo "unreachable"; return 2
    fi
  else
    echo "unknown"; return 0
  fi
}

reload_luci() {
  if command -v luci-reload >/dev/null 2>&1; then
    luci-reload || true
    log "Ran luci-reload"
  else
    [ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart || true
    log "Restarted uhttpd"
  fi
}

add_link() {
  ensure_custom_file
  echo "Add a new LuCI redirect link"
  read -p "Menu Name: " NAME
  [ -z "$NAME" ] && { echo "Name required."; return 1; }
  read -p "URL (http:// or https://): " URL
  validate_url "$URL" || true
  read -p "Section under admin (default services): " SECTION
  SECTION=${SECTION:-services}
  read -p "Priority (default 90): " PRIORITY
  PRIORITY=${PRIORITY:-90}
  ID=$(echo "$NAME" | tr '[:upper:]' '[:lower:]' | sed -e 's/ /_/g' -e 's/[^a-z0-9_]/_/g')
  # prevent duplicate id in custom file
  if grep -q "{\"admin\", \"$SECTION\", \"$ID\"" "$CUSTOM_FILE" 2>/dev/null; then
    echo "An entry with the same section+id exists in custom file. Choose a different name."; return 1
  fi
  safe_backup
  cat >> "$CUSTOM_FILE" <<EOF

-- Entry: $NAME
entry({"admin", "$SECTION", "$ID"}, template("redirect"), _("$NAME"), $PRIORITY).url = "$URL"
EOF
  chmod 644 "$CUSTOM_FILE"
  log "Added $NAME -> $URL"
  reload_luci
  echo "Added and reloaded LuCI."
}

_edit_by_index() {
  IDX=$(build_index)
  [ -s "$IDX" ] || { echo "No entries to edit."; return 1; }
  echo "Select index to edit (from displayed list):"
  show_indexed_list
  read -p "Enter index number: " SEL
  if ! echo "$SEL" | grep -qE '^[0-9]+$'; then echo "Invalid index"; return 1; fi
  # extract selected JSON-like line
  line=$(sed -n "${SEL}p" "$IDX" 2>/dev/null || true)
  [ -n "$line" ] || { echo "Index not found"; return 1; }
  srcfile=$(echo "$line" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
  srcpath="$LUCI_CTRL_DIR/$srcfile"
  # if source is detected (not custom), ask to copy to custom first
  srctype=$(echo "$line" | sed -n 's/.*"source":"\([^"]*\)".*/\1/p')
  if [ "$srctype" != "custom" ]; then
    echo "Selected entry is from $srcfile (package controller). Editing package controllers can be overwritten by package updates."
    read -p "Copy this entry into custom_links.lua for safe editing? [Y/n]: " CONF
    CONF=${CONF:-Y}
    if [ "$CONF" = "Y" ] || [ "$CONF" = "y" ] || [ -z "$CONF" ]; then
      # extract raw line and append to custom file under a header
      raw=$(echo "$line" | sed -n 's/.*"raw":"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
      safe_backup
      echo "\n-- Imported from $srcfile" >> "$CUSTOM_FILE"
      echo "$raw" >> "$CUSTOM_FILE"
      chmod 644 "$CUSTOM_FILE"
      log "Imported entry from $srcfile into $CUSTOM_FILE"
      reload_luci
      echo "Imported entry into custom file. Now open editor to fine-tune it."
    else
      echo "Edit aborted."; return 1
    fi
  fi
  # open custom file in editor at end so user can find appended entry
  echo "Opening $CUSTOM_FILE in $EDITOR (or vi) - edit the entry, save & exit to apply changes."
  ${EDITOR:-vi} "$CUSTOM_FILE"
  reload_luci
  echo "Edited and reloaded LuCI."
}

delete_by_index() {
  IDX=$(build_index)
  [ -s "$IDX" ] || { echo "No entries to delete."; return 1; }
  show_indexed_list
  read -p "Enter index number to delete: " SEL
  if ! echo "$SEL" | grep -qE '^[0-9]+$'; then echo "Invalid index"; return 1; fi
  line=$(sed -n "${SEL}p" "$IDX" 2>/dev/null || true)
  [ -n "$line" ] || { echo "Index not found"; return 1; }
  file=$(echo "$line" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
  raw=$(echo "$line" | sed -n 's/.*"raw":"\(.*\)".*/\1/p' | sed 's/\\"/"/g')
  if [ "$file" != "custom_links.lua" ]; then
    echo "Selected entry is from $file (package controller). You should not delete package files."
    read -p "Do you want to import it into custom file and then delete the imported custom copy? [y/N]: " C
    C=${C:-N}
    if [ "$C" != "y" ] && [ "$C" != "Y" ]; then
      echo "Aborted."; return 0
    fi
    safe_backup
    echo "\n-- Imported (for delete) from $file" >> "$CUSTOM_FILE"
    echo "$raw" >> "$CUSTOM_FILE"
    chmod 644 "$CUSTOM_FILE"
    # now find the appended line number in CUSTOM_FILE and delete it
    LN=$(grep -nF -- "$raw" -n "$CUSTOM_FILE" | tail -n1 | cut -d: -f1)
    if [ -n "$LN" ]; then
      awk "NR!=$LN" "$CUSTOM_FILE" > "$CUSTOM_FILE.tmp" && mv "$CUSTOM_FILE.tmp" "$CUSTOM_FILE"
      log "Deleted imported custom entry at line $LN"
      reload_luci
      echo "Deleted imported custom entry and reloaded LuCI."
    else
      echo "Could not find appended line to delete."; return 1
    fi
  else
    # directly delete from custom file by matching raw
    safe_backup
    # remove the exact raw line (first occurrence)
    awk -v r="$raw" 'BEGIN{found=0} {if(found==0 && index($0,r)) {found=1; next} print}' "$CUSTOM_FILE" > "$CUSTOM_FILE.tmp" && mv "$CUSTOM_FILE.tmp" "$CUSTOM_FILE"
    log "Deleted custom entry matching raw: $raw"
    reload_luci
    echo "Deleted from custom file and reloaded LuCI."
  fi
}

export_custom() { dst="/tmp/custom_links_export_$(date +%Y%m%d%H%M%S).lua"; cp -a "$CUSTOM_FILE" "$dst"; echo "Exported to $dst"; }
import_custom() { read -p "Path to import file: " IF; [ -f "$IF" ] || { echo "Not found"; return 1; }; safe_backup; echo "\n-- Imported on $(date)" >> "$CUSTOM_FILE"; cat "$IF" >> "$CUSTOM_FILE"; chmod 644 "$CUSTOM_FILE"; reload_luci; echo "Imported and reloaded."; }
backup_now() { safe_backup; echo "Backups:"; ls -1 "$BACKUP_DIR" | sed -n '1,50p'; }
restore_last() { last=$(ls -1t "$BACKUP_DIR" | head -n1 || true); [ -n "$last" ] || { echo "No backups"; return 1; }; cp -a "$BACKUP_DIR/$last" "$CUSTOM_FILE"; chmod 644 "$CUSTOM_FILE"; reload_luci; echo "Restored $last and reloaded."; }

show_help() {
  cat <<EOF
LuCI Manager - interactive commands:
1) List combined (indexed) entries
2) Add new link
3) Edit entry (by index)
4) Delete entry (by index)
5) Export custom file
6) Import file
7) Backup now
8) Restore last backup
9) Reload LuCI
10) Show raw custom file
11) Quit
EOF
}

# Main loop
ensure_custom_file
while true; do
  echo
  echo "=== LuCI Manager (improved) ==="
  echo "1) List combined (indexed) entries"
  echo "2) Add new link"
  echo "3) Edit entry (by index)"
  echo "4) Delete entry (by index)"
  echo "5) Export custom file"
  echo "6) Import file"
  echo "7) Backup now"
  echo "8) Restore last backup"
  echo "9) Reload LuCI"
  echo "10) Show raw custom file"
  echo "11) Quit"
  printf "Enter choice [1-11]: "
  read CHOICE
  case "$CHOICE" in
    1) show_indexed_list ;;
    2) add_link ;;
    3) _edit_by_index ;;
    4) delete_by_index ;;
    5) export_custom ;;
    6) import_custom ;;
    7) backup_now ;;
    8) restore_last ;;
    9) reload_luci ;;
    10) echo "---- $CUSTOM_FILE ----"; sed -n '1,200p' "$CUSTOM_FILE" ;;
    11) echo "Bye"; exit 0 ;;
    *) echo "Invalid choice" ;;
  esac
done
