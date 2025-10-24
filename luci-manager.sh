#!/bin/sh
# === LuCI Manager (Final Stable Version) ===

DB_FILE="/etc/luci_custom_links.db"
LUA_FILE="/usr/lib/lua/luci/controller/custom_links.lua"
BACKUP_FILE="/etc/luci_custom_links.db.bak"

mkdir -p /usr/lib/lua/luci/controller 2>/dev/null

rebuild_lua() {
cat <<'EOF' > "$LUA_FILE"
module("luci.controller.custom_links", package.seeall)

function index()
    local i18n = require "luci.i18n"
    local http = require "luci.http"

    -- Always ensure visible parent
    entry({"admin", "services", "custom_links"}, firstchild(), i18n.translate("Custom Links"), 10).dependent = false

    local links = {}
    local f = io.open("/etc/luci_custom_links.db", "r")
    if f then
        for line in f:lines() do
            local name, url, section, priority = line:match("([^|]+)|([^|]+)|([^|]*)|([^|]*)")
            if name and url then
                table.insert(links, {
                    name = name,
                    url = url,
                    section = section ~= "" and section or "custom_links",
                    priority = tonumber(priority) or 90
                })
            end
        end
        f:close()
    end

    for _, link in ipairs(links) do
        local title = i18n.translate(link.name or "Custom Link")
        local target_url = link.url
        local section = "custom_links"
        local prio = link.priority

        entry({"admin", "services", section, link.name:lower()}, function()
            http.redirect(target_url)
        end, title, prio)
    end
end
EOF
}

list_links() {
    echo
    echo "Index | Name                 | URL"
    echo "-----------------------------------------------"
    [ -f "$DB_FILE" ] && awk -F"|" '{printf "%-5s | %-20s | %s\n", NR, $1, $2}' "$DB_FILE" || echo "No links found."
    echo
}

add_link() {
    echo
    printf "Menu name: "
    read name
    [ -z "$name" ] && echo "Name required!" && return
    printf "URL (http/https): "
    read url
    [ -z "$url" ] && echo "URL required!" && return
    printf "Section (default custom_links): "
    read section
    [ -z "$section" ] && section="custom_links"
    printf "Priority (default 90): "
    read priority
    [ -z "$priority" ] && priority="90"

    echo "${name}|${url}|${section}|${priority}" >> "$DB_FILE"
    echo "Added '$name' → $url"
    rebuild_lua
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    echo "LuCI reloaded. Visit: Services → Custom Links → ${name}"
}

delete_link() {
    list_links
    printf "Enter index or keyword to delete: "
    read sel
    [ -z "$sel" ] && return
    if echo "$sel" | grep -qE '^[0-9]+$'; then
        sed -i "${sel}d" "$DB_FILE"
    else
        grep -v "^${sel}|" "$DB_FILE" > "$DB_FILE.tmp" && mv "$DB_FILE.tmp" "$DB_FILE"
    fi
    echo "Deleted entry: $sel"
    rebuild_lua
    /etc/init.d/uhttpd restart >/dev/null 2>&1
}

backup_links() {
    cp "$DB_FILE" "$BACKUP_FILE" 2>/dev/null && echo "Backup created: $BACKUP_FILE" || echo "Nothing to backup."
}

restore_backup() {
    [ -f "$BACKUP_FILE" ] && cp "$BACKUP_FILE" "$DB_FILE" && echo "Backup restored." || echo "No backup found."
    rebuild_lua
    /etc/init.d/uhttpd restart >/dev/null 2>&1
}

show_raw() {
    echo
    [ -f "$LUA_FILE" ] && cat "$LUA_FILE" || echo "No Lua file yet."
    echo
}

while true; do
    echo
    echo "=== LuCI Manager (Final Stable Version) ==="
    echo "1) List links"
    echo "2) Add link"
    echo "3) Delete link"
    echo "4) Backup links"
    echo "5) Restore backup"
    echo "6) Show raw Lua file"
    echo "7) Quit"
    printf "Enter choice [1-7]: "
    read c
    case "$c" in
        1) list_links ;;
        2) add_link ;;
        3) delete_link ;;
        4) backup_links ;;
        5) restore_backup ;;
        6) show_raw ;;
        7) echo "Goodbye."; exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
done
