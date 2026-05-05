# Raspberry Pi 5 — Setup Commandos
# Bijgewerkt: 2026-05-04

---

## Stap 1 — Systeem bijwerken en basistools installeren

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
sudo apt install -y curl wget git vim iw net-tools usbutils dnsutils

---

## Stap 2 — USB WiFi adapter detecteren

ip link show | grep -E "^[0-9]+: w"
lsusb
iw list 2>/dev/null | grep -A 10 "Supported interface modes"
iw dev wlan1 info

---

## Stap 3 — Packages installeren

sudo apt install -y hostapd dnsmasq nftables
sudo systemctl unmask hostapd
sudo systemctl stop hostapd dnsmasq 2>/dev/null
hostapd -v 2>&1 | head -1
dnsmasq --version | head -1
nft --version

---

## Stap 4 — wlan1 statisch IP + NetworkManager unmanaged

sudo tee /etc/NetworkManager/conf.d/99-unmanaged.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan1
EOF

sudo systemctl reload NetworkManager

sudo tee /etc/systemd/system/wlan1-setup.service << 'EOF'
[Unit]
Description=Static IP for wlan1 (AP interface)
After=hostapd.service
BindsTo=hostapd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/ip addr flush dev wlan1
ExecStart=/sbin/ip addr add 192.168.50.1/24 dev wlan1
ExecStart=/sbin/ip link set wlan1 up

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wlan1-setup.service

---

## Stap 5 — hostapd configureren

sudo mkdir -p /etc/hostapd

sudo tee /etc/hostapd/hostapd.conf > /dev/null << 'EOF'
interface=wlan1
driver=nl80211
ssid=ToetsLocker
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=Welkom2024!
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
country_code=NL
EOF

sudo sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

sudo rfkill unblock all
sudo systemctl start hostapd

---

## Stap 6 — dnsmasq configureren (DHCP + DNS)

sudo mkdir -p /etc/systemd/system/dnsmasq.service.d

sudo tee /etc/systemd/system/dnsmasq.service.d/override.conf > /dev/null << 'EOF'
[Unit]
After=wlan1-setup.service
Requires=wlan1-setup.service
EOF

sudo tee /etc/dnsmasq.d/ap.conf > /dev/null << 'EOF'
interface=wlan1
bind-interfaces
no-resolv
server=8.8.8.8
server=1.1.1.1
dhcp-range=192.168.50.10,192.168.50.200,255.255.255.0,24h
dhcp-option=option:router,192.168.50.1
dhcp-option=option:dns-server,192.168.50.1
address=/toetslocker.local/192.168.50.1
domain-needed
bogus-priv
log-queries
log-facility=/var/log/dnsmasq.log
EOF

sudo systemctl daemon-reload
sudo systemctl start dnsmasq

---

## Stap 7 — IP forwarding + NAT

sudo sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-ipforward.conf

sudo tee /etc/nftables.conf > /dev/null << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table ip nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "wlan0" masquerade;
    }
}

table inet filter {
    chain input {
        type filter hook input priority filter; policy accept;
    }
    chain forward {
        type filter hook forward priority filter; policy accept;
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

sudo systemctl enable nftables
sudo systemctl restart nftables

---

## Stap 8 — nftables strikte firewall

sudo tee /etc/nftables.conf > /dev/null << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
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
        iifname "wlan0" accept
        iifname "wlan1" udp dport 67 accept
        iifname "wlan1" udp dport 53 accept
        iifname "wlan1" tcp dport 53 accept
        iifname "wlan1" tcp dport 80 accept
        ip protocol icmp accept
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        iifname "wlan1" oifname "wlan0" ip daddr @allowed_ips tcp dport { 80, 443 } accept
        iifname "wlan1" oifname "wlan0" ip daddr @allowed_ips udp dport 443 accept
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}

table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
        iifname "wlan1" udp dport 53 redirect to :53
        iifname "wlan1" tcp dport 53 redirect to :53
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "wlan0" masquerade;
    }
}
EOF

sudo systemctl restart nftables

# Fix: verplaats nat-regels naar aparte tabel zodat Docker's DNAT kan werken
sudo tee /etc/nftables.conf > /dev/null << 'EOF'
#!/usr/sbin/nft -f
flush ruleset

table ip custom_nat {
    chain prerouting {
        type nat hook prerouting priority -150;
        iifname "wlan1" udp dport 53 redirect to :53
        iifname "wlan1" tcp dport 53 redirect to :53
    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "wlan0" masquerade;
    }
}

