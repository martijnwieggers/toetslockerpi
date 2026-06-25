# ToetsLocker — Projectstatus
Bijgewerkt: 2026-06-26

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
| Gebruiker | <gebruiker> |
| Internet uplink | eth0 (voorkeur) of wlan0 (fallback) — automatisch gekozen |
| AP interface | wlan1 (USB WiFi adapter — RTL8812AU of MT7921U) |

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
| Docker container | ghcr.io/roelofvanleeuwen/gctoetslocking:latest op poort 80 |

---

## Uplink beheer

De Pi werkt met twee mogelijke uplinks. De keuze wordt bij iedere opstart én bij het in-/uitpluggen van een kabel automatisch gemaakt.

| Situatie | Actieve uplink |
|----------|---------------|
| Netwerkkabel in eth0 (carrier aanwezig) | eth0 |
| Geen kabel of geen carrier op eth0 | wlan0 |

### Hoe het werkt

**`uplink-monitor.service`** draait continu als systemd-service. Bij opstart doet hij een initiële controle; daarna luistert hij via `ip monitor link` naar kernel-events. Zodra eth0 van carrier wisselt, reageert de service binnen ~2 seconden.

Bij elke wisseling roept de monitor **`switch-uplink.sh`** aan. Dit script:
1. Schrijft de nieuwe uplink naar `/etc/nftables.d/uplink.conf` (`define UPLINK = eth0` of `wlan0`)
2. Herlaadt nftables — alleen onze eigen tabellen worden ververst, Docker's tabellen blijven intact
3. Herlaadt de whitelist (`update-whitelist.sh`) zodat de `allowed_ips` set direct actief is op de nieuwe interface

**Handmatig wisselen** (bijv. voor testen):
```bash
sudo switch-uplink.sh eth0    # forceer ethernet
sudo switch-uplink.sh wlan0   # forceer WiFi
sudo switch-uplink.sh         # toon huidige instelling
```

**Status bekijken:**
```bash
systemctl status uplink-monitor
journalctl -t uplink-monitor -n 20
cat /etc/nftables.d/uplink.conf    # toont actieve uplink
cat /etc/toetslocker.conf          # toont volledige config
```

---

## Windows ICS instellen

Gebruik dit script als de Pi via een USB-ethernetadapter of directe kabelverbinding aan een Windows-pc hangt en die pc als internetgateway moet dienen.

**Bestand:** `windows_ics.ps1`

**Vereiste:** PowerShell uitvoeren **als Administrator**. Klik met rechtermuisknop op PowerShell → *Als administrator uitvoeren*, of zoek in het startmenu naar PowerShell, rechtsklik en kies *Als administrator uitvoeren*.

