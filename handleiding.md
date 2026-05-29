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

## Docker Compose gebruiken

Kloon de repository op de Pi en bouw eerst de image:

```bash
git clone git@github.com:<gebruiker>/<repository>.git
cd <repository>
sudo docker-compose build --no-cache
```

`docker-compose build --no-cache` bouwt de Docker-image op basis van de `Dockerfile` in de repository. De vlag `--no-cache` zorgt ervoor dat alle lagen opnieuw worden gebouwd — dus zonder gebruik te maken van eerder gecachte stappen. Dit is handig bij een eerste installatie of als je zeker wilt zijn dat de nieuwste code in de image zit.

Start daarna de container op de achtergrond:

```bash
sudo docker-compose up -d
```

De `-d` vlag staat voor *detached*: de container draait op de achtergrond. Je terminal blijft vrij en de container blijft draaien ook als je de SSH-sessie sluit. Omdat de `docker-compose.yaml` `restart: always` bevat, start de container ook automatisch opnieuw op na een crash of reboot van de Pi — zonder dat je iets hoeft te doen.

**Stoppen:**
```bash
sudo docker-compose down
```

**Logs bekijken:**
```bash
sudo docker-compose logs -f
```

**Bijwerken na git pull:**
```bash
git pull
sudo docker-compose build --no-cache
sudo docker-compose up -d
```

---

## Uitleg docker-compose.yaml

```yaml
services:
  wifi-manager:
    image: wifi-manager:latest
    container_name: wifi-manager

    build:
      context: .
      dockerfile: Dockerfile
      network_mode: host

    restart: always

    network_mode: host
    privileged: true
    pid: host

    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - ASPNETCORE_URLS=http://+:8080
      - TZ=Europe/Amsterdam
      - DOTNET_RUNNING_IN_CONTAINER=true

    volumes:
      - ./logs:/app/logs
      - /var/run/dbus:/var/run/dbus:ro
      - /etc/NetworkManager:/etc/NetworkManager:ro

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

    deploy:
      resources:
        limits:
          cpus: '3.0'
          memory: 6G
        reservations:
          cpus: '2'
          memory: 4G
```

### image en container_name

```yaml
image: wifi-manager:latest
container_name: wifi-manager
```

`image` is de naam die de gebouwde image krijgt. `container_name` geeft de draaiende container een vaste naam, zodat je hem altijd met `docker restart wifi-manager` of `docker logs wifi-manager` kunt aanspreken.

### build

```yaml
build:
  context: .
  dockerfile: Dockerfile
  network_mode: host
```

Bepaalt hoe de image gebouwd wordt. `context: .` betekent dat de huidige map (de root van de repository) als bouwcontext wordt gebruikt — alle bestanden daarin zijn beschikbaar tijdens de build. `dockerfile: Dockerfile` verwijst naar het bestand met de buildinstructies. `network_mode: host` zorgt dat de container tijdens het builden toegang heeft tot het hostnetwerk, wat nodig kan zijn als de build externe pakketten downloadt.

### restart

```yaml
restart: always
```

De container herstart altijd automatisch: na een crash, na `docker-compose down && up`, en na een reboot van de Pi. Dit zorgt ervoor dat de applicatie altijd draait zonder handmatige tussenkomst.

### network_mode: host

```yaml
network_mode: host
```

De container deelt het netwerk van de Pi rechtstreeks — er is geen NAT of bridge. Dit is noodzakelijk omdat de applicatie de echte netwerkinterfaces (`wlan0`, `wlan1`) moet kunnen zien en aansturen. Een bijwerking is dat de `ports`-instelling wordt genegeerd: de container luistert direct op de poorten van de Pi, dus poort `8080` van de container is meteen poort `8080` van de Pi.

### privileged en pid

```yaml
privileged: true
pid: host
```

