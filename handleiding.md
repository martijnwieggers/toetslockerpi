# ToetsLocker — Handleiding

## Verbinden met de Pi

De Pi zendt altijd het WiFi-netwerk **ToetsLocker** uit (via de USB WiFi-adapter). Je kunt er altijd op inloggen, ook als er geen internet is.

**SSH via ToetsLocker-netwerk (altijd beschikbaar):**
1. Verbind met WiFi-netwerk `ToetsLocker` (wachtwoord: `Welkom2024!`)
2. Open terminal → `ssh mwieggers@192.168.50.1`

**SSH via thuisnetwerk of schoolnetwerk:**
```
ssh mwieggers@<wlan0-ip>
```
Het wlan0-IP vind je via: `ip addr show wlan0` (op de Pi) of in de DHCP-lijst van je router.

---

## Webapplicatie openen

Verbind met het ToetsLocker-netwerk en ga naar:
```
http://toetslocker.lan
```
of direct via IP:
```
http://192.168.50.1
```

---

## Webapplicatie openen als beheerder (via schoolnetwerk / wlan0)

Verbind je laptop met hetzelfde netwerk als de Pi (wlan0), en ga naar het wlan0-IP van de Pi:

```bash
# Wlan0-IP opzoeken op de Pi:
ip addr show wlan0
```

Daarna in de browser:
```
http://<wlan0-ip>
```

> `toetslocker.lan` werkt niet via het wlan0-netwerk — dnsmasq luistert alleen op wlan1. Gebruik het IP-adres.

---

## Nieuw WiFi-netwerk toevoegen (bijv. thuis)

De Pi gebruikt wlan0 als internetverbinding. NetworkManager onthoudt alle bekende netwerken en schakelt automatisch over.

```bash
sudo nmcli dev wifi connect "NaamVanHetNetwerk" password "WachtwoordVanHetNetwerk"
```

Daarna verbindt de Pi op die locatie automatisch — ook na een reboot.

---

## Whitelist beheren

Alleen domeinen op de whitelist zijn bereikbaar voor studenten.

**Domeinen toevoegen of verwijderen:**
```bash
sudo nano /etc/whitelist.txt
```

**Wijzigingen activeren:**
```bash
sudo /usr/local/bin/update-whitelist.sh
```

**Huidige toegestane IPs bekijken:**
```bash
sudo nft list set inet filter allowed_ips
```

---

## Services controleren

```bash
sudo systemctl is-active hostapd dnsmasq nftables docker wlan1-setup
```

Alle vijf moeten `active` tonen. Bij problemen:
```bash
sudo systemctl status <servicenaam> --no-pager
```

---

## Docker container beheren

**Status bekijken:**
```bash
docker ps
```

**Container herstarten:**
```bash
docker restart toetslocker
```

**Andere container deployen (vervangt huidige):**
```bash
docker stop toetslocker
docker rm toetslocker
docker run -d --name toetslocker --restart unless-stopped -p 80:8080 <image>
```

> Let op: pas de poort aan op de container. aspnetapp gebruikt `80:8080`, nginx gebruikt `80:80`.

---

## Herinstallatie op verse Pi

```bash
# Kopieer script naar de Pi (vanuit Windows):
scp C:\Claude\pi-install\install.sh mwieggers@<pi-ip>:~/

# Voer uit op de Pi:
chmod +x install.sh
sudo ./install.sh
```

Het script vraagt interactief om SSID, wachtwoord en landcode.