**Uitvoeren:**
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\windows_ics.ps1
```

**Wat het script doet:**

1. Toont alle actieve netwerkadapters als genummerde lijst
2. Detecteert automatisch welke adapter internet heeft (via de default route) en welke naar de Pi gaat
3. Toont de suggestie — druk **Enter** als het klopt, of typ een ander nummer
4. Vraagt bevestiging vóór er iets wordt gewijzigd
5. Schakelt eventuele bestaande ICS-configuratie uit
6. Stelt ICS in: internetadapter als *public*, Pi-adapter als *private*
7. Zet een statisch IP op de Pi-adapter: `192.168.137.1`

**Resultaat na uitvoeren:**

| Parameter | Waarde |
|-----------|--------|
| Windows IP (naar Pi) | 192.168.137.1 |
| Pi IP (via DHCP) | automatisch, ergens in 192.168.137.x |
| Pi IP (handmatig) | bijv. 192.168.137.2 |
| Gateway op Pi | 192.168.137.1 |
| DNS op Pi | 192.168.137.1 of 8.8.8.8 |

> **Let op:** Windows ICS wijzigt het IP van de gedeelde adapter naar 192.168.137.1. Als je de Pi daarna via SSH wilt bereiken, gebruik dan dit nieuwe IP of stel een statisch IP in op de Pi.

---

## Lokale bestanden

| Bestand | Beschrijving |
|---------|-------------|
| `C:\Claude\pi-install\install.sh` | Volledig idempotent installatiescript (voor verse Pi) |
| `C:\Claude\pi-install\switch-uplink.sh` | Wisselt actieve uplink (eth0/wlan0) en herlaadt nftables + whitelist |
| `C:\Claude\pi-install\kopieren-naar-pi.cmd` | Kopieert install.sh, switch-uplink.sh, logging_on.sh en logging_off.sh naar Pi via scp; zet daarna +x |
| `C:\Claude\pi-install\windows_ics.ps1` | PowerShell script voor Windows ICS instellen (uitvoeren als Administrator) |
| `C:\Claude\pi-install\whitelist.txt` | Lokale kopie van de domeinwhitelist |
| `C:\Claude\pi-install\commandos.md` | Stap-voor-stap commandolog (stappen 1–12) |
| `C:\Claude\pi-install\status.md` | Dit bestand |

---

## Bestanden op de Pi

| Pad | Beschrijving |
|-----|-------------|
| `/etc/hostapd/hostapd.conf` | AP configuratie (SSID, WPA2) |
| `/etc/NetworkManager/conf.d/99-unmanaged.conf` | wlan1 buiten NetworkManager |
| `/etc/NetworkManager/conf.d/99-dns.conf` | Globale DNS-override: alle NM-verbindingen gebruiken 8.8.8.8 / 8.8.4.4 |
| `/etc/systemd/system/wlan1-setup.service` | Statisch IP 192.168.50.1 op wlan1 |
| `/etc/dnsmasq.d/ap.conf` | DHCP + DNS basisconfig |
| `/etc/dnsmasq.d/whitelist.conf` | Automatisch gegenereerd door update-whitelist.sh |
| `/etc/whitelist.txt` | Domeinwhitelist (handmatig bewerken) |
| `/usr/local/bin/update-whitelist.sh` | Whitelist herladen + dnsmasq herstarten |
| `/etc/nftables.conf` | Firewall (NAT + filter) — gebruikt include voor uplink |
| `/etc/nftables.d/uplink.conf` | Actieve uplink definitie (`define UPLINK = eth0` of `wlan0`) |
| `/etc/sysctl.d/99-ipforward.conf` | IP forwarding permanent |
| `/etc/systemd/system/docker.service.d/after-nftables.conf` | Docker start na nftables |
| `/etc/systemd/system/dnsmasq.service.d/override.conf` | dnsmasq start na wlan1-setup |
| `/etc/systemd/system/uplink-monitor.service` | Realtime uplink-bewaking (eth0/wlan0) |
| `/etc/systemd/system/toetslocker.service` | Pull latest image + start container bij iedere opstart |
| `/usr/local/bin/uplink-monitor.sh` | Daemon: ip monitor link + switch-uplink.sh |
| `/usr/local/bin/switch-uplink.sh` | Wisselt uplink: schrijft uplink.conf, herlaadt nftables + whitelist |
| `/usr/local/bin/logging_on.sh` | DNS query-logging inschakelen (schrijft naar /var/log/dnsmasq.log) |
| `/usr/local/bin/logging_off.sh` | DNS query-logging uitschakelen |
| `/etc/toetslocker/docker-compose.yml` | Docker Compose voor gctoetslocking app |
| `/boot/firmware/cmdline.txt` | cgroup_memory=1 toegevoegd |
| `/etc/hosts` | 192.168.50.1 toetslocker.lan toetslocker |
| `/etc/toetslocker.conf` | Actieve configuratie (UPLINK_IFACE, AP_IFACE, AP_IP) |

---

## Werkende services

```
hostapd          active + enabled
dnsmasq          active + enabled
nftables         active + enabled
docker           active + enabled
wlan1-setup      active + enabled
uplink-monitor   active + enabled
toetslocker      active + enabled   (pull latest image + start bij opstart)
```

---

## hostapd-profielen

Twee profielen worden altijd geïnstalleerd. Het installatiescript detecteert automatisch de adapter via USB-ID en kiest het juiste profiel.

| Bestand | Adapter | Actief wanneer |
|---------|---------|----------------|
| `/etc/hostapd/hostapd.conf` | Generiek (RTL8812AU e.d.) | USB-ID `0e8d:7961` **niet** gevonden |
| `/etc/hostapd/hostapd-mt7921u.conf` | AWUS036AXML (MT7921U) | USB-ID `0e8d:7961` gevonden |

Detectie werkt via `lsusb | grep -qi "0e8d:7961"` in `install.sh`. Het actieve profiel staat in `/etc/default/hostapd` als `DAEMON_CONF=`.

**Verschillen MT7921U-profiel t.o.v. generiek:**
- `ieee80211d=1` + `ieee80211h=1` (regulatory domain + DFS-ondersteuning)
- `ht_capab=[HT40+][SHORT-GI-40]` (zonder `DSSS_CCK-40`)
- `vht_capab=[SHORT-GI-80][RX-STBC-1]` (conservatief; geen MAX-MPDU/HTC-VHT)

**Handmatig wisselen van profiel:**
```bash
# Naar MT7921U-profiel:
sed -i 's|hostapd.conf|hostapd-mt7921u.conf|' /etc/default/hostapd && systemctl restart hostapd