`privileged: true` geeft de container volledige toegang tot hardware en systeemaanroepen van de host. Dit is nodig voor netwerkbeheeroperaties zoals het instellen van interfaces. `pid: host` laat de container de PID-naamruimte van de host delen, zodat PID 1 verwijst naar systemd op de Pi. Dit maakt het mogelijk om via `nsenter -t 1` commando's uit te voeren in de host-omgeving, bijvoorbeeld voor een gecontroleerde shutdown of reboot.

### environment

```yaml
environment:
  - ASPNETCORE_ENVIRONMENT=Production
  - ASPNETCORE_URLS=http://+:8080
  - TZ=Europe/Amsterdam
  - DOTNET_RUNNING_IN_CONTAINER=true
```

| Variable | Betekenis |
|---|---|
| `ASPNETCORE_ENVIRONMENT` | ASP.NET Core draait in productiemodus (geen developer-foutpagina's, optimale instellingen) |
| `ASPNETCORE_URLS` | De applicatie luistert op poort `8080` op alle netwerk­interfaces |
| `TZ` | Tijdzone voor logregels en tijdstempels in de applicatie |
| `DOTNET_RUNNING_IN_CONTAINER` | Vertelt de .NET runtime dat hij in een container draait, wat gedrag zoals signaalafhandeling aanpast |

### volumes

```yaml
volumes:
  - ./logs:/app/logs
  - /var/run/dbus:/var/run/dbus:ro
  - /etc/NetworkManager:/etc/NetworkManager:ro
```

| Mount | Doel |
|---|---|
| `./logs:/app/logs` | Logbestanden worden buiten de container opgeslagen in de `logs/` map van de repository. Ze blijven bewaard als de container opnieuw gebouwd wordt. |
| `/var/run/dbus` | D-Bus socket van de host. NetworkManager communiceert via D-Bus; de applicatie heeft dit nodig om draadloze netwerken te beheren. Read-only omdat de app alleen leest en luistert. |
| `/etc/NetworkManager` | NetworkManager-configuratiebestanden. Hiermee kan de applicatie bekende netwerken uitlezen. Read-only. |

### healthcheck

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

Docker controleert elke 30 seconden of de applicatie reageert via een HTTP-verzoek. Als de applicatie niet antwoordt binnen 10 seconden, telt dat als een mislukte poging. Na 3 opeenvolgende mislukkingen markeert Docker de container als `unhealthy`. De eerste 10 seconden na opstarten worden overgeslagen (`start_period`) zodat de applicatie de kans krijgt om op te starten zonder meteen als ongezond te worden beschouwd.

### deploy.resources

```yaml
deploy:
  resources:
    limits:
      cpus: '3.0'
      memory: 6G
    reservations:
      cpus: '2'
      memory: 4G
```

Stelt limieten en reserveringen in voor CPU en geheugen. De `limits` zijn het maximum dat de container mag gebruiken; de Pi zal de container afremmen of geheugen weigeren als dit overschreden wordt. De `reservations` zijn wat Docker garandeert beschikbaar te houden voor deze container. Op een Raspberry Pi 5 zorgen deze waarden dat de applicatie voldoende resources heeft zonder de rest van het systeem te verstikken.

---

## Docker container beheren

**Status bekijken:**
```bash
docker ps
```

**Container herstarten:**
```bash
docker restart wifi-manager
```

**Andere container deployen (vervangt huidige):**
```bash
docker stop <container-naam>
docker rm <container-naam>
docker run -d --name <container-naam> --restart unless-stopped -p 80:8080 <image>
```

> Let op: pas de poort aan op de container. aspnetapp gebruikt `80:8080`, nginx gebruikt `80:80`.

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

```bash
# Kopieer script naar de Pi (vanuit Windows):
scp C:\Claude\pi-install\install.sh <gebruiker>@<pi-ip>:~/

# Voer uit op de Pi:
chmod +x install.sh
sudo ./install.sh
```

Het script vraagt interactief om SSID, wachtwoord en landcode.
