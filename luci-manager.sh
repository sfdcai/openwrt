#!/bin/sh
# LuCI Manager - BusyBox & modern LuCI compatible
# Fully enhanced with proper redirect functions
# Backups, reload, add, delete, list, raw file

LUCI_DIR="/usr/lib/lua/luci/controller"
CUSTOM="$LUCI_DIR/custom_links.lua"
BACKUP_DIR="/tmp/luci-manager-backups"

mkdir -p "$LUCI_DIR" "$BACKUP_DIR"

log() {
    echo "$(date '+%F %T') $*" >> /tmp/luci-manager.log
}

safe_backup() {
    [ -f "$CUSTOM" ] || return 0
    TS="$(date +%Y%m%d%H%M%S)"
    cp "$CUSTOM" "$BACKUP_DIR/custom_links.lua.bak.$TS"
    log "Backup saved: $BACKUP_DIR/custom_links.lua.bak.$TS"
}

ensure_file() {
    if [ ! -f "$CUSTOM" ] || ! grep -q 'module("luci.controller.custom_links"' "$CUSTOM" 2>/dev/null; then
        safe_backup
        echo 'module("luci.controller.custom_links", package.seeall)' > "$CUSTOM"
        echo 'function index() end' >> "$CUSTOM"
        echo "-- Managed by luci-manager" >> "$CUSTOM"
        chmod 644 "$CUSTOM"
        log "Created base file $CUSTOM"
    fi
}

reload_luci() {
    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart >/dev/null 2>&1
        log "Reloaded LuCI via uhttpd"
    fi
}

normalize() {
    echo "$1" | tr '[:upper:] ' '[:lower:]_' | sed 's/[^a-z0-9_]//g'
}

list_entries() {
    echo "Index | File | Section | ID | Name | URL"
    echo "-------------------------------------------------------------"
    I=0
    for F in "$LUCI_DIR"/*.lua; do
        [ -f "$F" ] || continue
        grep -H 'entry({' "$F" | while IFS= read -r L; do
            I=$((I+1))
            SEC=$(echo "$L" | sed -n 's/.*entry({ *"admin", *"\([^"]*\)".*/\1/p')
            ID=$(echo "$L" | sed -n 's/.*entry({ *"admin", *"[^"]*", *"\([^"]*\)".*/\1/p')
            NAME=$(echo "$L" | sed -n 's/.*_("\([^"]*\)").*/\1/p')
            URL=$(echo "$L" | sed -n 's/.*luci\.http\.redirect("\([^"]*\)")/\1/p')
            [ -z "$URL" ] && URL=$(echo "$L" | sed -n 's/.*url *= *"\([^"]*\)".*/\1/p')
            printf "%3d | %-18s | %-10s | %-12s | %-20s | %s\n" "$I" "$(basename "$F")" "$SEC" "$ID" "$NAME" "${URL:--}"
        done
    done
}

add_link() {
    ensure_file
    printf "Menu name: "
    read NAME
    [ -z "$NAME" ] && echo "Name required" && return
    printf "URL (http/https): "
    read URL
    [ -z "$URL" ] && echo "URL required" && return
    printf "Section (default services): "
    read SECTION
    [ -z "$SECTION" ] && SECTION="services"
    printf "Priority (default 90): "
    read PRIO
    [ -z "$PRIO" ] && PRIO="90"
    ID=$(normalize "$NAME")

    if grep -q "\"$SECTION\", *\"$ID\"" "$CUSTOM" 2>/dev/null; then
        echo "Entry already exists"
        return
    fi

    safe_backup
    {
        echo ""
        echo "-- $NAME"
        echo "entry({\"admin\",\"$SECTION\",\"$ID\"}, call(\"redirect_$ID\"), _(\"$NAME\"),$PRIO)"
        echo "function redirect_$ID() luci.http.redirect(\"$URL\") end"
    } >> "$CUSTOM"

    echo "Added '$NAME' -> $URL"
    log "Added $NAME -> $URL"
    reload_luci
}

delete_entry() {
    echo "Enter keyword (name or id) to delete:"
    read KEY
    [ -z "$KEY" ] && echo "Nothing entered" && return
    safe_backup
    TMP=/tmp/custom.tmp
    grep -v "$KEY" "$CUSTOM" > "$TMP" || true
    mv "$TMP" "$CUSTOM"
    chmod 644 "$CUSTOM"
    echo "Deleted lines containing '$KEY'."
    log "Deleted $KEY"
    reload_luci
}

show_file() {
    echo "------ $CUSTOM ------"
    cat "$CUSTOM" 2>/dev/null || echo "(empty)"
    echo "----------------------"
}

while true; do
    echo
    echo "=== LuCI Manager (BusyBox Final) ==="
    echo "1) List entries"
    echo "2) Add new link"
    echo "3) Delete link (by keyword)"
    echo "4) Show custom file"
    echo "5) Quit"
    printf "Enter choice [1-5]: "
    read CH
    case "$CH" in
        1) list_entries ;;
        2) add_link ;;
        3) delete_entry ;;
        4) show_file ;;
        5) echo "Bye"; exit 0 ;;
        *) echo "Invalid choice" ;;
    esac
done
