#!/bin/sh
# ==========================================================
# AdGuardHome RAM Runtime v2 (Idempotent)
# - Keeps YAML untouched; moves runtime to /tmp/adghome
# - Adds nightly sync to /var/lib/adguardhome and restore-on-boot
# - Injects fallback to USB if /tmp not available
# - Auto-installs rsync if missing
# Tested: OpenWrt/ImmortalWRT 24.x, WRT1900ACS
# ==========================================================

set -e

# ---- Config ----
UCI_PKG="adguardhome"
UCI_SECTION="config"
UCI_OPT_WORKDIR="workdir"
CFG_FILE="/etc/config/adguardhome"
INIT_FILE="/etc/init.d/adguardhome"
CRON_FILE="/etc/crontabs/root"
RC_LOCAL="/etc/rc.local"
RAM_DIR="/tmp/adghome"
USB_DIR="/var/lib/adguardhome"
PID_FILE="/run/adguardhome.pid"
SELFTEST_LOG="$RAM_DIR/adguardhome-selftest.log"
TEST_DOMAIN="openwrt.org"

log(){ echo "[+] $*"; }
warn(){ echo "[!] $*"; }
err(){ echo "[x] $*"; exit 1; }

require_file(){
  [ -f "$1" ] || err "Missing file: $1"
}

# ---- 0) Pre-flight sanity ----
require_file "$INIT_FILE"
[ -f "$CFG_FILE" ] || { warn "$CFG_FILE missing; creating bare config stub"; cat >"$CFG_FILE" <<EOF
config adguardhome $UCI_SECTION
        option config /etc/adguardhome.yaml
        option workdir $USB_DIR
        option pidfile $PID_FILE
EOF
}

# ---- 1) Ensure rsync ----
if ! command -v rsync >/dev/null 2>&1; then
  log "Installing rsync..."
  opkg update >/dev/null 2>&1 || warn "opkg update failed; trying install anyway"
  opkg install rsync >/dev/null 2>&1 || err "Couldn't install rsync; install it manually and re-run"
  log "rsync installed."
fi

# ---- 2) Read current workdir from UCI (fallback USB) ----
CUR_WD="$(uci -q get $UCI_PKG.$UCI_SECTION.$UCI_OPT_WORKDIR || true)"
[ -n "$CUR_WD" ] || CUR_WD="$USB_DIR"
log "Current UCI workdir: $CUR_WD"

# ---- 3) Stop service cleanly ----
log "Stopping AdGuardHome..."
/etc/init.d/adguardhome stop >/dev/null 2>&1 || true
sleep 1
rm -f "$PID_FILE" >/dev/null 2>&1 || true

# ---- 4) Make RAM dir and preload from current workdir (if exists) ----
log "Preloading RAM workdir from $CUR_WD ..."
mkdir -p "$RAM_DIR"
if [ -d "$CUR_WD" ] && [ "$(ls -A "$CUR_WD" 2>/dev/null)" ]; then
  rsync -a "$CUR_WD"/ "$RAM_DIR"/
else
  warn "No data in $CUR_WD (first-time run is fine)."
fi

# ---- 5) Point UCI workdir to RAM (idempotent) ----
log "Setting UCI $UCI_PKG.$UCI_SECTION.$UCI_OPT_WORKDIR = $RAM_DIR"
uci set $UCI_PKG.$UCI_SECTION.$UCI_OPT_WORKDIR="$RAM_DIR"
uci commit $UCI_PKG

# ---- 6) Inject safe fallback into init script (only if missing) ----
if ! grep -q '\[ ! -d "\$WORK_DIR" \] && WORK_DIR="/var/lib/adguardhome"' "$INIT_FILE"; then
  log "Injecting fallback to USB into init script..."
  # Insert right after config_get WORK_DIR line
  sed -i '/config_get WORK_DIR/ a [ ! -d "$WORK_DIR" ] \&\& WORK_DIR="\/var\/lib\/adguardhome"' "$INIT_FILE"
else
  log "Fallback already present in init script."
fi

# ---- 7) Ensure init uses UCI-driven command (procd) ----
# We don't hardcode -w here; init script uses procd with "$WORK_DIR" from UCI.
# Force procd to reload definition:
log "Re-registering service with procd..."
/etc/init.d/adguardhome disable >/dev/null 2>&1 || true
/etc/init.d/adguardhome enable  >/dev/null 2>&1 || true

