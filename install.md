# Installatie

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

Het script stelt je een paar vragen (SSID, wachtwoord, landcode) en installeert daarna automatisch alles wat nodig is. Bij een herinstallatie worden de eerder ingevoerde waarden als standaard getoond.

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
