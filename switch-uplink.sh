#!/bin/bash
# Toont de uplink-status van de ToetsLocker AP.
#
# Handmatig wisselen is niet meer nodig: de firewall staat beide uplinks
# (eth0 en wlan0) toe en de kernel-routing kiest automatisch — eth0 wint
# van wlan0 via een lagere route-metric zodra er een kabel in zit.
# De uplink-monitor service logt wissels en flusht stale conntrack-entries.
set -euo pipefail

CONF=/etc/toetslocker.conf

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[--]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }

if [[ $# -gt 0 ]]; then
    warn "Handmatig wisselen is vervallen — de uplink volgt automatisch de routing."
    warn "eth0 met kabel wint altijd van wlan0; trek de kabel eruit om terug te vallen."
    echo ""
fi

echo ""
info "Uplink status:"

for iface in eth0 wlan0; do
    carrier=$(cat "/sys/class/net/${iface}/carrier" 2>/dev/null || echo 0)
    ip4=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2; exit}')
    if [[ "$carrier" == "1" && -n "$ip4" ]]; then
        ok "  ${iface}: link actief, IP ${ip4}"
    elif [[ "$carrier" == "1" ]]; then
        warn "  ${iface}: link actief, geen IP"
    else
        info "  ${iface}: geen link"
    fi
done

ACTIVE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
[[ -n "$ACTIVE" ]] \
    && ok "  Actieve uplink (default route): ${ACTIVE}" \
    || warn "  Geen default route — geen internetverbinding"

if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
    info "  Geregistreerd in ${CONF}: ${UPLINK_IFACE:-onbekend}"
fi
echo ""