# ---- 8) Start service from RAM workdir ----
log "Starting AdGuardHome..."
/etc/init.d/adguardhome start
sleep 3

PID="$(pidof AdGuardHome || true)"
[ -n "$PID" ] || err "AdGuardHome did not start; check init script and logs."

# ---- 9) Verify runtime command line shows -w /tmp/adghome ----
CMD_LINE="$(ps | awk '/AdGuardHome .* -c .* -w /{print $0}' | tail -1)"
echo "$CMD_LINE" | grep -q " -w $RAM_DIR " || {
  warn "Process not showing -w $RAM_DIR yet. Trying a hard restart..."
  /etc/init.d/adguardhome stop; sleep 1; /etc/init.d/adguardhome start; sleep 3
  CMD_LINE="$(ps | awk '/AdGuardHome .* -c .* -w /{print $0}' | tail -1)"
  echo "$CMD_LINE" | grep -q " -w $RAM_DIR " || err "Still not using $RAM_DIR. Inspect $INIT_FILE and /etc/config/adguardhome."
}
log "Runtime OK: $(echo "$CMD_LINE" | sed 's/^ *//')"

# ---- 10) Nightly sync cron (dedupe) ----
log "Ensuring nightly sync at 03:00..."
mkdir -p "$(dirname "$CRON_FILE")"
grep -v "rsync -a --delete $RAM_DIR/" "$CRON_FILE" 2>/dev/null > "$CRON_FILE.tmp" || true
echo "0 3 * * * rsync -a --delete $RAM_DIR/ $USB_DIR/" >> "$CRON_FILE.tmp"
mv "$CRON_FILE.tmp" "$CRON_FILE"
chmod 600 "$CRON_FILE"
/etc/init.d/cron restart >/dev/null 2>&1 || true

# ---- 11) Restore-on-boot via rc.local (dedupe, keep exit 0 last) ----
log "Ensuring restore-on-boot..."
TMP_RC="$(mktemp)"
grep -v "$USB_DIR/" "$RC_LOCAL" 2>/dev/null > "$TMP_RC" || true
grep -v "$RAM_DIR" "$TMP_RC" > "${TMP_RC}.2" || true
mv "${TMP_RC}.2" "$TMP_RC"
{
  echo "mkdir -p $RAM_DIR"
  echo "rsync -a $USB_DIR/ $RAM_DIR/ 2>/dev/null"
} >> "$TMP_RC"
# keep exit 0 at end
grep -q '^exit 0' "$TMP_RC" || echo "exit 0" >> "$TMP_RC"
mv "$TMP_RC" "$RC_LOCAL"
chmod +x "$RC_LOCAL"

# ---- 12) Self-test + diagnostics ----
log "Self-test DNS..."
mkdir -p "$RAM_DIR"
nslookup "$TEST_DOMAIN" 127.0.0.1 >"$SELFTEST_LOG" 2>&1 && log "DNS test OK." || warn "DNS test failed (see $SELFTEST_LOG)."

log "Ports check (53, 3000)..."
netstat -ntlp | grep -E 'AdGuardHome|:53|:3000' >>"$SELFTEST_LOG" 2>&1 || true

log "Snapshot -> $SELFTEST_LOG"
{
  echo "=== AdGuardHome RAM Runtime v2 Snapshot ==="
  date
  echo "\n--- UCI ---"
  uci show $UCI_PKG 2>/dev/null || true
  echo "\n--- Process ---"
  ps | grep [A]dGuardHome || true
  echo "\n--- Net Ports ---"
  netstat -ntlp | grep -E 'AdGuardHome|:53|:3000' || true
  echo "\n--- Disks ---"
  df -h | grep -E 'overlay|/tmp' || true
  echo "\n--- Mounts ---"
  mount | grep -E 'tmpfs|overlay' || true
  echo "\n--- Workdir sizes ---"
  du -sh "$RAM_DIR" 2>/dev/null || true
  du -sh "$USB_DIR" 2>/dev/null || true
  echo "\n--- Recent logread (AdGuardHome) ---"
  logread | grep -i adguardhome | tail -n 30 || true
} >> "$SELFTEST_LOG"

log "Done."
echo "==> RAM runtime: $RAM_DIR"
echo "==> Persistent backup: $USB_DIR"
echo "==> Self-test log: $SELFTEST_LOG"
