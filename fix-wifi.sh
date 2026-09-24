#!/bin/bash

# Raspberry Pi 5 Wi-Fi fix
# - Disable Broadcom roaming
# - Disable selected brcmfmac features
# - Disable Wi-Fi power saving permanently

set -e

CMDLINE="/boot/firmware/cmdline.txt"
SERVICE="/etc/systemd/system/wlan0-powersave-off.service"

echo
echo "======================================"
echo " Raspberry Pi 5 Wi-Fi configuratie"
echo "======================================"
echo

# Root controleren
if [ "$EUID" -ne 0 ]; then
    echo "Dit script moet als root worden uitgevoerd."
    echo
    echo "Gebruik:"
    echo "  sudo ./wifi-fix.sh"
    exit 1
fi

# cmdline.txt controleren
if [ ! -f "$CMDLINE" ]; then
    echo "FOUT: $CMDLINE bestaat niet."
    exit 1
fi

echo "[1/4] Backup maken..."

BACKUP="${CMDLINE}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$CMDLINE" "$BACKUP"

echo "Backup gemaakt:"
echo "  $BACKUP"
echo

# Controleer of cmdline.txt uit één regel bestaat
LINES=$(wc -l < "$CMDLINE")

if [ "$LINES" -ne 1 ]; then
    echo "WAARSCHUWING: $CMDLINE bevat $LINES regels."
    echo "cmdline.txt hoort normaal uit één regel te bestaan."
    echo "Er worden geen wijzigingen gemaakt."
    exit 1
fi

echo "[2/4] brcmfmac parameters instellen..."

# brcmfmac.roamoff
if grep -q 'brcmfmac.roamoff=' "$CMDLINE"; then
    sed -i 's/brcmfmac\.roamoff=[^ ]*/brcmfmac.roamoff=1/' "$CMDLINE"
    echo "  brcmfmac.roamoff=1 bijgewerkt"
else
    sed -i 's/$/ brcmfmac.roamoff=1/' "$CMDLINE"
    echo "  brcmfmac.roamoff=1 toegevoegd"
fi

# brcmfmac.feature_disable
if grep -q 'brcmfmac.feature_disable=' "$CMDLINE"; then
    sed -i 's/brcmfmac\.feature_disable=[^ ]*/brcmfmac.feature_disable=0x282000/' "$CMDLINE"
    echo "  brcmfmac.feature_disable=0x282000 bijgewerkt"
else
    sed -i 's/$/ brcmfmac.feature_disable=0x282000/' "$CMDLINE"
    echo "  brcmfmac.feature_disable=0x282000 toegevoegd"
fi

echo

echo "[3/4] Wi-Fi power saving permanent uitschakelen..."

cat > "$SERVICE" <<'EOF'
[Unit]
Description=Disable Wi-Fi power saving on wlan0
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iw dev wlan0 set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wlan0-powersave-off.service

echo "  systemd-service geïnstalleerd."
echo

# Direct toepassen zonder reboot
echo "[4/4] Wi-Fi power saving nu uitschakelen..."

if iw dev wlan0 set power_save off 2>/dev/null; then
    echo "  Power saving: OFF"
else
    echo "  wlan0 is momenteel niet beschikbaar."
    echo "  Power saving wordt bij de volgende boot uitgeschakeld."
fi

echo
echo "======================================"
echo " Configuratie"
echo "======================================"
echo

echo "Kernel parameters:"
grep -o 'brcmfmac[^ ]*' "$CMDLINE" || true

echo
echo "Wi-Fi power saving:"
iw dev wlan0 get power_save 2>/dev/null || echo "Niet beschikbaar"

echo
echo "Systemd-service:"
systemctl is-enabled wlan0-powersave-off.service

echo
echo "======================================"
echo " Klaar"
echo "======================================"
echo
echo "Een reboot is nodig om de cmdline.txt"
echo "wijzigingen actief te maken."
echo
echo "Gebruik:"
echo "  sudo reboot"
echo
