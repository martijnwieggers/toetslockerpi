# ToetsLocker AP

Raspberry Pi access point met captive portal voor gebruik in de klas. Verbonden studenten bereiken de toetsapplicatie via `https://gctoetslocking.nl` — beveiligd met een geldig Let's Encrypt SSL-certificaat.

---

## Benodigdheden

**Hardware**
- Raspberry Pi 5
- USB WiFi-adapter voor het access point (`wlan1`):
  - ALFA AWUS036AXML (MT7921U-chip) — aanbevolen, automatisch herkend
  - RTL8812AU-gebaseerde adapters — generiek ondersteund
- Internetverbinding via ingebouwde WiFi (`wlan0`) of ethernet (`eth0`)

**Software**
- Raspberry Pi OS Lite (Debian Trixie, 64-bit)
- Root-toegang (`sudo`)

**Accounts**
- GitHub account met toegang tot `ghcr.io/roelofvanleeuwen/gctoetslocking` (voor de Docker image)
- Cloudflare account met beheer over het domein `gctoetslocking.nl` (voor het SSL-certificaat)

---

## Installeren

Voer de volgende commando's uit op de Raspberry Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/martijnwieggers/toetslockerpi/main/install.sh | sudo bash
```

Het script downloadt automatisch alle benodigde hulpscripts en installeert alles in één keer.

---

## Hoe werkt het installatiescript?

### 1. Configuratievragen

Het script begint met een aantal vragen. Bij een herinstallatie worden eerder ingevoerde waarden als standaard getoond — Enter drukken bewaart ze.

```
WiFi netwerknaam (SSID) [ToetsLocker]:
WiFi wachtwoord (min. 8 tekens) [huidig wachtwoord]:
Landcode [NL]:

--- Cloudflare + Let's Encrypt (SSL voor gctoetslocking.nl) ---
  Cloudflare API-token [opgeslagen, Enter = bewaren]:
  E-mailadres voor Let's Encrypt:
```

Daarna detecteert het script automatisch de uplink (eth0 als er een kabel is, anders wlan0) en toont een samenvatting:

```
[--] SSID:         ToetsLocker
[--] Land:         NL
[--] AP-IP:        192.168.50.1 (wlan1)
[--] Uplink:       eth0
[--] CF e-mail:    jouw@email.nl
[--] CF token:     abc12345…

