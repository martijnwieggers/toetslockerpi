# Automatische installatie via Raspberry Pi Imager (voorstel — nog niet gebouwd)

Doel: een verse SD-kaart flashen met Raspberry Pi Imager en de ToetsLocker-installatie
volledig automatisch laten verlopen bij de eerste boot, met alle parameters vooraf meegegeven.

Status: **idee/ontwerp** — hieronder staat het uitgewerkte voorstel. Er is nog niets van gebouwd.

---

## Wat Raspberry Pi Imager zelf kan (en niet kan)

De "OS customization" van Imager (tandwiel-icoon) regelt:

- hostname
- gebruiker + wachtwoord
- SSH aanzetten
- **uplink-WiFi (wlan0)** — meteen de nette manier om die parameters mee te geven
- locale/landcode

Onder water schrijft Imager dit naar een `firstrun.sh` op de boot-partitie, aangeroepen via
`systemd.run=` in `cmdline.txt` (op Bookworm/Trixie bestaat daarnaast `custom.toml`, maar dat
ondersteunt alleen de standaardvelden).

**Beperking:** eigen scripts meegeven kan **niet** via de Imager-UI — er is geen veld voor.
Wat wél kan: na het flashen is de boot-partitie een gewone FAT-partitie die Windows kan lezen
en schrijven. Daar kun je zelf iets injecteren.

Bronnen:
- https://github.com/raspberrypi/rpi-imager/issues/554
- https://forums.raspberrypi.com/viewtopic.php?t=320331
- https://khalifa.ws/posts/unattended-first-boot-config-for-raspberry-pi.html
- https://deepwiki.com/raspberrypi/rpi-imager/3.2-os-customization

---

## Voorstel: Imager + één PowerShell-nabewerking

### Stap 1 — `install.sh` krijgt een unattended-modus

Als `/boot/firmware/toetslocker-setup.conf` bestaat:

- leest install.sh daar alle parameters uit (SSID, WiFi-wachtwoord, landcode, ghcr-gebruiker + PAT)
- worden álle prompts overgeslagen, inclusief de j/N-bevestiging en de interactieve ghcr-login
- wordt het bestand na een geslaagde installatie **verwijderd** (er staat een PAT in)

### Stap 2 — nieuw script `prepare-sd.ps1` in de repo

Draaien op Windows direct na het flashen, terwijl de kaart nog in de pc zit. Het script:

1. Vindt de boot-partitie automatisch (volumelabel `bootfs`).
2. Vraagt de parameters (of leest ze uit een antwoordbestand) en schrijft `toetslocker-setup.conf`.
3. Injecteert in de Imager-`firstrun.sh` — vóór de cleanup-regel — een blok dat een oneshot
   systemd-service aanmaakt (`toetslocker-firstinstall.service`): wachten op network-online,
   `install.sh` van GitHub downloaden, unattended uitvoeren, en zichzelf bij succes uitschakelen.
   Fallback: als er geen firstrun.sh is (Imager zonder customization gebruikt), maakt het script
   er zelf één aan en past het `cmdline.txt` aan.

**Waarom via een service en niet direct in `firstrun.sh`:** die draait heel vroeg in de boot,
vóór netwerk en apt bruikbaar zijn, en de installatie duurt 10–15 minuten. Beter: eerste boot
normaal laten afronden en de installatie daarna als service laten lopen. Voortgang volgen met:

```bash
journalctl -u toetslocker-firstinstall -f
```

### De workflow wordt dan

1. Imager: OS kiezen, customization invullen (hostname, user, uplink-WiFi, SSH aan), flashen.
2. `prepare-sd.ps1` draaien → parameters invullen.
3. Kaart in de Pi, USB-WiFi-adapter erin, aanzetten — na een kwartier staat er een werkende ToetsLocker.

---

## Kanttekeningen

- **Secrets op de FAT-partitie:** het WiFi-wachtwoord en de PAT staan tot de eerste boot als
  platte tekst op de kaart. Dat is inherent aan deze aanpak (Imager doet hetzelfde met het
  WiFi-wachtwoord). Schadebeperking: fine-grained PAT met alléén `read:packages`, en het
  conf-bestand wordt na installatie gewist.
- **Alternatief voor grotere aantallen Pi's:** een kant-en-klaar "golden image" bakken met
  [pi-gen](https://github.com/RPi-Distro/pi-gen) en dát via Imager flashen — geen
  internet-afhankelijke eerste installatie. Nu niet gekozen: veel meer onderhoud, en de
  whitelist-sync plus de auto-pull van de container houden de Pi's toch al actueel. Alleen bij
  wijzigingen aan `install.sh` zelf zou je het image opnieuw moeten bakken.
- `custom.toml` is geen optie voor het script zelf (alleen standaardvelden); de
  Imager-customization gebruiken we gewoon voor wat hij wél kan.

---

## Te bouwen (wanneer dit wordt opgepakt)

- [ ] Unattended-modus in `install.sh` (leest `/boot/firmware/toetslocker-setup.conf`, versie ophogen)
- [ ] `prepare-sd.ps1` (boot-partitie vinden, conf schrijven, firstrun.sh injecteren)
- [ ] Documentatie bijwerken in `status.md` / `handleiding.md`
