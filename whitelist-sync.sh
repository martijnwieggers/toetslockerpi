#!/bin/bash
# Haalt whitelist.txt op van GitHub en past hem alleen toe als er iets
# gewijzigd is. Draait periodiek via whitelist-sync.timer — veilig om vaak
# te draaien: dnsmasq wordt uitsluitend herstart bij een echte wijziging.
set -euo pipefail

URL="https://raw.githubusercontent.com/martijnwieggers/toetslockerpi/main/whitelist.txt"
WHITELIST=/etc/whitelist.txt
MARKER="# Whitelist voor ToetsLocker AP"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

curl -fsSL --max-time 30 "$URL" -o "$TMP" \
    || { echo "Download mislukt: $URL — whitelist ongewijzigd"; exit 1; }

# Validatie: niet leeg en bevat de vaste headerregel. Voorkomt dat een
# foutpagina of half gedownload bestand de whitelist vervangt.
[ -s "$TMP" ] \
    || { echo "Download is leeg — whitelist ongewijzigd"; exit 1; }
grep -qF "$MARKER" "$TMP" \
    || { echo "Headerregel ontbreekt in download — whitelist ongewijzigd"; exit 1; }

if [ -f "$WHITELIST" ] && cmp -s "$TMP" "$WHITELIST"; then
    echo "Whitelist ongewijzigd — niets te doen"
    exit 0
fi

[ -f "$WHITELIST" ] && cp "$WHITELIST" "${WHITELIST}.bak"
install -m 644 "$TMP" "$WHITELIST"
echo "Nieuwe whitelist geplaatst (backup: ${WHITELIST}.bak)"
/usr/local/bin/update-whitelist.sh
