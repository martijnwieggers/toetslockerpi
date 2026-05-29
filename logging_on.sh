#!/bin/bash
# Dnsmasq query-logging inschakelen

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[--]${NC} $1"; }
fail() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Voer uit als root: sudo $0"

CONF=/etc/dnsmasq.d/ap.conf
[ -f "$CONF" ] || fail "Configuratiebestand niet gevonden: $CONF"

grep -q '^log-queries' "$CONF" || echo 'log-queries' >> "$CONF"
grep -q '^log-facility' "$CONF" || echo 'log-facility=/var/log/dnsmasq.log' >> "$CONF"

systemctl restart dnsmasq
ok "Logging ingeschakeld"
info "Live meekijken: sudo tail -f /var/log/dnsmasq.log"
