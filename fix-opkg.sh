#!/bin/sh

# Enhanced OpenWrt opkg repair utility
# -------------------------------------
# * Validates dependencies and environment before making changes
# * Offers command-line options for custom feeds file, NTP server, or skipping steps
# * Provides safe restore mode for previously created backups
# * Supports dry-run execution for auditing the actions that would occur

set -eu

DEFAULT_FEEDS_FILE="/etc/opkg/distfeeds.conf"
DEFAULT_BACKUP_SUFFIX=".bak"
DEFAULT_NTP_SERVER="pool.ntp.org"

FEEDS_FILE="$DEFAULT_FEEDS_FILE"
BACKUP_FILE=""
NTP_SERVER="$DEFAULT_NTP_SERVER"
SKIP_NTP=0
HTTP_ONLY=0
DRY_RUN=0
RESTORE_ONLY=0

COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

log() {
    printf "%s[INFO]%s %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$1"
}

log_success() {
    printf "%s[SUCCESS]%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$1"
}

log_warn() {
    printf "%s[WARN]%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$1"
}

log_error() {
    printf "%s[ERROR]%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$1" >&2
}

usage() {
    cat <<'EOF'
Usage: fix-opkg.sh [options]

Repair HTTPS-related opkg update issues by temporarily switching to HTTP,
installing CA certificates, and restoring secure feeds.

Options:
  -f, --feeds-file PATH   Path to distfeeds configuration (default: /etc/opkg/distfeeds.conf)
  -b, --backup PATH       Custom backup destination. Defaults to PATH.bak.
  -n, --ntp-server HOST   NTP server for time sync (default: pool.ntp.org)
      --skip-ntp          Skip time synchronisation step.
      --http-only         Leave feeds configured for HTTP after the fix.
      --dry-run           Show planned actions without applying changes.
      --restore           Restore the most recent backup and exit.
  -h, --help              Show this help message.

Examples:
  fix-opkg.sh
  fix-opkg.sh --feeds-file /etc/opkg/customfeeds.conf --ntp-server time.google.com
  fix-opkg.sh --restore
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Required command '$1' not found. Please install it first."
        exit 1
    fi
}

ensure_writable() {
    local path="$1"
    local dir
    dir=$(dirname "$path")

    if [ -e "$path" ] && [ ! -w "$path" ]; then
        log_error "File $path is not writable. Run as root."
        exit 1
    fi

    if [ ! -w "$dir" ]; then
        log_error "Directory $dir is not writable. Run as root."
        exit 1
    fi
}

restore_backup() {
    local backup="$1"
    local dest="$2"

    if [ ! -f "$backup" ]; then
        log_error "No backup found at $backup"
        exit 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Would restore backup $backup to $dest"
        return 0
    fi

    cp "$backup" "$dest"
    log_success "Restored feeds configuration from $backup"
}

backup_file() {
    local source="$1"
    local backup="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Would create backup $backup from $source"
        return 0
    fi

    cp "$source" "$backup"
    log_success "Backup saved to $backup"
}

replace_scheme() {
    local file="$1"
    local from="$2"
    local to="$3"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Would replace '$from' with '$to' in $file"
        return 0
    fi

    sed -i "s/${from}:/${to}:/g" "$file"
}

run_opkg() {
    local label="$1"
    shift

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Would run: opkg $*"
        return 0
    fi

    if ! opkg "$@"; then
        log_error "$label failed."
        exit 1
    fi
    log_success "$label succeeded."
}

sync_time() {
    if [ "$SKIP_NTP" -eq 1 ]; then
        log_warn "Skipping NTP sync as requested."
        return 0
    fi

    require_command ntpd

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Would run: ntpd -q -p $NTP_SERVER"
        return 0
    fi

    if ntpd -q -p "$NTP_SERVER"; then
        log_success "Time synchronised via $NTP_SERVER"
        date
    else
        log_warn "Failed to sync time with $NTP_SERVER. Continuing regardless."
    fi
}

parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -f|--feeds-file)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                FEEDS_FILE="$2"
                shift 2
                ;;
            -b|--backup)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                BACKUP_FILE="$2"
                shift 2
                ;;
            -n|--ntp-server)
                [ $# -lt 2 ] && { log_error "Missing value for $1"; exit 1; }
                NTP_SERVER="$2"
                shift 2
                ;;
            --skip-ntp)
                SKIP_NTP=1
                shift
                ;;
            --http-only)
                HTTP_ONLY=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --restore)
                RESTORE_ONLY=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    require_command opkg
    ensure_writable "$FEEDS_FILE"

    if [ ! -f "$FEEDS_FILE" ]; then
        log_error "Feeds file $FEEDS_FILE not found."
        exit 1
    fi

    if [ -z "$BACKUP_FILE" ]; then
        BACKUP_FILE="${FEEDS_FILE}${DEFAULT_BACKUP_SUFFIX}"
    fi

    if [ "$RESTORE_ONLY" -eq 1 ]; then
        restore_backup "$BACKUP_FILE" "$FEEDS_FILE"
        exit 0
    fi

    log "Starting OpenWrt opkg fix"

    sync_time

    if [ ! -f "$BACKUP_FILE" ]; then
        backup_file "$FEEDS_FILE" "$BACKUP_FILE"
    else
        log_warn "Backup $BACKUP_FILE already exists and will be reused."
    fi

    log "Temporarily switching feeds to HTTP"
    replace_scheme "$FEEDS_FILE" "https" "http"

    run_opkg "opkg update (HTTP)" update

    run_opkg "Installing ca-certificates" install ca-certificates

    if [ "$HTTP_ONLY" -eq 1 ]; then
        log_warn "Leaving feeds configured for HTTP as requested."
    else
        log "Restoring feeds to HTTPS"
        replace_scheme "$FEEDS_FILE" "http" "https"
        run_opkg "opkg update (HTTPS)" update
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log_warn "Dry-run completed. No changes were made."
    else
        log_success "opkg fix completed successfully."
    fi
}

main "$@"
