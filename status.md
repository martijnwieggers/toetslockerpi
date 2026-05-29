# ToetsLocker — Projectstatus
Bijgewerkt: 2026-05-29

---

## Status: VOLLEDIG WERKEND ✅

Alle stappen zijn uitgevoerd en getest op de echte Pi. Het systeem werkt op iPhone én Windows.

Installatiescript succesvol uitgevoerd (2026-05-29). Één timing-waarschuwing ("container niet bereikbaar") opgelost door `sleep 20` toe te voegen na container start in `install.sh`.

---

## Hardware

| Component | Waarde |
|-----------|--------|
| Apparaat | Raspberry Pi 5 |
| OS | Raspberry Pi OS Lite (Debian Trixie) |
| Gebruiker | mwieggers |
| Internet uplink | wlan0 (ingebouwde WiFi) |
| AP interface | wlan1 (USB WiFi adapter) |

---

## Netwerkconfiguratie

| Parameter | Waarde |
|-----------|--------|
| SSID | ToetsLocker |
| WiFi wachtwoord | Welkom2024! |
| Landcode | NL |
| AP IP-adres | 192.168.50.1 |
| DHCP range | 192.168.50.10 – 192.168.50.200 |
| Domeinnaam | toetslocker.lan |
| Docker container | mcr.microsoft.com/dotnet/samples:aspnetapp op poort 80 |

---

## Lokale bestanden

| Bestand | Beschrijving |
|---------|-------------|
| `C:\Claude\pi-install\install.sh` | Volledig idempotent installatiescript (voor verse Pi) |
| `C:\Claude\pi-install\whitelist.txt` | Lokale kopie van de domeinwhitelist |
| `C:\Claude\pi-install\commandos.md` | Stap-voor-stap commandolog (stappen 1–12) |
| `C:\Claude\pi-install\status.md` | Dit bestand |

---

## Bestanden op de Pi

| Pad | Beschrijving |
|-----|-------------|
| `/etc/hostapd/hostapd.conf` | AP configuratie (SSID, WPA2) |
| `/etc/NetworkManager/conf.d/99-unmanaged.conf` | wlan1 buiten NetworkManager |
| `/etc/systemd/system/wlan1-setup.service` | Statisch IP 192.168.50.1 op wlan1 |
| `/etc/dnsmasq.d/ap.conf` | DHCP + DNS basisconfig |
| `/etc/dnsmasq.d/whitelist.conf` | Automatisch gegenereerd door update-whitelist.sh |
| `/etc/whitelist.txt` | Domeinwhitelist (handmatig bewerken) |
| `/usr/local/bin/update-whitelist.sh` | Whitelist herladen + dnsmasq herstarten |
| `/etc/nftables.conf` | Firewall (NAT + filter) |
| `/etc/sysctl.d/99-ipforward.conf` | IP forwarding permanent |
| `/etc/systemd/system/docker.service.d/after-nftables.conf` | Docker start na nftables |
| `/etc/systemd/system/dnsmasq.service.d/override.conf` | dnsmasq start na wlan1-setup |
| `/boot/firmware/cmdline.txt` | cgroup_memory=1 toegevoegd |
| `/etc/hosts` | 192.168.50.1 toetslocker.lan toetslocker |

---

## Werkende services

```
hostapd      active + enabled
dnsmasq      active + enabled
nftables     active + enabled
docker       active + enabled
wlan1-setup  active + enabled
```

---

## Kritieke technische details (niet verliezen)

### nftables: table ip custom_nat (priority -150)
Docker draait zijn eigen `table ip nat` op priority -100. Als onze NAT-tabel ook op -100 staat, blokkeert die Docker's DNAT voor de container. Oplossing: onze prerouting-chain draait op **priority -150** (eerder dan Docker), zodat DNS-redirect werkt én Docker's DNAT daarna nog kan vuren.

