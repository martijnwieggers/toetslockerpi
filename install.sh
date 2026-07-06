#!/bin/bash
# versie 7
# Bij curl | bash leest bash het script via stdin; read-prompts lezen dan ook
# van de pipe i.p.v. het toetsenbord. Oplossing: schrijf het script naar een
# temp-bestand en herstart van daaruit zodat stdin de terminal is.
[ -t 0 ] || { T=$(mktemp); { printf '#!/bin/bash\n'; cat; } > "$T"; bash "$T"; EC=$?; rm -f "$T"; exit $EC; }
# =============================================================================
# ToetsLocker AP Setup Script
# Raspberry Pi 5 — Raspberry Pi OS Lite (Debian Trixie)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[--]${NC} $1"; }
warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
fail() { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && fail "Voer uit als root: sudo $0"

# =============================================================================
# CONFIGURATIE
# =============================================================================
echo ""
echo "============================================"
echo " ToetsLocker AP Setup"
echo "============================================"
echo ""

# Laad bestaande AP-instellingen als defaults
_DEF_SSID="ToetsLocker"; _DEF_PASS=""; _DEF_COUNTRY="NL"
if [[ -f /etc/toetslocker.conf ]]; then
    _v=$(grep '^SSID='      /etc/toetslocker.conf 2>/dev/null | cut -d= -f2- || true)
    [[ -n "$_v" ]] && _DEF_SSID="$_v" || true
    _v=$(grep '^WIFI_PASS=' /etc/toetslocker.conf 2>/dev/null | cut -d= -f2- || true)
    [[ -n "$_v" ]] && _DEF_PASS="$_v" || true
    _v=$(grep '^COUNTRY='   /etc/toetslocker.conf 2>/dev/null | cut -d= -f2- || true)
    [[ -n "$_v" ]] && _DEF_COUNTRY="$_v" || true
    unset _v
fi

read -rp "WiFi netwerknaam (SSID) [${_DEF_SSID}]: " SSID
SSID=${SSID:-$_DEF_SSID}

while true; do
    read -rp "WiFi wachtwoord (min. 8 tekens) [${_DEF_PASS:-nieuw invoeren}]: " WIFI_PASS
    WIFI_PASS=${WIFI_PASS:-$_DEF_PASS}
    [[ ${#WIFI_PASS} -ge 8 ]] && break
    warn "Minimaal 8 tekens vereist."
done

read -rp "Landcode [${_DEF_COUNTRY}]: " COUNTRY
COUNTRY=${COUNTRY:-$_DEF_COUNTRY}

AP_IFACE="wlan1"
AP_IP="192.168.50.1"

# Uplink interface auto-detectie: eth0 heeft voorkeur boven wlan0
info "Uplink interface detecteren..."
UPLINK_IFACE="wlan0"
if ip link show eth0 &>/dev/null; then
    ETH_CARRIER=$(cat /sys/class/net/eth0/carrier 2>/dev/null || echo 0)
    if [[ "$ETH_CARRIER" == "1" ]]; then
        UPLINK_IFACE="eth0"
        ok "eth0: kabel aanwezig — eth0 gekozen als uplink"
    else
        info "eth0: geen kabel — wlan0 gekozen als uplink"
    fi
else
    info "eth0 niet aanwezig — wlan0 gekozen als uplink"
fi
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.200"

echo ""
info "SSID:     $SSID"
info "Land:     $COUNTRY"
info "AP-IP:    $AP_IP ($AP_IFACE)"
info "Uplink:   $UPLINK_IFACE"
echo ""
read -rp "Klopt dit? Doorgaan? [j/N]: " CONFIRM
[[ "${CONFIRM,,}" == "j" ]] || { info "Gestopt."; exit 0; }
echo ""

# Instellingen persisteren voor switch-uplink.sh
cat > /etc/toetslocker.conf << EOF
UPLINK_IFACE=${UPLINK_IFACE}
AP_IFACE=${AP_IFACE}
AP_IP=${AP_IP}
SSID=${SSID}
WIFI_PASS=${WIFI_PASS}
COUNTRY=${COUNTRY}
EOF
ok "Configuratie opgeslagen (/etc/toetslocker.conf)"

# =============================================================================
# STAP 1: Packages
# =============================================================================
info "Stap 1: Packages installeren..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git vim iw net-tools usbutils dnsutils tcpdump \
    hostapd dnsmasq nftables docker.io docker-compose
ok "Packages geïnstalleerd"

# =============================================================================
# STAP 2: hostapd
# =============================================================================
info "Stap 2: hostapd configureren..."
systemctl unmask hostapd

mkdir -p /etc/hostapd

# Profiel 1: generiek (RTL8812AU of vergelijkbaar)
cat > /etc/hostapd/hostapd.conf << EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
ht_capab=[HT40+][SHORT-GI-40][DSSS_CCK-40]
vht_capab=[MAX-MPDU-11454][SHORT-GI-80][RX-STBC-1][HTC-VHT][MAX-A-MPDU-LEN-EXP7]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${WIFI_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
country_code=${COUNTRY}
EOF

# Profiel 2: AWUS036AXML (MT7921U) — conservatievere VHT-caps, DFS-ondersteuning
cat > /etc/hostapd/hostapd-mt7921u.conf << EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
country_code=${COUNTRY}
ieee80211d=1
ieee80211h=1
ht_capab=[HT40+][SHORT-GI-40]
vht_capab=[SHORT-GI-80][RX-STBC-1]
vht_oper_chwidth=1
vht_oper_centr_freq_seg0_idx=42
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${WIFI_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

# Detecteer adapter via USB-ID en kies het bijpassende profiel
# MT7921U (AWUS036AXML) = 0e8d:7961
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
if lsusb | grep -qi "0e8d:7961"; then
    HOSTAPD_CONF="/etc/hostapd/hostapd-mt7921u.conf"
    info "MT7921U (AWUS036AXML) gedetecteerd — hostapd-mt7921u.conf actief"
else
    info "Geen MT7921U gevonden — hostapd.conf actief (generiek profiel)"
fi

sed -i "s|^#\?DAEMON_CONF=.*|DAEMON_CONF=\"${HOSTAPD_CONF}\"|" \
    /etc/default/hostapd
rfkill unblock all
systemctl enable hostapd
ok "hostapd geconfigureerd (profiel: $(basename "${HOSTAPD_CONF}"))"

# =============================================================================
# STAP 3: NetworkManager — wlan1 unmanaged
# =============================================================================
info "Stap 3: NetworkManager..."
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-unmanaged.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan1
EOF
systemctl reload NetworkManager 2>/dev/null || true
ok "wlan1 onbeheerd door NetworkManager"

# =============================================================================
# STAP 4: wlan1-setup service (statisch IP)
# =============================================================================
info "Stap 4: wlan1-setup service..."
cat > /etc/systemd/system/wlan1-setup.service << EOF
[Unit]
Description=Static IP for wlan1 (AP interface)
After=hostapd.service
BindsTo=hostapd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip addr flush dev ${AP_IFACE}
ExecStart=/sbin/ip addr add ${AP_IP}/24 dev ${AP_IFACE}
ExecStart=/sbin/ip link set ${AP_IFACE} up

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable wlan1-setup.service
ok "wlan1-setup service aangemaakt"

# =============================================================================
# STAP 5: dnsmasq
# =============================================================================
info "Stap 5: dnsmasq configureren..."

mkdir -p /etc/systemd/system/dnsmasq.service.d
cat > /etc/systemd/system/dnsmasq.service.d/override.conf << 'EOF'
[Unit]
After=wlan1-setup.service
Requires=wlan1-setup.service
EOF

cat > /etc/dnsmasq.d/ap.conf << EOF
interface=${AP_IFACE}
bind-interfaces
no-resolv

dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,24h
dhcp-option=option:router,${AP_IP}
dhcp-option=option:dns-server,${AP_IP}

address=/toetslocker.lan/${AP_IP}
domain=lan
dhcp-option=option:domain-search,lan

domain-needed
bogus-priv
EOF

systemctl daemon-reload
systemctl enable dnsmasq
ok "dnsmasq geconfigureerd"

# =============================================================================
# STAP 6: IP forwarding
# =============================================================================
info "Stap 6: IP forwarding..."
sysctl -w net.ipv4.ip_forward=1 > /dev/null
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ipforward.conf
ok "IP forwarding actief"

# DNS permanent op 8.8.8.8 zetten via globale NM-override.
# Werkt voor alle verbindingen (ook toekomstige), ongeacht of ze actief zijn bij installatie.
info "Stap 6b: DNS fixeren op 8.8.8.8 (globale NM override)..."
cat > /etc/NetworkManager/conf.d/99-dns.conf << 'EOF'
[global-dns-domain-*]
servers=8.8.8.8,8.8.4.4
EOF
nmcli general reload 2>/dev/null || true
ok "DNS 8.8.8.8 ingesteld voor alle NetworkManager-verbindingen"

# =============================================================================
# STAP 7: nftables firewall
# =============================================================================
info "Stap 7: nftables firewall..."

# De actieve uplink wordt opgeslagen in een apart include-bestand.
# switch-uplink.sh hoeft dan alleen dit bestand te overschrijven en
# nftables te herladen — de rest van nftables.conf blijft ongewijzigd.
mkdir -p /etc/nftables.d
echo "define UPLINK = ${UPLINK_IFACE}" > /etc/nftables.d/uplink.conf

cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f
include "/etc/nftables.d/uplink.conf"

# Verwijder alleen onze eigen tabellen; Docker's nat/filter tabellen blijven intact
table ip custom_nat {}
delete table ip custom_nat

table inet filter {}
delete table inet filter

# Eigen NAT-tabel (prioriteit -150, vóór Docker's -100)
table ip custom_nat {
    # IPs van whitelisted domeinen — gevuld door dnsmasq, zelfde als allowed_ips.
    # Gebruikt in prerouting om whitelisted HTTP-verkeer NIET te onderscheppen.
    set captive_bypass {
        type ipv4_addr
        flags timeout
        timeout 1h
    }

    chain prerouting {
        type nat hook prerouting priority -150;
        iifname "${AP_IFACE}" udp dport 53 redirect to :53
        iifname "${AP_IFACE}" tcp dport 53 redirect to :53
        # Captive portal: onderschep HTTP naar niet-whitelisted IPs → Pi
        # Whitelisted IPs (in captive_bypass) gaan gewoon door
        iifname "${AP_IFACE}" tcp dport 80 ip daddr != @captive_bypass redirect to :80
    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname \$UPLINK masquerade;
    }
}

table inet filter {
    # IPs van whitelisted domeinen — gevuld door dnsmasq
    set allowed_ips {
        type ipv4_addr
        flags timeout
        timeout 1h
    }

    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        iif "lo" accept
        iifname "eth0"  accept
        iifname "wlan0" accept
        iifname "${AP_IFACE}" udp dport 67 accept
        iifname "${AP_IFACE}" udp dport 53 accept
        iifname "${AP_IFACE}" tcp dport 53 accept
        iifname "${AP_IFACE}" tcp dport 22 accept
        iifname "${AP_IFACE}" tcp dport 80 accept
        ip protocol icmp accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        # Studenten naar internet: alleen whitelist IPs via actieve uplink
        iifname "${AP_IFACE}" oifname \$UPLINK ip daddr @allowed_ips tcp dport { 80, 443 } accept
        iifname "${AP_IFACE}" oifname \$UPLINK ip daddr @allowed_ips udp dport 443 accept
        # Docker container: altijd bereikbaar via AP én beide beheerinterfaces
        iifname "${AP_IFACE}" oifname "docker0" tcp dport { 80, 8080 } accept
        iifname "eth0"        oifname "docker0" tcp dport { 80, 8080 } accept
        iifname "wlan0"       oifname "docker0" tcp dport { 80, 8080 } accept
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

systemctl enable nftables
ok "nftables geconfigureerd"

# =============================================================================
# STAP 8: Whitelist
# =============================================================================
info "Stap 8: Whitelist instellen..."

_WL_URL="https://raw.githubusercontent.com/martijnwieggers/toetslockerpi/main/whitelist.txt"
curl -fsSL "$_WL_URL" -o /etc/whitelist.txt \
    || fail "Kon whitelist.txt niet downloaden van GitHub: $_WL_URL"
unset _WL_URL
ok "Whitelist gedownload van GitHub"

ok "Whitelist gedownload van GitHub (script volgt in stap 9b)"

# =============================================================================
# STAP 9: Docker
# =============================================================================
info "Stap 9: Docker configureren..."

mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/after-nftables.conf << 'EOF'
[Unit]
After=nftables.service
EOF

# Cgroup memory (Raspberry Pi vereiste voor Docker memory limits)
CMDLINE=/boot/firmware/cmdline.txt
if [[ -f "$CMDLINE" ]] && ! grep -q "cgroup_memory=1" "$CMDLINE"; then
    sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE"
    warn "Cgroup memory ingeschakeld — herstart vereist voor volledig effect"
fi

systemctl daemon-reload
systemctl enable docker
ok "Docker geconfigureerd"

# docker-compose voor de gctoetslocking-app (ingebakken in install.sh)
# De app draait met network_mode: host op poort 80 — geen nginx nodig.
# nftables stuurt captive-portal-verkeer al naar poort 80 van de Pi.
mkdir -p /etc/toetslocker

cat > /etc/toetslocker/docker-compose.yml << 'COMPOSE'
services:
  toetslocking:
    image: ghcr.io/roelofvanleeuwen/gctoetslocking:latest
    container_name: toetslocker
    restart: unless-stopped

    # Host networking geeft de container directe toegang tot alle
    # host-interfaces (wlan1, wlan0, etc.) — vereist voor iw en ip-commando's.
    # Poortmapping is niet nodig: de app is bereikbaar op poort 80 van de Pi.
    network_mode: host

    privileged: true

    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:80
      - ConnectionStrings__Default=Data Source=/data/app.db
      - Monitoring__Interface=wlan1
      - Monitoring__PollSeconds=2
      - Wifi__Interface=wlan0
      - Teacher__Password=1234
      - ForceHttps=false
      - TZ=Europe/Amsterdam
      - DOTNET_RUNNING_IN_CONTAINER=true

    volumes:
      - toetslocking-pi-data:/data
      - /var/run/dbus:/var/run/dbus:ro
      - /etc/NetworkManager:/etc/NetworkManager:ro

volumes:
  toetslocking-pi-data:
COMPOSE
ok "docker-compose.yml aangemaakt (/etc/toetslocker/docker-compose.yml)"

# /etc/hosts
sed -i '/toetslocker/d' /etc/hosts
echo "${AP_IP} toetslocker.lan toetslocker" >> /etc/hosts

# =============================================================================
# STAP 9a: GitHub Container Registry inloggen (ghcr.io)
# =============================================================================
info "Stap 9a: Inloggen bij ghcr.io..."

DOCKER_CONF="/root/.docker/config.json"
DO_LOGIN=true

if [[ -f "$DOCKER_CONF" ]] && grep -q '"ghcr.io"' "$DOCKER_CONF" 2>/dev/null; then
    STORED_USER=$(python3 -c "
import json, base64, sys
try:
    with open('$DOCKER_CONF') as f:
        c = json.load(f)
    auth = c.get('auths', {}).get('ghcr.io', {}).get('auth', '')
    if auth:
        print(base64.b64decode(auth).decode().split(':')[0])
except Exception:
    pass
" 2>/dev/null || true)

    if [[ -n "$STORED_USER" ]]; then
        info "Bestaande ghcr.io login gevonden: ${STORED_USER}"
    else
        info "Bestaande ghcr.io login gevonden (gebruikersnaam niet leesbaar)"
    fi

    read -rp "Nieuwe credentials invoeren? [j/N]: " NEW_CREDS
    [[ "${NEW_CREDS,,}" == "j" ]] || { DO_LOGIN=false; ok "Bestaande ghcr.io credentials worden gebruikt"; }
fi

if [[ "$DO_LOGIN" == true ]]; then
    echo "  Maak een PAT aan op https://github.com/settings/tokens → New token → scope: read:packages"
    read -rp  "  GitHub gebruikersnaam (eigenaar van het PAT token): " GHCR_USER
    read -rsp "  GitHub PAT token (read:packages): " GHCR_TOKEN < /dev/tty; echo ""
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin \
        || fail "Docker login mislukt — controleer gebruikersnaam en token en probeer opnieuw"
    unset GHCR_TOKEN
    ok "Ingelogd bij ghcr.io als ${GHCR_USER}"
fi

# =============================================================================
# STAP 9b: hulpscripts downloaden en installeren
# =============================================================================
info "Stap 9b: hulpscripts downloaden van GitHub..."
_BASE_URL="https://raw.githubusercontent.com/martijnwieggers/toetslockerpi/main"
for _SCRIPT in switch-uplink.sh logging_on.sh logging_off.sh update-whitelist.sh; do
    if curl -fsSL "${_BASE_URL}/${_SCRIPT}" -o "/usr/local/bin/${_SCRIPT}"; then
        chmod +x "/usr/local/bin/${_SCRIPT}"
        ok "${_SCRIPT} geïnstalleerd (/usr/local/bin/${_SCRIPT})"
    else
        warn "${_SCRIPT} kon niet worden gedownload — stap overgeslagen"
    fi
done
unset _BASE_URL _SCRIPT

# =============================================================================
# STAP 9c: uplink-monitor (realtime eth0/wlan0 bewaking + whitelist-behoud)
# =============================================================================
info "Stap 9c: uplink-monitor installeren..."

# Verwijder eventuele oude auto-uplink installatie
systemctl disable --now auto-uplink.service 2>/dev/null || true
rm -f /etc/systemd/system/auto-uplink.service \
      /usr/local/bin/auto-uplink.sh

cat > /usr/local/bin/uplink-monitor.sh << 'SCRIPT'
#!/bin/bash
# Bewaakt eth0 carrier en wisselt masquerade-uplink in realtime.
# eth0 met carrier → eth0; anders → wlan0.
# switch-uplink.sh herlaadt nftables + whitelist zodat de allowed_ips set
# altijd actief blijft op de juiste interface.

CONF=/etc/toetslocker.conf
SWITCH=/usr/local/bin/switch-uplink.sh

_log() { logger -t uplink-monitor "$1"; echo "[uplink-monitor] $1"; }

check_and_switch() {
    [[ -f "$CONF" ]] || return
    # Herlaad conf zodat UPLINK_IFACE altijd de huidige waarde heeft
    # shellcheck source=/dev/null
    source "$CONF"
    local eth_carrier
    eth_carrier=$(cat /sys/class/net/eth0/carrier 2>/dev/null || echo 0)

    if [[ "$eth_carrier" == "1" ]] && [[ "$UPLINK_IFACE" != "eth0" ]]; then
        # Wacht tot eth0 een IP heeft (DHCP gereed), max 30 seconden
        local retries=0 eth_ip=""
        while [[ $retries -lt 15 ]]; do
            eth_ip=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2; exit}')
            [[ -n "$eth_ip" ]] && break
            sleep 2; retries=$((retries + 1))
        done
        if [[ -z "$eth_ip" ]]; then
            _log "eth0 carrier aanwezig maar geen IP na 30s — wisselen geannuleerd"
            return
        fi
        _log "eth0 carrier aanwezig en IP=${eth_ip} — wisselen naar eth0"
        "$SWITCH" eth0 || _log "Fout bij wisselen naar eth0"
    elif [[ "$eth_carrier" != "1" ]] && [[ "$UPLINK_IFACE" != "wlan0" ]]; then
        _log "eth0 carrier weg — wisselen naar wlan0"
        "$SWITCH" wlan0 || _log "Fout bij wisselen naar wlan0"
    fi
}

# Initiële controle bij opstart
check_and_switch

# Realtime bewaking via kernel netlink events
ip monitor link 2>/dev/null | while IFS= read -r line; do
    if [[ "$line" == *"eth0"* ]]; then
        sleep 2  # Wacht tot kernel carrier-bestand is bijgewerkt
        check_and_switch
    fi
done
SCRIPT
chmod +x /usr/local/bin/uplink-monitor.sh

cat > /etc/systemd/system/uplink-monitor.service << 'EOF'
[Unit]
Description=Realtime uplink monitor (eth0 boven wlan0)
After=nftables.service network.target
Before=hostapd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/uplink-monitor.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable uplink-monitor.service
ok "uplink-monitor service aangemaakt en ingeschakeld"

# =============================================================================
# STAP 9d: toetslocker systemd service (pull latest image bij iedere opstart)
# =============================================================================
info "Stap 9d: toetslocker.service aanmaken (auto-pull bij opstart)..."

cat > /etc/systemd/system/toetslocker.service << 'EOF'
[Unit]
Description=ToetsLocker app — pull latest image en start container
After=docker.service network-online.target nftables.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Pull nieuwe image (fout = OK, dan wordt gecachede image gebruikt)
ExecStartPre=-/usr/bin/docker compose -f /etc/toetslocker/docker-compose.yml pull
# Start container (of herstart als image gewijzigd is)
ExecStart=/usr/bin/docker compose -f /etc/toetslocker/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f /etc/toetslocker/docker-compose.yml down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable toetslocker.service
ok "toetslocker.service aangemaakt en ingeschakeld"

# =============================================================================
# STAP 10: Services starten
# =============================================================================
info "Stap 10: Services starten..."

systemctl restart nftables
systemctl restart hostapd
sleep 2
systemctl restart wlan1-setup 2>/dev/null || true
sleep 1
systemctl restart dnsmasq
systemctl restart docker
sleep 3
systemctl restart uplink-monitor

# Whitelist laden
/usr/local/bin/update-whitelist.sh

# Verwijder eventuele oude nginx container
docker rm -f toetslocker-nginx 2>/dev/null || true

# gctoetslocking app via systemd service (pull + start)
# restart i.p.v. start: werkt ook als service al actief is bij herinstallatie
systemctl restart toetslocker.service \
    && ok "gctoetslocking container gestart via toetslocker.service" \
    || warn "toetslocker.service kon niet starten — controleer: journalctl -u toetslocker"
sleep 20

# =============================================================================
# EINDCONTROLE
# =============================================================================
echo ""
echo "============================================"
echo " Eindcontrole"
echo "============================================"

ERRORS=0
for svc in hostapd dnsmasq nftables docker wlan1-setup uplink-monitor toetslocker; do
    if [[ "$(systemctl is-active "$svc")" == "active" ]]; then
        ok "$svc actief"
    else
        warn "$svc NIET actief"
        ERRORS=$((ERRORS+1))
    fi
done

DNS_OK=$(nslookup toetslocker.lan "${AP_IP}" 2>/dev/null | grep -c "${AP_IP}" || true)
[[ "$DNS_OK" -gt 0 ]] \
    && ok "DNS: toetslocker.lan → ${AP_IP}" \
    || { warn "DNS: toetslocker.lan resolveert niet"; ERRORS=$((ERRORS+1)); }

APP_OK=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "http://localhost:80" || true)
[[ "$APP_OK" =~ ^(200|301|302)$ ]] \
    && ok "HTTP: gctoetslocking app bereikbaar op poort 80 (status ${APP_OK})" \
    || { warn "HTTP: gctoetslocking app niet bereikbaar op poort 80 — mogelijk nog aan het starten"; ERRORS=$((ERRORS+1)); }

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN} Setup voltooid!${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${YELLOW} Setup voltooid met ${ERRORS} waarschuwing(en).${NC}"
fi

echo ""
echo "  WiFi netwerk    : ${SSID}"
echo "  WiFi wachtwoord : ${WIFI_PASS}"
echo "  IP-adres        : ${AP_IP}"
echo "  Adapter profiel : $(basename "${HOSTAPD_CONF}")"
echo "  Container       : http://toetslocker.lan"
echo ""
echo "  Whitelist bewerken : sudo nano /etc/whitelist.txt"
echo "  Whitelist herladen : sudo /usr/local/bin/update-whitelist.sh"
echo "  Wissel uplink      : sudo switch-uplink.sh eth0   (of wlan0)"
echo ""
echo "  Herstart de Pi voor cgroup-geheugenlimieten (Docker)."
echo ""
