#!/bin/bash
# Wissel de uplink interface van de ToetsLocker AP zonder herinstallatie.
# Gebruik: sudo switch-uplink.sh [eth0|wlan0]
set -euo pipefail

CONF=/etc/toetslocker.conf
NFTABLES=/etc/nftables.conf

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[--]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Voer uit als root: sudo $0"
[[ -f "$CONF" ]] || fail "Configuratie niet gevonden: $CONF — voer install.sh opnieuw uit"
[[ -f "$NFTABLES" ]] || fail "nftables config niet gevonden: $NFTABLES"

# shellcheck source=/dev/null
source "$CONF"

# Geen argument: toon huidige instelling
if [[ $# -eq 0 ]]; then
    echo ""
    info "Huidige instellingen (${CONF}):"
    info "  Uplink:       ${UPLINK_IFACE}"
    info "  AP-interface: ${AP_IFACE}"
    info "  AP-IP:        ${AP_IP}"
    echo ""
    echo "  Gebruik: sudo $0 eth0   # naar ethernet"
    echo "           sudo $0 wlan0  # naar WiFi"
    echo ""
    exit 0
fi

NEW_UPLINK="$1"

if [[ "$NEW_UPLINK" == "$UPLINK_IFACE" ]]; then
    info "Uplink staat al ingesteld op ${UPLINK_IFACE} — niets te doen."
    exit 0
fi

# Controleer of het interface bestaat
ip link show "$NEW_UPLINK" &>/dev/null \
    || fail "Interface '${NEW_UPLINK}' niet gevonden — controleer 'ip link'"

# Waarschuw als het nieuwe interface geen carrier heeft
CARRIER=$(cat "/sys/class/net/${NEW_UPLINK}/carrier" 2>/dev/null || echo 0)
[[ "$CARRIER" == "1" ]] \
    || warn "Interface ${NEW_UPLINK} heeft geen actieve link — doorgaan kan SSH-verbinding verbreken"

OLD_UPLINK="$UPLINK_IFACE"
info "Wisselen van uplink: ${OLD_UPLINK} → ${NEW_UPLINK}"

# Schrijf de nieuwe uplink-definitie; nftables.conf leest dit via include.
# nftables.conf zelf wordt niet gewijzigd, zodat er geen sed-bijwerkingen zijn.
echo "define UPLINK = ${NEW_UPLINK}" > /etc/nftables.d/uplink.conf

# Valideer de config vóór herladen
nft -c -f "$NFTABLES" || fail "nftables config ongeldig — herstel handmatig: $NFTABLES"

nft -f "$NFTABLES"
ok "nftables herladen met uplink: ${NEW_UPLINK}"

# Config bijwerken
sed -i "s/^UPLINK_IFACE=.*/UPLINK_IFACE=${NEW_UPLINK}/" "$CONF"
ok "Configuratie bijgewerkt (${CONF})"

# Whitelist herladen: nftables-reload leegt de allowed_ips set; dnsmasq
# moet opnieuw starten zodat zijn nftset-regels opnieuw actief zijn.
if [[ -x /usr/local/bin/update-whitelist.sh ]]; then
    /usr/local/bin/update-whitelist.sh
    ok "Whitelist herladen (allowed_ips set opnieuw actief)"
fi

echo ""
ok "Uplink gewisseld naar: ${NEW_UPLINK}"
echo "  Verifieer bereikbaarheid: ping -c3 \$(ip route | awk '/default/{print \$3; exit}')"
echo ""