Klopt dit? Doorgaan? [j/N]:
```

### 2. Cloudflare API-token aanmaken

Het script heeft een Cloudflare API-token nodig om via DNS-challenge een Let's Encrypt-certificaat aan te vragen. Je hoeft de Pi niet publiek bereikbaar te maken.

**Stap voor stap:**

1. Ga naar [dash.cloudflare.com](https://dash.cloudflare.com) → rechtsboven op je profiel → **My Profile**
2. Tabblad **API Tokens** → **Create Token**
3. Kies de template **Edit zone DNS**
4. Pas aan:
   - Permissions: Zone → DNS → Edit *(staat al ingevuld)*
   - Zone Resources: Include → Specific zone → `gctoetslocking.nl`
5. **Continue to summary** → **Create Token**
6. Kopieer het token — je ziet het maar één keer

> Het token wordt opgeslagen in `/etc/toetslocker.conf` op de Pi (alleen leesbaar door root).

### 3. Wat het script installeert

Na bevestiging voert het script de volgende stappen automatisch uit:

| Stap | Wat er gebeurt |
|------|----------------|
| 1 | Benodigde packages installeren (hostapd, dnsmasq, nftables, docker) |
| 2 | hostapd configureren — detecteert automatisch de USB WiFi-adapter en kiest het juiste profiel |
| 3 | NetworkManager: wlan1 buiten beheer houden |
| 4 | Statisch IP instellen op wlan1 (192.168.50.1) |
| 5 | dnsmasq configureren (DHCP + DNS — `gctoetslocking.nl` → 192.168.50.1) |
| 6 | IP-forwarding inschakelen en DNS fixeren op 8.8.8.8 |
| 7 | nftables firewall instellen (captive portal, whitelist, HTTPS op poort 443) |
| 8 | Whitelist downloaden van GitHub (itsLearning, Microsoft SSO, Apple/Windows captive portal) |
| 9 | Docker configureren en docker-compose aanmaken (NPM + gctoetslocking) |
| 9a | Inloggen bij ghcr.io (GitHub Container Registry) voor de Docker image |
| 9b | Hulpscripts downloaden: `switch-uplink.sh`, `logging_on.sh`, `logging_off.sh`, `update-whitelist.sh`, `whitelist-sync.sh` |
| 9c | Uplink-monitor installeren (automatisch wisselen tussen eth0 en wlan0) |
| 9d | Systemd-service aanmaken die bij elke opstart de nieuwste images ophaalt |
| 9e | Whitelist-sync timer aanmaken (bij boot + elke 15 min) |
| 9f | npm-setup.sh aanmaken (configureert Nginx Proxy Manager via API) |
| 9g | Docker image cleanup timer aanmaken (wekelijks ongebruikte images verwijderen) |
| 10 | Services starten, Docker images ophalen, NPM configureren, eindcontrole |

### 4. GitHub Container Registry (stap 9a)

Het script vraagt om in te loggen bij `ghcr.io` voor de Docker image. Je hebt een GitHub Personal Access Token (PAT) nodig met scope `read:packages`.

Bij een herinstallatie controleert het script of er al een opgeslagen login is:

```
Bestaande ghcr.io login gevonden: jouwgebruikersnaam
Nieuwe credentials invoeren? [j/N]:
```

### 5. NPM configuratie (stap 10)

Na het starten van de containers configureert het script automatisch Nginx Proxy Manager via de API:

1. Wacht tot de NPM container actief is
2. Logt in met standaard credentials (`admin@example.com` / `changeme`)
3. Vraagt een Let's Encrypt-certificaat aan via Cloudflare DNS-challenge
4. Maakt een proxy host aan: `gctoetslocking.nl` → app op poort 8080

Dit kan enkele minuten duren vanwege DNS-propagatie. Als het mislukt, staat er een melding met instructies om het handmatig opnieuw te proberen.

### 6. Eindcontrole

Na afloop toont het script de status van alle services en een samenvatting:

```
[OK] hostapd actief
[OK] dnsmasq actief
[OK] nftables actief
[OK] docker actief
[OK] wlan1-setup actief
[OK] uplink-monitor actief
[OK] toetslocker actief
[OK] whitelist-sync.timer actief
[OK] docker-prune.timer actief
[OK] npm container actief
[OK] DNS: gctoetslocking.nl → 192.168.50.1
[OK] App intern bereikbaar op poort 8080
[--] HTTPS: certificaat wordt aangevraagd (journalctl -t npm-setup)

  Applicatie URL  : https://gctoetslocking.nl
  NPM admin-UI    : http://192.168.x.x:81  (alleen via beheernetwerk)
```

> De HTTPS-melding is normaal — het certificaat wordt op de achtergrond aangevraagd. Controleer de status met `journalctl -t npm-setup -n 20`.

---

## Na installatie

De webapplicatie is bereikbaar voor verbonden studenten via:

```
https://gctoetslocking.nl
```

De Nginx Proxy Manager admin-interface is bereikbaar via je beheernetwerk (eth0 of wlan0, **niet** via het studentenwifi):

```
http://<uplink-ip>:81
```

Standaard inloggegevens NPM (eerste keer): `admin@example.com` / `changeme` — NPM vraagt dit direct te wijzigen.

---

## Whitelist beheren

Bewerk `whitelist.txt` in deze repository en push naar GitHub. De Pi haalt de wijziging binnen 15 minuten automatisch op.

```bash
# Direct synchroniseren (zonder op de timer te wachten):
sudo systemctl start whitelist-sync.service

# Sync-log bekijken:
journalctl -u whitelist-sync -n 20
```

---

## Handige commando's

```bash
# NPM setup herhalen (als het tijdens installatie mislukte):
sudo /usr/local/bin/npm-setup.sh
journalctl -t npm-setup -n 30

# Uplink status bekijken:
sudo switch-uplink.sh

# DNS query-logging aan/uit:
sudo logging_on.sh
sudo logging_off.sh

# Docker containers bekijken:
docker ps
```
