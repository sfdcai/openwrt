#!/bin/sh
# luci_menu_manager_full.sh
# Full-feature LUCI Menu Manager for OpenWRT
# Interactive script to add, edit, delete, and list links in LUCI menu

set -e

LUA_DIR="/usr/lib/lua/luci/controller"
DEFAULT_SECTION="services"

echo "=== Full LUCI Menu Manager ==="

# Helper functions

get_filename() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr -cd '[:alnum:]_'
}

reload_luci() {
    echo "Reloading LUCI..."
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
    /etc/init.d/luci restart >/dev/null 2>&1 || true
}

list_controllers() {
    printf "%-25s %-50s %-15s %-30s\n" "Filename" "Menu Name" "Section" "URL"
    echo "----------------------------------------------------------------------------------------------------------------"
    for file in "$LUA_DIR"/*.lua; do
        [ -f "$file" ] || continue
        fname=$(basename "$file" .lua)
        menu=$(grep 'entry({' "$file" 2>/dev/null | sed -n 's/.*_\("\?\)\([^"]*\)\("\?\).*$/\2/p')
        section=$(grep 'entry({' "$file" 2>/dev/null | sed -n 's/.*{"admin","\([^"]*\)".*/\1/p' | head -n1)
        url=$(grep 'http.redirect' "$file" 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p')
        printf "%-25s %-50s %-15s %-30s\n" "$fname" "$menu" "$section" "$url"
    done
}

select_controller() {
    list_controllers
    read -rp "Enter the filename (without .lua): " fname
    FULL_PATH="$LUA_DIR/$fname.lua"
    if [ ! -f "$FULL_PATH" ]; then
        echo "Error: File not found."
        return 1
    fi
    echo "$fname"
}

# Main menu
while true; do
    echo ""
    echo "Select action:"
    echo " 1) List existing links"
    echo " 2) Add a new link"
    echo " 3) Edit existing link"
    echo " 4) Delete a link"
    echo " 5) Exit"
    read -rp "Enter choice [1-5]: " ACTION

    case "$ACTION" in
    1)
        echo ""
        list_controllers
        ;;
    2)
        echo ""
        # ADD LINK
        while true; do
            read -rp "Enter Menu Name: " MENU_NAME
            [ -n "$MENU_NAME" ] && break
            echo "Menu Name cannot be empty."
        done

        while true; do
            read -rp "Enter URL (http:// or https://): " TARGET_URL
            echo "$TARGET_URL" | grep -Eq '^https?://'
            [ $? -eq 0 ] && break
            echo "Invalid URL."
        done

        read -rp "Enter Section (default: $DEFAULT_SECTION): " SECTION
        SECTION="${SECTION:-$DEFAULT_SECTION}"

        FILENAME=$(get_filename "$MENU_NAME")
        FULL_PATH="$LUA_DIR/$FILENAME.lua"

        if [ -f "$FULL_PATH" ]; then
            echo "Existing controller found. Backing up..."
            mv "$FULL_PATH" "${FULL_PATH}.bak_$(date +%Y%m%d%H%M%S)"
        fi

        cat > "$FULL_PATH" <<EOF
module("luci.controller.${FILENAME}", package.seeall)

function index()
    entry({"admin","$SECTION","$FILENAME"}, call("redirect"), _("$MENU_NAME"), 50)
end

function redirect()
    local http = require "luci.http"
    http.redirect("$TARGET_URL")
end
EOF

        chmod 644 "$FULL_PATH"
        reload_luci
        echo "✅ Link added successfully. Router reboot may be required to reflect changes."
        ;;
    3)
        echo ""
        # EDIT LINK
        fname=$(select_controller) || continue
        FULL_PATH="$LUA_DIR/$fname.lua"
        cp "$FULL_PATH" "${FULL_PATH}.bak_$(date +%Y%m%d%H%M%S)"

        CUR_MENU=$(grep 'entry({' "$FULL_PATH" | sed -n 's/.*_\("\?\)\([^"]*\)\("\?\).*$/\2/p')
        CUR_SECTION=$(grep 'entry({' "$FULL_PATH" | sed -n 's/.*{"admin","\([^"]*\)".*/\1/p' | head -n1)
        CUR_URL=$(grep 'http.redirect' "$FULL_PATH" | sed -n 's/.*"\(.*\)".*/\1/p')

        read -rp "New Menu Name (current: $CUR_MENU, leave empty to keep): " MENU_NAME
        MENU_NAME="${MENU_NAME:-$CUR_MENU}"

        while true; do
            read -rp "New URL (current: $CUR_URL, leave empty to keep): " TARGET_URL
            TARGET_URL="${TARGET_URL:-$CUR_URL}"
            echo "$TARGET_URL" | grep -Eq '^https?://'
            [ $? -eq 0 ] && break
            echo "Invalid URL."
        done

        read -rp "New Section (current: $CUR_SECTION, leave empty to keep): " SECTION
        SECTION="${SECTION:-$CUR_SECTION}"

        cat > "$FULL_PATH" <<EOF
module("luci.controller.${fname}", package.seeall)

function index()
    entry({"admin","$SECTION","$fname"}, call("redirect"), _("$MENU_NAME"), 50)
end

function redirect()
    local http = require "luci.http"
    http.redirect("$TARGET_URL")
end
EOF

        chmod 644 "$FULL_PATH"
        reload_luci
        echo "✅ Link edited successfully. Router reboot may be required to reflect changes."
        ;;
    4)
        echo ""
        # DELETE LINK
        fname=$(select_controller) || continue
        FULL_PATH="$LUA_DIR/$fname.lua"
        mv "$FULL_PATH" "${FULL_PATH}.bak_$(date +%Y%m%d%H%M%S)"
        reload_luci
        echo "✅ Link deleted successfully. Backup created. Router reboot may be required to reflect changes."
        ;;
    5)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid choice. Please select 1-5."
        ;;
    esac
done
