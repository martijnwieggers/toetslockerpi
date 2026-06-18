#!/bin/bash
# install_8812au.sh — Controleert en installeert de RTL8812AU wifi driver
# Gebruik: sudo bash install_8812au.sh

set -e

MODULE="8812au"
REPO_URL="https://github.com/morrownr/8812au-20210820"
REPO_DIR="/usr/local/src/8812au-20210820"

echo "=== RTL8812AU driver check ==="

# Controleer of module al geladen is
if lsmod | grep -q "^${MODULE}"; then
    echo "[OK] Driver '${MODULE}' is al geladen en actief."
    exit 0
fi

# Controleer of module geïnstalleerd is (maar niet geladen)
if modinfo "${MODULE}" &>/dev/null; then
    echo "[OK] Driver '${MODULE}' is geïnstalleerd. Probeer te laden..."
    sudo modprobe "${MODULE}"
    echo "[OK] Driver geladen."
    exit 0
fi

echo "[INFO] Driver niet gevonden. Installatie starten..."

# Controleer root
if [[ $EUID -ne 0 ]]; then
    echo "[FOUT] Dit script moet als root uitgevoerd worden: sudo bash $0"
    exit 1
fi

# Benodigde pakketten installeren
echo "[INFO] Benodigde pakketten installeren..."
apt update -qq
apt install -y bc git dkms build-essential linux-headers-$(uname -r)

# Repo klonen of updaten
if [[ -d "${REPO_DIR}" ]]; then
    echo "[INFO] Bestaande broncode gevonden, updaten..."
    git -C "${REPO_DIR}" pull
else
    echo "[INFO] Broncode ophalen van GitHub..."
    git clone "${REPO_URL}" "${REPO_DIR}"
fi

# Driver compileren en installeren
cd "${REPO_DIR}"
echo "[INFO] Driver compileren en installeren via DKMS..."
./install-driver.sh NoPrompt

echo ""
echo "=== Installatie voltooid ==="
echo "De Pi wordt nu herstart. Na de reboot is de wifi adapter beschikbaar."
echo "Controleer daarna met: ip link show"
echo ""
read -rp "Druk op Enter om te herstarten, of Ctrl+C om te annuleren..."
reboot
