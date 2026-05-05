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
    read -rsp "WiFi wachtwoord (min. 8 tekens): " WIFI_PASS; echo ""
    [[ ${#WIFI_PASS} -ge 8 ]] && break
    warn "Minimaal 8 tekens vereist."
done

read -rp "Landcode [NL]: " COUNTRY
COUNTRY=${COUNTRY:-NL}

AP_IFACE="wlan1"
UPLINK_IFACE="wlan0"
AP_IP="192.168.50.1"
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

# =============================================================================
# STAP 1: Packages
# =============================================================================
info "Stap 1: Packages installeren..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git vim iw net-tools usbutils dnsutils tcpdump \
    hostapd dnsmasq nftables docker.io
ok "Packages geïnstalleerd"

# =============================================================================
# STAP 2: hostapd
# =============================================================================
info "Stap 2: hostapd configureren..."
systemctl unmask hostapd

mkdir -p /etc/hostapd
cat > /etc/hostapd/hostapd.conf << EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${WIFI_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
country_code=${COUNTRY}
EOF

sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' \
    /etc/default/hostapd
rfkill unblock all
systemctl enable hostapd
ok "hostapd geconfigureerd"

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
log-queries
log-facility=/var/log/dnsmasq.log
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
cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f
flush ruleset

# Eigen NAT-tabel (prioriteit -150, vóór Docker's -100)
table ip custom_nat {
    chain prerouting {
        type nat hook prerouting priority -150;
        iifname "${AP_IFACE}" udp dport 53 redirect to :53
        iifname "${AP_IFACE}" tcp dport 53 redirect to :53
    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "${UPLINK_IFACE}" masquerade;
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
        iifname "${UPLINK_IFACE}" accept
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
        # Studenten naar internet: alleen whitelist IPs via HTTP(S)
        iifname "${AP_IFACE}" oifname "${UPLINK_IFACE}" ip daddr @allowed_ips tcp dport { 80, 443 } accept
        iifname "${AP_IFACE}" oifname "${UPLINK_IFACE}" ip daddr @allowed_ips udp dport 443 accept
        # Studenten naar Docker container
        iifname "${AP_IFACE}" oifname "docker0" tcp dport { 80, 8080 } accept
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
        echo "nftset=/${domain}/4#inet#filter#allowed_ips"
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

# /etc/hosts
sed -i '/toetslocker/d' /etc/hosts
echo "${AP_IP} toetslocker.lan toetslocker" >> /etc/hosts

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

# Whitelist laden
/usr/local/bin/update-whitelist.sh

# Docker container
if docker ps -a --format '{{.Names}}' | grep -q "^toetslocker$"; then
    docker start toetslocker 2>/dev/null || true
    ok "Container 'toetslocker' herstart"
else
    docker run -d \
        --name toetslocker \
        --restart unless-stopped \
        -p 80:80 \
        nginx:alpine
    ok "Container 'toetslocker' gestart (nginx placeholder)"
fi

# =============================================================================
# EINDCONTROLE
# =============================================================================
echo ""
echo "============================================"
echo " Eindcontrole"
echo "============================================"

ERRORS=0
for svc in hostapd dnsmasq nftables docker wlan1-setup; do
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

HTTP_OK=$(curl -s --max-time 3 "http://${AP_IP}" | grep -c "nginx" || true)
[[ "$HTTP_OK" -gt 0 ]] \
    && ok "HTTP: container bereikbaar op poort 80" \
    || { warn "HTTP: container niet bereikbaar"; ERRORS=$((ERRORS+1)); }

echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN} Setup voltooid!${NC}"
    echo -e "${GREEN}============================================${NC}"
else
    echo -e "${YELLOW} Setup voltooid met ${ERRORS} waarschuwing(en).${NC}"
fi

echo ""
echo "  WiFi netwerk : ${SSID}"
echo "  IP-adres     : ${AP_IP}"
echo "  Container    : http://toetslocker.lan"
echo ""
echo "  Whitelist bewerken : sudo nano /etc/whitelist.txt"
echo "  Whitelist herladen : sudo /usr/local/bin/update-whitelist.sh"
echo ""
echo "  Herstart de Pi voor cgroup-geheugenlimieten (Docker)."
echo ""
