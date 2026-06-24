@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1

echo.
echo ============================================
echo  ToetsLocker -- bestanden naar Pi kopiëren
echo ============================================
echo.

set /p "PI_IP=Pi IP-adres    : "
if "!PI_IP!"=="" (
    echo Geen IP ingevoerd. Gestopt.
    pause & exit /b 1
)

set /p "PI_USER=Gebruikersnaam : "
if "!PI_USER!"=="" (
    echo Geen gebruikersnaam ingevoerd. Gestopt.
    pause & exit /b 1
)

:: Wachtwoord verborgen inlezen via PowerShell
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command ^
    "$pw = Read-Host 'Wachtwoord      ' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))"`) do set "PI_PASS=%%p"

if "!PI_PASS!"=="" (
    echo Geen wachtwoord ingevoerd. Gestopt.
    pause & exit /b 1
)

echo.
echo Kopiëren naar !PI_USER!@!PI_IP!:~/
echo   - install.sh
echo   - switch-uplink.sh
echo.

set "FILES=%~dp0install.sh %~dp0switch-uplink.sh"

:: Gebruik pscp (PuTTY) als beschikbaar — ondersteunt -pw flag
where pscp >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pscp -pw "!PI_PASS!" -batch "%~dp0install.sh" "%~dp0switch-uplink.sh" "!PI_USER!@!PI_IP!:~/"
) else (
    :: Geen pscp beschikbaar — gebruik standaard scp
    :: Windows scp ondersteunt geen -pw; SSH vraagt zelf om het wachtwoord
    echo Tip: installeer PuTTY voor automatisch inloggen (pscp -pw).
    echo      Voer hieronder het wachtwoord opnieuw in als SSH ernaar vraagt.
    echo.
    scp "%~dp0install.sh" "%~dp0switch-uplink.sh" "!PI_USER!@!PI_IP!:~/"
)

if %ERRORLEVEL% EQU 0 (
    echo.
    echo  OK  Bestanden gekopieerd.
    echo.
    echo Verbind met de Pi:
    echo   ssh !PI_USER!@!PI_IP!
    echo.
    echo Start daarna de installatie:
    echo   sudo ./install.sh
    echo.
) else (
    echo.
    echo  FOUT bij kopiëren.
    echo  Controleer: IP-adres, gebruikersnaam en wachtwoord.
    echo.
)

set "PI_PASS="
pause
