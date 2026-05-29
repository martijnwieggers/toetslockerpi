#!/bin/bash
# Dnsmasq query-logging uitschakelen

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Voer uit als root: sudo $0"

CONF=/etc/dnsmasq.d/ap.conf
[ -f "$CONF" ] || fail "Configuratiebestand niet gevonden: $CONF"

sed -i '/^log-queries/d' "$CONF"
sed -i '/^log-facility/d' "$CONF"

systemctl restart dnsmasq
ok "Logging uitgeschakeld"
