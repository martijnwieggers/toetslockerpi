@echo off
setlocal

echo.
echo ============================================
echo  ToetsLocker -- bestanden naar Pi kopieren
echo ============================================
echo.

set /p "PI_IP=Pi IP-adres    : "
if "%PI_IP%"=="" ( echo Geen IP ingevoerd. Gestopt. & pause & exit /b 1 )

set /p "PI_USER=Gebruikersnaam : "
if "%PI_USER%"=="" ( echo Geen gebruikersnaam ingevoerd. Gestopt. & pause & exit /b 1 )

echo.
echo Kopieren naar %PI_USER%@%PI_IP%:~/
echo Voer het SSH-wachtwoord in als scp daarom vraagt.
echo.

scp "%~dp0install.sh" "%~dp0switch-uplink.sh" "%PI_USER%@%PI_IP%:~/"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Uitvoerrechten instellen op de Pi...
    ssh "%PI_USER%@%PI_IP%" "chmod +x ~/install.sh ~/switch-uplink.sh"
    echo.
    echo Klaar! Verbind met de Pi en start de installatie:
    echo   ssh %PI_USER%@%PI_IP%
    echo   sudo ./install.sh
    echo.
) else (
    echo.
    echo Fout bij kopieren. Controleer IP-adres en gebruikersnaam.
    echo.
)

pause
