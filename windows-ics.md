# Windows ICS instellen voor Raspberry Pi

Internet Connection Sharing (ICS) laat een Windows-pc zijn internetverbinding delen via een tweede netwerkadapter — bijvoorbeeld een USB-ethernetadapter die rechtstreeks op de Pi is aangesloten.

---

## Wanneer gebruik je dit?

Gebruik ICS als de Pi geen eigen internetverbinding heeft (geen WiFi-uplink, geen schoolnetwerkkabel) maar wel internet nodig heeft — bijvoorbeeld tijdens de installatie of voor onderhoud.

---

## Vereisten

| Wat | Details |
|-----|---------|
| Twee netwerkadapters op de pc | Eén met internet (bijv. Wi-Fi of LAN), één naar de Pi (bijv. USB-ethernet) |
| Raspberry Pi verbonden via kabel | USB-ethernetadapter of Thunderbolt-ethernet naar Pi |
| PowerShell als **Administrator** | Zie hieronder |

---

## Stap 1 — PowerShell als Administrator openen

**Optie A — Startmenu:**
1. Druk op de **Windows-toets**
2. Typ `PowerShell`
3. Klik met de **rechtermuisknop** op *Windows PowerShell*
4. Kies **Als administrator uitvoeren**

**Optie B — Rechtsklik op de taakbalk:**
1. Rechtsklik op de **Start-knop**
2. Kies **Windows PowerShell (Admin)** of **Terminal (Admin)**

> Je ziet een UAC-bevestigingsvenster — klik op **Ja**.

---

## Stap 2 — Script uitvoeren

Navigeer naar de map met het script en voer het uit:

```powershell
cd C:\Claude\pi-install
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\windows_ics.ps1
```

> `Set-ExecutionPolicy` is alleen nodig als PowerShell scripts blokkeert. De instelling geldt alleen voor deze sessie.

---

## Stap 3 — Adapters kiezen

Het script toont alle actieve netwerkadapters als genummerde lijst, bijvoorbeeld:

```
Beschikbare actieve adapters:
  [1] Ethernet          Realtek USB GbE Family Controller
  [2] Wi-Fi             Intel(R) Wi-Fi 6 AX201

Internet adapter (nummer) [Enter = Wi-Fi]:
Pi adapter      (nummer) [Enter = Ethernet]:
```

Het script detecteert automatisch:
- **Internet adapter** — de adapter met een actieve standaardroute (meestal Wi-Fi of schoolnetwerk-LAN)
- **Pi adapter** — de overige actieve adapter (meestal de USB-ethernetadapter)

Druk **Enter** als de suggestie klopt, of typ het nummer van de juiste adapter.

---

## Stap 4 — Bevestigen

Het script toont een samenvatting en vraagt om bevestiging:

```
Configuratie:
  Internet : Wi-Fi
  Pi       : Ethernet

Doorgaan? [J/n]:
```

Typ `j` en druk Enter.

---

## Resultaat

Na afloop:

| Parameter | Waarde |
|-----------|--------|
| Windows IP (Pi-adapter) | `192.168.137.1` |
| Pi IP via DHCP | automatisch, bijv. `192.168.137.x` |
| Gateway op Pi | `192.168.137.1` |
| DNS op Pi | `192.168.137.1` of `8.8.8.8` |

Windows stelt automatisch een DHCP-server in op de Pi-adapter. De Pi krijgt normaal gesproken automatisch een IP-adres.

---

## Pi bereiken via SSH na ICS

De Pi krijgt via DHCP automatisch een IP in het bereik `192.168.137.x`. Zoek het op met:

```powershell
# Op Windows — toont verbonden apparaten
arp -a
```

Verbind daarna via SSH:

```powershell
ssh mwieggers@192.168.137.x
```

---

## Veelvoorkomende problemen

| Probleem | Oplossing |
|----------|-----------|
| Script start niet | PowerShell **niet** als administrator gestart — zie Stap 1 |
| Adapter niet gevonden | Controleer of de USB-ethernetadapter herkend is (`Apparaatbeheer`) en de kabel in de Pi zit |
| Pi krijgt geen IP | Wacht 10–15 seconden na ICS-activatie; probeer daarna `ipconfig /release` + `ipconfig /renew` op Windows |
| ICS werkt na herstart niet meer | Windows schakelt ICS niet automatisch in na herstart — voer het script opnieuw uit |
| Fout: "adapter niet gevonden in ICS" | Start het script opnieuw; soms heeft Windows een moment nodig na het inpluggen van de adapter |