### DNS whitelist via dnsmasq --nftset
dnsmasq 2.91+ ondersteunt `nftset=/<domain>/4#inet#filter#allowed_ips`. Bij elke DNS-lookup van een whitelisted domein wordt het resolved IP automatisch in de nftables set `allowed_ips` gezet (timeout 1h). Niet-whiteliste domeinen krijgen REFUSED. Direct IP-verkeer wordt geblokkeerd door FORWARD policy drop.

### .lan in plaats van .local
iOS gebruikt mDNS (Bonjour) voor `.local` domeinen — dat gaat buiten de gewone DNS om. Daardoor werkte `toetslocker.local` niet via dnsmasq. Opgelost met `.lan` + `domain=lan` + `dhcp-option=option:domain-search,lan` in dnsmasq.

### SSH alleen bereikbaar via wlan0 (standaard)
Poort 22 stond initieel niet open voor wlan1. Dat betekent: geen SSH via het ToetsLocker-netwerk, alleen via het uplink-netwerk (wlan0). Opgelost door `iifname "wlan1" tcp dport 22 accept` toe te voegen aan de INPUT-chain in nftables.conf.

### toetslocker.lan werkt niet lokaal op de Pi zelf
dnsmasq luistert alleen op `wlan1` (`bind-interfaces`), dus de Pi zelf gebruikt dnsmasq niet. `toetslocker.lan` moet daarom in `/etc/hosts` staan. Het installatiescript verwijdert altijd de oude regel en schrijft `192.168.50.1 toetslocker.lan toetslocker` opnieuw.

### Docker FORWARD-regel
De nftables FORWARD chain heeft policy drop. Docker container op docker0 is alleen bereikbaar als er expliciet een regel staat:
```
iifname "wlan1" oifname "docker0" tcp dport { 80, 8080 } accept
```
Gebruik `{ 80, 8080 }` omdat Docker's DNAT het pakket herschrijft naar de **container-poort** vóórdat onze FORWARD-chain het ziet. nginx gebruikt container-poort 80, aspnetapp gebruikt 8080 — de FORWARD-regel moet op de container-poort matchen, niet op de host-poort.

---

## Whitelist beheren

```bash
# Domeinen toevoegen:
sudo nano /etc/whitelist.txt

# Whitelist herladen:
sudo /usr/local/bin/update-whitelist.sh

# Huidige allowed IPs bekijken:
sudo nft list set inet filter allowed_ips
```

Huidig in whitelist.txt:
- `apple.com` + `captive.apple.com` — iOS captive portal
- `www.msftconnecttest.com` — Windows captive portal
- `graafschapcollege.itslearning.com`, `cdn.itslearning.com`, `filerepository.itslearning.com`, `proxy.itslearning.com`, `filecache.itslearning.com`, `eu1.itslearning.com`, `platform.itslearning.com`, `eu1-filerepo-1436663729.eu-central-1.elb.amazonaws.com` — itsLearning
- `login.microsoftonline.com`, `login.mso.msidentity.com`, `aadcdn.msauth.net`, `aadcdn.msauthimages.net`, `autologon.microsoftazuread-sso.com` — Microsoft authenticatie (SSO)

---

## Volgende stappen (optioneel)

- [x] Eigen Docker-applicatie deployen ter vervanging van nginx:alpine (aspnetapp)
- [x] Schooldomeinen toevoegen aan `/etc/whitelist.txt` (itsLearning + Microsoft SSO)
- [x] Reboot-test uitvoeren om te bevestigen dat alles automatisch start
- [ ] WPA3 toevoegen aan hostapd.conf (indien USB adapter dat ondersteunt)
- [ ] HTTPS captive portal pagina bouwen (nu plain nginx placeholder)
- [x] Logging inrichten: `log-queries` + `log-facility=/var/log/dnsmasq.log` actief in ap.conf

---

## Installatiescript gebruiken op verse Pi

```bash
# Script kopiëren naar Pi (vanuit Windows):
scp C:\Claude\pi-install\install.sh mwieggers@<pi-ip>:~/

# Op de Pi uitvoeren:
chmod +x install.sh
sudo ./install.sh
```

Het script vraagt interactief om SSID, wachtwoord en landcode.
