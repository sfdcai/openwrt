#!/bin/sh
# LuCI Manager - Modern + BusyBox Safe (final)
# Generates valid redirect functions for each menu

LUCI_DIR="/usr/lib/lua/luci/controller"
CUSTOM="$LUCI_DIR/custom_links.lua"
BACKUP_DIR="/tmp/luci-manager-backups"

mkdir -p "$LUCI_DIR" "$BACKUP_DIR"

safe_backup() {
    [ -f "$CUSTOM" ] || return 0
    cp "$CUSTOM" "$BACKUP_DIR/custom_links.lua.$(date +%s).bak"
}

ensure_file() {
    if [ ! -f "$CUSTOM" ]; then
        echo 'module("luci.controller.custom_links", package.seeall)' > "$CUSTOM"
        echo 'function index() end' >> "$CUSTOM"
    fi
}

normalize() {
    echo "$1" | tr '[:upper:] ' '[:lower:]_' | sed 's/[^a-z0-9_]//g'
}

add_link() {
    ensure_file
    echo -n "Menu name: "
    read NAME
    [ -z "$NAME" ] && echo "Name required" && return
    echo -n "URL (http/https): "
    read URL
    [ -z "$URL" ] && echo "URL required" && return
    echo -n "Section (default services): "
    read SECTION
    [ -z "$SECTION" ] && SECTION="services"
    echo -n "Priority (default 90): "
    read PRIO
    [ -z "$PRIO" ] && PRIO="90"

    ID=$(normalize "$NAME")
    safe_backup

    # Remove existing entry if same ID exists
    sed -i "/$ID/d" "$CUSTOM"

    {
        echo ""
        echo "-- $NAME"
        echo "entry({\"admin\",\"$SECTION\",\"$ID\"}, call(\"redirect_$ID\"), _(\"$NAME\"),$PRIO)"
        echo "function redirect_$ID() luci.http.redirect(\"$URL\") end"
    } >> "$CUSTOM"

    echo "Added '$NAME' -> $URL"
    /etc/init.d/uhttpd restart >/dev/null 2>&1
}

list_links() {
    echo "Index | Section | ID | Name | URL"
    echo "---------------------------------------------"
    awk '
    /entry\(\{/ {
        i++
        if (match($0, /"admin","([^"]+)"/, a)) sec=a[1];
        if (match($0, /"admin","[^"]+","([^"]+)"/, b)) id=b[1];
        if (match($0, /_\("([^"]+)"\)/, c)) name=c[1];
        getline; if (match($0, /redirect\("([^"]+)"/, d)) url=d[1];
        printf("%3d | %-10s | %-10s | %-20s | %s\n", i, sec, id, name, url);
    }' "$CUSTOM"
}

delete_link() {
    echo -n "Enter keyword to delete: "
    read KEY
    [ -z "$KEY" ] && echo "Nothing entered" && return
    safe_backup
    awk -v k="$KEY" '
    BEGIN{del=0}
    /entry\(\{/ {
        if(index($0,k)) {del=1;next}
    }
    /function redirect_/ {
        if(del){next}
    }
    {if(!del) print $0}
    /end$/ {del=0}
    ' "$CUSTOM" > /tmp/custom.tmp
    mv /tmp/custom.tmp "$CUSTOM"
    chmod 644 "$CUSTOM"
    echo "Deleted lines containing '$KEY'"
    /etc/init.d/uhttpd restart >/dev/null 2>&1
}

show_file() {
    echo "------ $CUSTOM ------"
    cat "$CUSTOM"
    echo "----------------------"
}

while true; do
    echo
    echo "=== LuCI Manager (Final) ==="
    echo "1) List links"
    echo "2) Add link"
    echo "3) Delete link"
    echo "4) Show raw file"
    echo "5) Quit"
    echo -n "Enter choice [1-5]: "
    read CH
    case "$CH" in
        1) list_links ;;
        2) add_link ;;
        3) delete_link ;;
        4) show_file ;;
        5) exit 0 ;;
        *) echo "Invalid choice" ;;
    esac
done