# Terug naar generiek profiel:
sed -i 's|hostapd-mt7921u.conf|hostapd.conf|' /etc/default/hostapd && systemctl restart hostapd
```

---

## Kritieke technische details (niet verliezen)

### nftables: table ip custom_nat (priority -150)
Docker draait zijn eigen `table ip nat` op priority -100. Als onze NAT-tabel ook op -100 staat, blokkeert die Docker's DNAT voor de container. Oplossing: onze prerouting-chain draait op **priority -150** (eerder dan Docker), zodat DNS-redirect werkt én Docker's DNAT daarna nog kan vuren.

### nftables: selectieve flush — Docker-tabellen blijven intact
`nftables.conf` doet **geen** `flush ruleset` meer. In plaats daarvan worden alleen onze eigen tabellen (`table ip custom_nat` en `table inet filter`) verwijderd en opnieuw aangemaakt. Docker's `table ip nat` en `table ip filter` (aangemaakt via iptables-nft) worden nooit aangeraakt. Dit voorkomt dat Docker's DNAT-regels verdwijnen bij een nftables-herstart.

### nftables: uplink als variabele via include
De actieve uplink staat in `/etc/nftables.d/uplink.conf`:
```
define UPLINK = eth0
```
`nftables.conf` leest dit via `include "/etc/nftables.d/uplink.conf"` en gebruikt `$UPLINK` in de masquerade- en whitelist-forwardregels. `switch-uplink.sh` hoeft alleen dit kleine bestand te overschrijven en nftables te herladen — `nftables.conf` zelf wordt nooit gewijzigd.

### Docker FORWARD-regel
De nftables FORWARD chain heeft policy drop. Docker-verkeer wordt doorgelaten via hardcoded regels voor **alle drie beheerinterfaces**:
```
iifname "wlan1" oifname "docker0" tcp dport { 80, 8080 } accept   # AP-clients
iifname "eth0"  oifname "docker0" tcp dport { 80, 8080 } accept   # beheer via kabel
iifname "wlan0" oifname "docker0" tcp dport { 80, 8080 } accept   # beheer via WiFi
```
Deze regels veranderen nooit bij een uplink-wissel. De container is altijd bereikbaar via alle interfaces, ongeacht welke uplink actief is.

### DNS whitelist via dnsmasq --nftset
dnsmasq 2.91+ ondersteunt `nftset=/<domain>/4#inet#filter#allowed_ips`. Bij elke DNS-lookup van een whitelisted domein wordt het resolved IP automatisch in de nftables set `allowed_ips` gezet (timeout 1h). Niet-whiteliste domeinen krijgen REFUSED. Direct IP-verkeer wordt geblokkeerd door FORWARD policy drop.