table inet filter {
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
        iifname "wlan0" accept
        iifname "wlan1" udp dport 67 accept
        iifname "wlan1" udp dport 53 accept
        iifname "wlan1" tcp dport 53 accept
        iifname "wlan1" tcp dport 80 accept
        ip protocol icmp accept
    }
    chain forward {
        type filter hook forward priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        iifname "wlan1" oifname "wlan0" ip daddr @allowed_ips tcp dport { 80, 443 } accept
        iifname "wlan1" oifname "wlan0" ip daddr @allowed_ips udp dport 443 accept
        iifname "wlan1" oifname "docker0" tcp dport 80 accept
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF

sudo systemctl restart nftables
sudo systemctl restart docker
sudo docker start toetslocker 2>/dev/null; true

---

## Stap 9 — DNS Whitelist filtering

sudo sed -i '/^server=8\.8\.8\.8/d; /^server=1\.1\.1\.1/d' /etc/dnsmasq.d/ap.conf

sudo tee /etc/whitelist.txt > /dev/null << 'EOF'
# Whitelist voor ToetsLocker AP
example.com
EOF

sudo tee /usr/local/bin/update-whitelist.sh > /dev/null << 'EOF'
#!/bin/bash
set -e
WHITELIST=/etc/whitelist.txt
OUTPUT=/etc/dnsmasq.d/whitelist.conf
UPSTREAM=8.8.8.8
[ -f "$WHITELIST" ] || { echo "Whitelist niet gevonden: $WHITELIST"; exit 1; }
{
    echo "# Automatisch gegenereerd"
    while IFS= read -r domain || [ -n "$domain" ]; do
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue
        domain="${domain#\*.}"
        echo "server=/${domain}/${UPSTREAM}"
        echo "nftset=/${domain}/4#inet#filter#allowed_ips"
    done < "$WHITELIST"
} | sudo tee "$OUTPUT" > /dev/null
systemctl restart dnsmasq
COUNT=$(grep -c '^server=' "$OUTPUT" 2>/dev/null || echo 0)
echo "Whitelist bijgewerkt: ${COUNT} domein(en) geladen"
EOF

sudo chmod +x /usr/local/bin/update-whitelist.sh
sudo /usr/local/bin/update-whitelist.sh

---

## Stap 10 — Docker installeren

sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker mwieggers
sudo docker run --rm hello-world

---

## Stap 11 — Container draaien + toetslocker.local

sudo docker run -d \
  --name toetslocker \
  --restart unless-stopped \
  -p 80:80 \
  nginx:alpine

echo "192.168.50.1 toetslocker" | sudo tee -a /etc/hosts

# Fix: toetslocker.local -> toetslocker.lan (iOS mDNS + Windows compatibiliteit)
sudo sed -i 's|address=/toetslocker.local/|address=/toetslocker.lan/|g' /etc/dnsmasq.d/ap.conf
sudo sed -i 's|192.168.50.1 toetslocker.local|192.168.50.1 toetslocker.lan toetslocker|g' /etc/hosts
cat >> /etc/dnsmasq.d/ap.conf << 'EOF'
domain=lan
dhcp-option=option:domain-search,lan
EOF
sudo systemctl restart dnsmasq

# Fix: Docker containers bereikbaar maken via FORWARD chain
sudo nft add rule inet filter forward \
  iifname "wlan1" oifname "docker0" tcp dport 80 accept

sudo sed -i '/iifname "wlan1" oifname "wlan0" ip daddr @allowed_ips udp dport 443 accept/a \\t\tiifname "wlan1" oifname "docker0" tcp dport 80 accept' /etc/nftables.conf

---

## Stap 12 — Eindcontrole

# Services actief?
for svc in hostapd dnsmasq nftables docker wlan1-setup; do
  echo "$svc: $(systemctl is-active $svc)"
done

# Services enabled bij boot?
for svc in hostapd dnsmasq nftables docker wlan1-setup; do
  echo "$svc: $(systemctl is-enabled $svc)"
done

# DNS whitelist werkt?
dig @192.168.50.1 google.com +short    # verwacht: REFUSED of geen antwoord
dig @192.168.50.1 toetslocker.lan +short  # verwacht: 192.168.50.1

# Hoeveel IPs in allowed_ips set?
sudo nft list set inet filter allowed_ips | grep -c "elements" || \
sudo nft list set inet filter allowed_ips | tail -5

# Docker container bereikbaar?
curl -s --max-time 3 http://192.168.50.1 | grep -o "<title>[^<]*"

# Whitelist herladen (als je whitelist.txt hebt aangepast):
sudo /usr/local/bin/update-whitelist.sh

---

## Stap 13 — Whitelist uitbreiden (itsLearning + Microsoft SSO)

sudo tee /etc/whitelist.txt > /dev/null << 'EOF'
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

sudo /usr/local/bin/update-whitelist.sh

---

## Stap 14 — Docker container vervangen door ASP.NET sample app

docker stop toetslocker
docker rm toetslocker

docker run -d \
    --name toetslocker \
    --restart unless-stopped \
    -p 80:8080 \
    mcr.microsoft.com/dotnet/samples:aspnetapp

# Controleren:
docker ps
curl -s --max-time 5 http://192.168.50.1 | grep -o "<title>[^<]*"

---

## Stap 15 — /etc/hosts fix voor toetslocker.lan lokaal op Pi

# Probleem: dnsmasq luistert alleen op wlan1, Pi zelf gebruikt dnsmasq niet.
# toetslocker.lan moet expliciet in /etc/hosts staan.

sudo sed -i '/toetslocker/d' /etc/hosts
echo "192.168.50.1 toetslocker.lan toetslocker" | sudo tee -a /etc/hosts

# Controleren:
ping -c 1 toetslocker.lan
ping -c 1 toetslocker

---

## Logging bekijken

# Live DNS-queries meekijken:
sudo tail -f /var/log/dnsmasq.log

# Alleen queries (geen DHCP):
sudo tail -f /var/log/dnsmasq.log | grep query

# Huidige whitelisted IPs in nftables:
sudo nft list set inet filter allowed_ips
