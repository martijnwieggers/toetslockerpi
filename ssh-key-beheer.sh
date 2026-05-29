#!/bin/bash
# SSH key beheer voor Git koppeling

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[--]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

list_keys() {
    echo ""
    info "Aanwezige SSH keys in $SSH_DIR:"
    echo ""
    local found=0
    for pubkey in "$SSH_DIR"/*.pub; do
        [ -f "$pubkey" ] || continue
        echo "  • $(basename "$pubkey" .pub)"
        found=1
    done
    [[ $found -eq 0 ]] && warn "Geen SSH keys gevonden."
    echo ""
}

show_public_key() {
    list_keys
    read -rp "Naam van de key: " KEYNAME
    local pubkey="$SSH_DIR/${KEYNAME}.pub"
    if [[ -f "$pubkey" ]]; then
        echo ""
        ok "Public key voor '${KEYNAME}':"
        echo ""
        cat "$pubkey"
        echo ""
        info "Kopieer bovenstaande sleutel naar GitHub → Settings → SSH keys → New SSH key"
    else
        warn "Key '${KEYNAME}' niet gevonden."
    fi
    echo ""
}

create_key() {
    echo ""
    read -rp "Naam voor de nieuwe SSH key (bijv. 'raspberry-pi'): " KEYNAME
    [[ -z "$KEYNAME" ]] && { warn "Naam mag niet leeg zijn."; return; }

    local keyfile="$SSH_DIR/${KEYNAME}"

    if [[ -f "$keyfile" ]]; then
        warn "Key '${KEYNAME}' bestaat al."
        read -rp "Overschrijven? [j/N]: " CONFIRM
        [[ "${CONFIRM,,}" == "j" ]] || { info "Gestopt."; return; }
    fi

    ssh-keygen -t ed25519 -f "$keyfile" -C "${KEYNAME}" -N ""
    chmod 600 "$keyfile"
    chmod 644 "${keyfile}.pub"

    # ~/.ssh/config bijwerken zodat GitHub de juiste key gebruikt
    local sshconfig="$SSH_DIR/config"
    if grep -q "^Host github.com" "$sshconfig" 2>/dev/null; then
        # Bestaand github.com blok vervangen
        sed -i '/^Host github\.com/,/^$/d' "$sshconfig"
        warn "Bestaande GitHub SSH config vervangen."
    fi
    cat >> "$sshconfig" << EOF

Host github.com
  HostName github.com
  User git
  IdentityFile ${keyfile}
EOF
    chmod 600 "$sshconfig"

    echo ""
    ok "Key aangemaakt: ${keyfile}"
    ok "SSH config bijgewerkt: github.com gebruikt deze key"
    echo ""
    echo "================================================================"
    ok "Public key — kopieer dit naar GitHub:"
    echo "================================================================"
    echo ""
    cat "${keyfile}.pub"
    echo ""
    echo "================================================================"
    info "GitHub → Settings → SSH and GPG keys → New SSH key → plak bovenstaande sleutel"
    echo ""
    info "Verbinding testen na toevoegen aan GitHub:"
    info "  ssh -T git@github.com"
    echo ""
}

while true; do
    echo ""
    echo "============================================"
    echo " SSH Key Beheer"
    echo "============================================"
    echo ""
    echo "  1) Nieuwe SSH key aanmaken"
    echo "  2) Lijst van SSH keys tonen"
    echo "  3) Public key tonen"
    echo "  0) Afsluiten"
    echo ""
    read -rp "Keuze: " CHOICE

    case "$CHOICE" in
        1) create_key ;;
        2) list_keys ;;
        3) show_public_key ;;
        0) info "Tot ziens."; exit 0 ;;
        *) warn "Ongeldige keuze." ;;
    esac
done
