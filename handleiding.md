# ToetsLocker — Handleiding

## Verbinden met de Pi

De Pi zendt altijd een WiFi-netwerk uit via de USB WiFi-adapter. De naam (SSID) en het wachtwoord zijn ingegeven tijdens de installatie met `install.sh` (standaard: **ToetsLocker** / `Welkom2024!`). Je kunt er altijd op inloggen, ook als er geen internet is.

**SSH via het AP-netwerk (altijd beschikbaar):**
1. Verbind met het WiFi-netwerk van de Pi (SSID ingegeven tijdens installatie, standaard `ToetsLocker`)
2. Open terminal → `ssh <gebruiker>@192.168.50.1`

**SSH via thuisnetwerk of schoolnetwerk:**
```
ssh <gebruiker>@<wlan0-ip>
```
Het wlan0-IP vind je via: `ip addr show wlan0` (op de Pi) of in de DHCP-lijst van je router.

---

## Webapplicatie openen

Verbind met het AP-netwerk van de Pi en ga naar:
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

## Uplink beheer

De Pi werkt met twee mogelijke uplinks: een netwerkkabel (eth0) heeft altijd voorkeur boven WiFi (wlan0). De keuze wordt automatisch gemaakt bij opstart én bij het in- of uitpluggen van een kabel.

**Handmatig wisselen (bijv. voor testen):**
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
```

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

## DNS-logging in-/uitschakelen

Dnsmasq query-logging staat standaard **uit**. De scripts zijn beschikbaar in `/usr/local/bin/`.

**Inschakelen:**
```bash
sudo logging_on.sh
```

**Uitschakelen:**
```bash
sudo logging_off.sh
```

**Live meekijken (alle berichten):**
```bash
sudo tail -f /var/log/dnsmasq.log
```

**Alleen DNS-queries (geen DHCP-ruis):**
```bash
sudo tail -f /var/log/dnsmasq.log | grep query
```

**Geblokkeerde domeinen bekijken:**
```bash
sudo grep REFUSED /var/log/dnsmasq.log
```

---

## Services controleren

```bash
sudo systemctl is-active hostapd dnsmasq nftables docker wlan1-setup uplink-monitor toetslocker
```

Alle zeven moeten `active` tonen. Bij problemen:
```bash
sudo systemctl status <servicenaam> --no-pager
```

---

## Docker container beheren

De container wordt beheerd via `toetslocker.service`. Bij elke opstart haalt de service automatisch de nieuwste image op van ghcr.io en start de container.

**Status bekijken:**
```bash
docker ps
systemctl status toetslocker
```

> `docker ps` toont `Up` zonder `(healthy)` — de healthcheck is verwijderd omdat `curl` niet in het .NET image zit. Dit is normaal.

**Container herstarten:**
```bash
sudo systemctl restart toetslocker
```

**Logs bekijken:**
```bash
docker logs toetslocker -f
```

**Nieuwste image handmatig ophalen en starten:**
```bash
sudo docker compose -f /etc/toetslocker/docker-compose.yml pull
sudo systemctl restart toetslocker
```

---

## Git koppeling instellen (SSH key)

Gebruik het script `ssh-key-beheer.sh` om een SSH key aan te maken en toe te voegen aan GitHub.

**Script kopiëren naar de Pi (vanuit Windows):**
```bash
scp C:\Claude\pi-install\ssh-key-beheer.sh <gebruiker>@<pi-ip>:~/
```

**Uitvoeren op de Pi:**
```bash
chmod +x ssh-key-beheer.sh
./ssh-key-beheer.sh
```

Het menu biedt:
- **1** — Nieuwe SSH key aanmaken (vraagt om naam, genereert sleutelpaar, configureert `~/.ssh/config` voor GitHub, toont direct de public key)
- **2** — Lijst van bestaande keys tonen
- **3** — Public key opnieuw tonen
- **4** — SSH key verwijderen (verwijdert sleutelpaar én GitHub-config)

**Public key toevoegen aan GitHub:**
1. Kopieer de public key die het script toont
2. Ga naar GitHub → Settings → SSH and GPG keys → New SSH key
3. Plak de sleutel en sla op

**Verbinding testen:**
```bash
ssh -T git@github.com
```

**Git instellen op de Pi:**
```bash
git config --global user.name "<naam>"
git config --global user.email "<email>"
```

---

## Herinstallatie op verse Pi

Het makkelijkst via `kopieren-naar-pi.cmd` op Windows: dubbelklik het bestand, voer IP en gebruikersnaam in. Het kopieert `install.sh`, `switch-uplink.sh`, `logging_on.sh` en `logging_off.sh` naar de Pi en zet automatisch `+x`.

Daarna op de Pi:
```bash
sudo ./install.sh
```

**Of handmatig:**
```bash
# Vanuit Windows:
scp C:\Claude\pi-install\install.sh <gebruiker>@<pi-ip>:~/

# Op de Pi:
chmod +x install.sh
sudo ./install.sh
```

Het script vraagt interactief om SSID, wachtwoord en landcode. Bij een herinstallatie op een Pi met bestaande ghcr.io credentials wordt gevraagd of deze hergebruikt moeten worden — de huidige gebruikersnaam wordt getoond.
