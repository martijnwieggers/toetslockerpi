#!/bin/bash
set -e
WHITELIST=/etc/whitelist.txt
OUTPUT=/etc/dnsmasq.d/whitelist.conf
UPSTREAM=8.8.8.8
[ -f "$WHITELIST" ] || { echo "Whitelist niet gevonden: $WHITELIST"; exit 1; }
{
    echo "# Automatisch gegenereerd op: $(date)"
    while IFS= read -r domain || [ -n "$domain" ]; do
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue
        domain="${domain#\*.}"
        echo "server=/${domain}/${UPSTREAM}"
        echo "nftset=/${domain}/4#inet#filter#allowed_ips,4#ip#custom_nat#captive_bypass"
    done < "$WHITELIST"
} | tee "$OUTPUT" > /dev/null
systemctl restart dnsmasq
COUNT=$(grep -c '^server=' "$OUTPUT" 2>/dev/null || echo 0)
echo "Whitelist bijgewerkt: ${COUNT} domein(en) geladen"

# Proactief alle domeinen oplossen zodat nftsets direct gevuld zijn
# na een uplink-wissel — zonder dit moeten clients zelf een DNS-query
# maken voordat hun IP in de nftset terechtkomt.
RESOLVED=0
while IFS= read -r domain || [ -n "$domain" ]; do
    [[ -z "$domain" || "$domain" =~ ^# ]] && continue
    domain="${domain#\*.}"
    dig +short "$domain" @127.0.0.1 > /dev/null 2>&1 && RESOLVED=$((RESOLVED + 1)) || true
done < "$WHITELIST"
echo "nftsets gevuld: ${RESOLVED} domein(en) proactief opgelost"
