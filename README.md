# Raspberry Pi Kiosk Setup

Automatiserat setup-script för Raspberry Pi kiosk-display.

## Användning

Flasha Raspberry Pi OS Lite (64-bit) med Raspberry Pi Imager.
Skapa användare `kiosk` och aktivera SSH.

Logga in via SSH och kör:

```bash
curl -sSL https://raw.githubusercontent.com/frestenb/Pi-Kiosk-Setup/main/setup.sh | sudo bash
```

Följ instruktionerna på skärmen.

## Efter setup

Konfigurera inställningar:
```bash
nano /home/kiosk/.config/kiosk.conf
```

Starta om tjänsterna efter ändringar:
```bash
sudo systemctl restart kiosk
pkill -f kiosk_watchdog.sh && rm -f /tmp/kiosk_watchdog.pid
```