Na een uplink-wissel wordt de whitelist automatisch herladen (`update-whitelist.sh`) zodat de `allowed_ips` set direct actief is op de nieuwe interface.

### Geen healthcheck in docker-compose.yml
De `healthcheck` is verwijderd. Het .NET container image bevat geen `curl`, waardoor de healthcheck altijd faalde met `executable file not found` — ook als de app prima draaide. `docker ps` toont de container als `Up` (zonder `(healthy)`). Automatisch herstarten werkt via `restart: unless-stopped`.

### .lan in plaats van .local
iOS gebruikt mDNS (Bonjour) voor `.local` domeinen — dat gaat buiten de gewone DNS om. Daardoor werkte `toetslocker.local` niet via dnsmasq. Opgelost met `.lan` + `domain=lan` + `dhcp-option=option:domain-search,lan` in dnsmasq.

### SSH alleen bereikbaar via wlan0 (standaard)
Poort 22 stond initieel niet open voor wlan1. Dat betekent: geen SSH via het AP-netwerk, alleen via het uplink-netwerk (wlan0). Opgelost door `iifname "wlan1" tcp dport 22 accept` toe te voegen aan de INPUT-chain in nftables.conf.

### toetslocker.lan werkt niet lokaal op de Pi zelf
dnsmasq luistert alleen op `wlan1` (`bind-interfaces`), dus de Pi zelf gebruikt dnsmasq niet. `toetslocker.lan` moet daarom in `/etc/hosts` staan. Het installatiescript verwijdert altijd de oude regel en schrijft `192.168.50.1 toetslocker.lan toetslocker` opnieuw.

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

## Lokale scripts

| Bestand | Beschrijving |
|---------|-------------|
| `ssh-key-beheer.sh` | SSH key aanmaken, tonen en verwijderen voor Git koppeling; configureert automatisch `~/.ssh/config` voor GitHub |
| `logging_on.sh` | Dnsmasq query-logging inschakelen |
| `logging_off.sh` | Dnsmasq query-logging uitschakelen |

---

## Volgende stappen (optioneel)

- [x] Eigen Docker-applicatie deployen: martijnwieggers/gctoetslocking:latest op poort 80
- [x] docker-compose geïnstalleerd en ingebakken in install.sh
- [x] toetslocker.service: pull latest image + start container bij iedere opstart
- [x] Schooldomeinen toevoegen aan `/etc/whitelist.txt` (itsLearning + Microsoft SSO)
- [x] Reboot-test uitvoeren om te bevestigen dat alles automatisch start
- [x] Dubbele uplink: eth0 (voorkeur) + wlan0 (fallback) met realtime bewaking
- [ ] WPA3 toevoegen aan hostapd.conf (indien USB adapter dat ondersteunt)
- [ ] HTTPS captive portal pagina bouwen (nu plain nginx placeholder)
- [x] Logging: standaard UIT; `logging_on.sh` / `logging_off.sh` geïnstalleerd in `/usr/local/bin/`
- [x] SSH key beheer script klaar (ssh-key-beheer.sh): aanmaken, tonen, verwijderen + automatische GitHub SSH config

---

## Installatiescript gebruiken op verse Pi

**Optie A — via het CMD-script (aanbevolen):**

Dubbelklik op `kopieren-naar-pi.cmd` in de `C:\Claude\pi-install` map.  
Het script vraagt om IP-adres en gebruikersnaam, kopieert beide bestanden via scp en zet automatisch +x.

**Optie B — handmatig:**

```bash
# Script kopiëren naar Pi (vanuit Windows):
scp C:\Claude\pi-install\install.sh C:\Claude\pi-install\switch-uplink.sh <gebruiker>@<pi-ip>:~/

# Op de Pi uitvoeren:
chmod +x install.sh switch-uplink.sh
sudo ./install.sh
```

Het script detecteert automatisch de uplink (eth0 of wlan0) en vraagt interactief om SSID, wachtwoord en landcode.
