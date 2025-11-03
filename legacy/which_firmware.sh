#!/bin/sh
# Linksys WRT1900/3200/32X Dual-Firmware Slot Detector
echo "=== ACTIVE FIRMWARE SLOT (Linksys Dual Image) ==="
CMDLINE=$(cat /proc/cmdline 2>/dev/null)
ROOTDEV=$(echo "$CMDLINE" | sed -n 's/.*root=\([^ ]*\).*/\1/p')

case "$ROOTDEV" in
  *mtdblock6*|*mtdblock7*)
    SLOT="Primary (kernel/rootfs A)"
    ;;
  *mtdblock8*|*mtdblock9*)
    SLOT="Alternate (kernel/rootfs B)"
    ;;
  *)
    SLOT="Unknown — root=$ROOTDEV"
    ;;
esac

echo "Root device: $ROOTDEV"
echo "Boot slot:   $SLOT"
echo "Cmdline:     $CMDLINE"
echo
MARKER="/etc/current_slot_marker.txt"
echo "marker-from-$(date +%Y%m%d-%H%M%S)-$SLOT" > "$MARKER"
sync
echo "Marker file created: $MARKER"
echo "If it persists after reboot → same slot."
