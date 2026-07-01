# ToetsLocker AP

Raspberry Pi access point met captive portal voor gebruik in de klas.

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

---

## Installeren

Voer het volgende commando uit op de Raspberry Pi:

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/martijnwieggers/toetslockerpi/main/install.sh)
```

Het script downloadt automatisch alle benodigde hulpscripts en installeert alles in één keer.

---

## Hoe werkt het installatiescript?

### 1. Configuratievragen

Het script begint met een paar vragen. Bij een herinstallatie worden de eerder ingevoerde waarden als standaard getoond — je kunt dan gewoon Enter drukken om ze te behouden.

```
WiFi netwerknaam (SSID) [ToetsLocker]:
WiFi wachtwoord (min. 8 tekens) [huidig wachtwoord]:
Landcode [NL]:
```

Daarna detecteert het script automatisch de uplink-interface (eth0 als er een netwerkkabel is aangesloten, anders wlan0) en toont een samenvatting:

```
[--] SSID:     ToetsLocker
[--] Land:     NL
[--] AP-IP:    192.168.50.1 (wlan1)
[--] Uplink:   eth0

Klopt dit? Doorgaan? [j/N]:
```

### 2. Wat het script installeert

Na bevestiging voert het script de volgende stappen automatisch uit:

| Stap | Wat er gebeurt |
|------|----------------|
| 1 | Benodigde packages installeren (hostapd, dnsmasq, nftables, docker) |
| 2 | hostapd configureren — detecteert automatisch de USB WiFi-adapter en kiest het juiste profiel |
| 3 | NetworkManager: wlan1 buiten beheer houden |
| 4 | Statisch IP instellen op wlan1 (192.168.50.1) |
| 5 | dnsmasq configureren (DHCP + DNS voor het AP-netwerk) |
| 6 | IP-forwarding inschakelen en DNS fixeren op 8.8.8.8 |
| 7 | nftables firewall instellen (captive portal + whitelist) |
| 8 | Standaard whitelist aanmaken (itsLearning, Microsoft SSO, Apple/Windows captive portal) |
| 9 | Docker configureren en de ToetsLocker-container instellen |
| 9a | Inloggen bij ghcr.io (GitHub Container Registry) voor de Docker image |
| 9b | Hulpscripts downloaden: `switch-uplink.sh`, `logging_on.sh`, `logging_off.sh` |
| 9c | Uplink-monitor installeren (automatisch wisselen tussen eth0 en wlan0) |
| 9d | Systemd-service aanmaken die bij elke opstart de nieuwste image ophaalt |
| 10 | Alle services starten en eindcontrole uitvoeren |

### 3. GitHub Container Registry (stap 9a)

Het script vraagt om in te loggen bij `ghcr.io` om de Docker-image te kunnen ophalen. Je hebt hiervoor een GitHub Personal Access Token (PAT) nodig met de scope `read:packages`.

Bij een herinstallatie controleert het script of er al een opgeslagen login is en vraag je of je nieuwe credentials wilt invoeren.

```
Bestaande ghcr.io login gevonden: jouwgebruikersnaam
Nieuwe credentials invoeren? [j/N]:
```

### 4. Eindcontrole

Na afloop toont het script de status van alle services en een samenvatting:

```
[OK] hostapd actief
[OK] dnsmasq actief
[OK] nftables actief
[OK] docker actief
[OK] wlan1-setup actief
[OK] uplink-monitor actief
[OK] toetslocker actief
[OK] DNS: toetslocker.lan → 192.168.50.1
[OK] HTTP: gctoetslocking app bereikbaar op poort 80
```

---

## Na installatie

De webapplicatie is bereikbaar via het AP-netwerk van de Pi:

```
http://toetslocker.lan
```

of direct via IP:

```
http://192.168.50.1
```
