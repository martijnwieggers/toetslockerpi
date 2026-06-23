#Requires -RunAsAdministrator
# ICS instellen voor Raspberry Pi — kies adapters op nummer of druk Enter voor de suggestie

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Sort-Object Name

if ($adapters.Count -lt 2) {
    Write-Host "Minder dan 2 actieve adapters gevonden. Controleer de verbindingen." -ForegroundColor Red
    exit 1
}

Write-Host "`nBeschikbare actieve adapters:" -ForegroundColor Cyan
for ($i = 0; $i -lt $adapters.Count; $i++) {
    Write-Host ("  [{0}] {1,-30} {2}" -f ($i + 1), $adapters[$i].Name, $adapters[$i].InterfaceDescription)
}

# Auto-detectie: internet = adapter met default gateway
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric | Select-Object -First 1
$suggestInternet = if ($defaultRoute) {
    ($adapters | Where-Object { $_.ifIndex -eq $defaultRoute.InterfaceIndex } | Select-Object -First 1).Name
} else { "" }
$suggestPi = ($adapters | Where-Object { $_.Name -ne $suggestInternet } | Select-Object -First 1).Name

function Pick-Adapter($prompt, $suggestion) {
    $hint = if ($suggestion) { " [Enter = $suggestion]" } else { "" }
    $sel = Read-Host "`n$prompt$hint"
    if ([string]::IsNullOrWhiteSpace($sel))    { return $suggestion }
    if ($sel -match '^\d+$')                    { return $adapters[[int]$sel - 1].Name }
    return $sel
}

$internetAdapter = Pick-Adapter "Internet adapter (nummer)" $suggestInternet
$piAdapter       = Pick-Adapter "Pi adapter      (nummer)" $suggestPi

if ($internetAdapter -eq $piAdapter) {
    Write-Host "Beide adapters zijn hetzelfde. Gestopt." -ForegroundColor Red
    exit 1
}

Write-Host "`nConfiguratie:" -ForegroundColor Cyan
Write-Host "  Internet : $internetAdapter"
Write-Host "  Pi       : $piAdapter"
$confirm = Read-Host "Doorgaan? [J/n]"
if ($confirm -match '^[Nn]') { Write-Host "Gestopt."; exit 0 }

# ICS via COM object
$HNetShare = New-Object -ComObject HNetCfg.HNetShare
$connections = @{}
foreach ($conn in $HNetShare.EnumEveryConnection()) {
    $name = $HNetShare.NetConnectionProps($conn).Name
    $connections[$name] = $conn
}

$publicConn  = $connections[$internetAdapter]
$privateConn = $connections[$piAdapter]

if (-not $publicConn)  { Write-Host "Internetadapter niet gevonden in ICS."  -ForegroundColor Red; exit 1 }
if (-not $privateConn) { Write-Host "Pi-adapter niet gevonden in ICS."        -ForegroundColor Red; exit 1 }

# Bestaande ICS uitschakelen
foreach ($conn in $HNetShare.EnumEveryConnection()) {
    $config = $HNetShare.INetSharingConfigurationForINetConnection($conn)
    if ($config.SharingEnabled) { $config.DisableSharing() }
}
Start-Sleep -Seconds 2

# ICS inschakelen
$HNetShare.INetSharingConfigurationForINetConnection($publicConn).EnableSharing(0)
$HNetShare.INetSharingConfigurationForINetConnection($privateConn).EnableSharing(1)
Start-Sleep -Seconds 3

# Statisch IP op Pi-adapter
netsh interface ip set address name="$piAdapter" static 192.168.137.1 255.255.255.0 | Out-Null

Write-Host "`nICS geconfigureerd." -ForegroundColor Green
Write-Host "  Windows IP  : 192.168.137.1"
Write-Host "  Pi (DHCP)   : krijgt automatisch een adres via ICS"
Write-Host "  Pi (handm.) : IP 192.168.137.x  GW 192.168.137.1  DNS 8.8.8.8"
Write-Host ""
