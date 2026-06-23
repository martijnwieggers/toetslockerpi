#!/bin/bash
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

read -rp  "WiFi netwerknaam (SSID) [ToetsLocker]: " SSID
SSID=${SSID:-ToetsLocker}

while true; do
    read -rp  "WiFi wachtwoord (min. 8 tekens): " WIFI_PASS
    [[ ${#WIFI_PASS} -ge 8 ]] && break
    warn "Minimaal 8 tekens vereist."
done

read -rp "Landcode [NL]: " COUNTRY
COUNTRY=${COUNTRY:-NL}

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

cat > /etc/whitelist.txt << 'EOF'
# Whitelist voor ToetsLocker AP
# Één domein per regel — subdomains worden automatisch meegenomen
# Commentaar begint met #

# Apple captive portal (vereist voor iOS-verbinding)
apple.com
captive.apple.com

# Windows captive portal
www.msftconnecttest.com

# itsLearning
graafschapcollege.itslearning.com
cdn.itslearning.com
filerepository.itslearning.com
proxy.itslearning.com
filecache.itslearning.com
eu1-filerepo-1436663729.eu-central-1.elb.amazonaws.com
eu1.itslearning.com
platform.itslearning.com

# Microsoft authenticatie (SSO via itsLearning)
login.microsoftonline.com
login.mso.msidentity.com
aadcdn.msauth.net
aadcdn.msauthimages.net
autologon.microsoftazuread-sso.com
EOF

cat > /usr/local/bin/update-whitelist.sh << 'EOF'
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
EOF
chmod +x /usr/local/bin/update-whitelist.sh
ok "Whitelist script aangemaakt (/etc/whitelist.txt)"

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

# Nginx captive portal configuratie
mkdir -p /etc/toetslocker

cat > /etc/toetslocker/nginx.conf << 'NGINX'
# Vang alle verzoeken op die niet voor toetslocker.lan zijn → redirect
server {
    listen 80 default_server;
    server_name _;
    return 302 http://toetslocker.lan/;
}

# Serveer de landingspagina voor toetslocker.lan
server {
    listen 80;
    server_name toetslocker.lan;
    root /usr/share/nginx/html;
    index index.html;
}
NGINX

cat > /etc/toetslocker/index.html << 'HTML'
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ToetsLocker</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif;
               background: #f0f2f5; display: flex; align-items: center;
               justify-content: center; min-height: 100vh; }
        .card { background: white; border-radius: 12px; padding: 48px 40px;
                max-width: 420px; width: 90%; text-align: center;
                box-shadow: 0 4px 20px rgba(0,0,0,.08); }
        h1 { font-size: 2rem; color: #1a73e8; margin-bottom: 16px; }
        p  { color: #555; line-height: 1.7; }
    </style>
</head>
<body>
    <div class="card">
        <h1>ToetsLocker</h1>
        <p>Je bent verbonden met het toetsnetwerk.<br>
           Gebruik de door je docent opgegeven applicatie.</p>
    </div>
</body>
</html>
HTML
ok "Nginx captive portal configuratie aangemaakt (/etc/toetslocker/)"

# /etc/hosts
sed -i '/toetslocker/d' /etc/hosts
echo "${AP_IP} toetslocker.lan toetslocker" >> /etc/hosts

# =============================================================================
# STAP 9b: switch-uplink.sh installeren
# =============================================================================
info "Stap 9b: switch-uplink.sh installeren..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/switch-uplink.sh" ]]; then
    cp "${SCRIPT_DIR}/switch-uplink.sh" /usr/local/bin/switch-uplink.sh
    chmod +x /usr/local/bin/switch-uplink.sh
    ok "switch-uplink.sh geïnstalleerd (/usr/local/bin/switch-uplink.sh)"
else
    warn "switch-uplink.sh niet gevonden naast install.sh — stap overgeslagen"
fi

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
        _log "eth0 carrier aanwezig — wisselen naar eth0"
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

# Docker container — altijd opnieuw aanmaken zodat volume-mounts kloppen
docker rm -f toetslocker 2>/dev/null || true
docker run -d \
    --name toetslocker \
    --restart unless-stopped \
    -p 80:80 \
    -v /etc/toetslocker/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
    -v /etc/toetslocker/index.html:/usr/share/nginx/html/index.html:ro \
    nginx:alpine
ok "Container 'toetslocker' gestart (captive portal)"
sleep 20

# =============================================================================
# EINDCONTROLE
# =============================================================================
echo ""
echo "============================================"
echo " Eindcontrole"
echo "============================================"

ERRORS=0
for svc in hostapd dnsmasq nftables docker wlan1-setup uplink-monitor; do
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

HTTP_OK=$(curl -sL --max-time 5 "http://toetslocker.lan" | grep -ci "toetslocker" || true)
[[ "$HTTP_OK" -gt 0 ]] \
    && ok "HTTP: captive portal bereikbaar (http://toetslocker.lan)" \
    || { warn "HTTP: captive portal niet bereikbaar"; ERRORS=$((ERRORS+1)); }

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
