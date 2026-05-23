#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Raspberry Pi Kiosk Setup
# ═══════════════════════════════════════════════════════════════════════════════
# Ladda ner och kör: 
#   curl -sSL https://raw.githubusercontent.com/frestenb/Pi-Kiosk-Setup/main/setup.sh -o setup.sh
#   sudo bash setup.sh
# ───────────────────────────────────────────────────────────────────────────────

set -e

# ── Färger ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[VARNING]${NC} $1"; }
error()   { echo -e "${RED}[FEL]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ── Kontrollera att scriptet körs som root ────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Kör scriptet som root: sudo bash setup.sh"
fi

KIOSK_USER="kiosk"
KIOSK_HOME="/home/${KIOSK_USER}"

# ── Loggning ──────────────────────────────────────────────────────────────────
LOG_FILE="${KIOSK_HOME}/setup.log"
mkdir -p "${KIOSK_HOME}"
exec > >(tee "${LOG_FILE}") 2>&1
info "Logg sparas till: ${LOG_FILE}"

# ═══════════════════════════════════════════════════════════════════════════════
# KONFIGURATION — Fråga efter inställningar
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Raspberry Pi Kiosk Setup — Konfiguration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo -e "Tryck ${YELLOW}Enter${NC} för att acceptera defaultvärdet inom [ ]\n"

read -p "Kiosk URL [http://172.30.7.79/wifiportal]: " INPUT_URL
KIOSK_URL="${INPUT_URL:-http://172.30.7.79/wifiportal}"

read -p "SSH-port [22]: " INPUT_SSH_PORT
SSH_PORT="${INPUT_SSH_PORT:-22}"

read -p "SMTP-server [smtp.example.com]: " INPUT_SMTP_HOST
SMTP_HOST="${INPUT_SMTP_HOST:-smtp.example.com}"

read -p "SMTP-port [587]: " INPUT_SMTP_PORT
SMTP_PORT_MAIL="${INPUT_SMTP_PORT:-587}"

read -p "SMTP-användare: " SMTP_USER

read -sp "SMTP-lösenord: " SMTP_PASS
echo ""

read -p "Larmmail: " MAIL_TO

echo ""
echo -e "${YELLOW}━━━ Sammanfattning ━━━${NC}"
echo -e "  Kiosk URL:      ${KIOSK_URL}"
echo -e "  SSH-port:       ${SSH_PORT}"
echo -e "  SMTP-server:    ${SMTP_HOST}"
echo -e "  SMTP-port:      ${SMTP_PORT_MAIL}"
echo -e "  SMTP-användare: ${SMTP_USER}"
echo -e "  SMTP-lösenord:  ********"
echo -e "  Larmmail:       ${MAIL_TO}"
echo ""
read -p "Stämmer inställningarna? (j/n): " CONFIRM
if [[ "$CONFIRM" != "j" && "$CONFIRM" != "J" ]]; then
    error "Setup avbruten. Kör scriptet igen."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 1 — Uppdatera systemet
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 1 — Uppdaterar systemet"
apt update && apt upgrade -y
log "Systemet uppdaterat."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 2 — Inaktivera cloud-init
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 2 — Inaktiverar cloud-init"
touch /etc/cloud/cloud-init.disabled
log "cloud-init inaktiverat."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 3 — Byt hostname baserat på MAC-adress
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 3 — Sätter hostname"
MAC=$(cat /sys/class/net/eth0/address | tr -d ':')
HOSTNAME="display-${MAC}"
hostnamectl set-hostname "$HOSTNAME"
sed -i "s/127.0.1.1.*/127.0.1.1\t${HOSTNAME}/" /etc/hosts
log "Hostname satt till: $HOSTNAME"

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 4 — SSH-säkerhet
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 4 — Konfigurerar SSH"
SSH_CONFIG="/etc/ssh/sshd_config"

sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" "$SSH_CONFIG"
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' "$SSH_CONFIG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' "$SSH_CONFIG"
sed -i 's/^#\?PermitEmptyPasswords .*/PermitEmptyPasswords no/' "$SSH_CONFIG"
sed -i 's/^#\?X11Forwarding .*/X11Forwarding no/' "$SSH_CONFIG"
sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 300/' "$SSH_CONFIG"
sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 2/' "$SSH_CONFIG"

grep -q "^AllowUsers" "$SSH_CONFIG" || echo "AllowUsers ${KIOSK_USER}" >> "$SSH_CONFIG"

systemctl restart ssh
log "SSH konfigurerat på port ${SSH_PORT}."
if [ "$SSH_PORT" != "22" ]; then
    warn "Verifiera att du kan ansluta via SSH på port ${SSH_PORT} innan du stänger nuvarande session!"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 5 — Brandvägg (UFW)
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 5 — Konfigurerar brandvägg"
apt install -y ufw

ufw --force reset
ufw default deny incoming
ufw default deny outgoing
ufw allow in ${SSH_PORT}
ufw allow out ${SSH_PORT}
ufw allow out 80
ufw allow out 443
ufw allow out 53
ufw allow out 587
ufw --force enable

log "UFW brandvägg aktiverad."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 6 — Automatiska säkerhetsuppdateringar
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 6 — Automatiska säkerhetsuppdateringar"
apt install -y unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
log "Automatiska säkerhetsuppdateringar aktiverade."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 7 — Inaktivera onödiga tjänster
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 7 — Inaktiverar onödiga tjänster"
for SERVICE in bluetooth cups cups-browsed ModemManager; do
    if systemctl list-unit-files | grep -q "^${SERVICE}.service"; then
        systemctl disable --now "${SERVICE}.service" && log "${SERVICE} inaktiverad."
    else
        info "${SERVICE} finns inte — hoppar över."
    fi
done

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 8 — Installera paket
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 8 — Installerar paket"
apt install -y wayfire chromium rpi-chromium-mods seatd
log "Paket installerade."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 9 — Konfigurera grupper och seatd
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 9 — Konfigurerar grupper och seatd"
groupadd seat 2>/dev/null || true
usermod -aG video,input,tty,seat "$KIOSK_USER"
systemctl enable seatd || true
systemctl start seatd || true
log "Grupper och seatd konfigurerade."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 10 — Inaktivera boot-splash
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 10 — Inaktiverar boot-splash"
CMDLINE="/boot/firmware/cmdline.txt"
if ! grep -q "quiet logo.nologo" "$CMDLINE"; then
    sed -i 's/$/ quiet logo.nologo/' "$CMDLINE"
    log "Boot-splash inaktiverat."
else
    info "Boot-splash redan inaktiverat."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 11 — Inaktivera getty på TTY1
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 11 — Inaktiverar getty på TTY1"
systemctl disable getty@tty1
log "getty@tty1 inaktiverad."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 12 — Skapa konfigfil
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 12 — Skapar konfigfil"
mkdir -p "${KIOSK_HOME}/.config"

cat > "${KIOSK_HOME}/.config/kiosk.conf" << EOF
# ── Kiosk URL ──────────────────────────────────────────────────────────────────
KIOSK_URL="${KIOSK_URL}"

# ── SSH ────────────────────────────────────────────────────────────────────────
SSH_PORT="${SSH_PORT}"

# ── SMTP ───────────────────────────────────────────────────────────────────────
SMTP_HOST="${SMTP_HOST}"
SMTP_PORT="${SMTP_PORT_MAIL}"
SMTP_USER="${SMTP_USER}"
SMTP_PASS="${SMTP_PASS}"

# ── Mail ───────────────────────────────────────────────────────────────────────
MAIL_TO="${MAIL_TO}"
EOF

chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/kiosk.conf"
chmod 600 "${KIOSK_HOME}/.config/kiosk.conf"
log "Konfigfil skapad: ${KIOSK_HOME}/.config/kiosk.conf"

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 13 — Konfigurera Wayfire
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 13 — Konfigurerar Wayfire"

cat > "${KIOSK_HOME}/.config/wayfire.ini" << EOF
[core]
plugins = autostart

[autostart]
chromium = chromium --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble --disable-restore-session-state --kiosk --disable-features=TranslateUI,Translate --lang=sv --accept-lang=sv ${KIOSK_URL}
watchdog = bash ${KIOSK_HOME}/kiosk_watchdog.sh
EOF

chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/wayfire.ini"
log "Wayfire konfigurerat."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 14 — Konfigurera Chromium-profil
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 14 — Konfigurerar Chromium-profil"
mkdir -p "${KIOSK_HOME}/.config/chromium/Default"
cat > "${KIOSK_HOME}/.config/chromium/Default/Preferences" << 'EOF'
{
  "translate": {
    "enabled": false
  },
  "translate_blocked_languages": ["sv"],
  "intl": {
    "accept_languages": "sv,sv-SE"
  }
}
EOF
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.config/chromium"
log "Chromium-profil konfigurerad."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 15 — Skapa systemd-tjänst för Wayfire
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 15 — Skapar systemd-tjänst"
cat > /etc/systemd/system/kiosk.service << EOF
[Unit]
Description=Kiosk
After=systemd-user-sessions.service seatd.service
Wants=seatd.service

[Service]
User=${KIOSK_USER}
Group=seat
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
EnvironmentFile=-/etc/locale.conf
ExecStart=wayfire
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable kiosk
systemctl daemon-reload
log "Systemd-tjänst skapad och aktiverad."

# ═══════════════════════════════════════════════════════════════════════════════
# STEG 16 — Skapa watchdog-script
# ═══════════════════════════════════════════════════════════════════════════════
section "Steg 16 — Skapar watchdog-script"
cat > "${KIOSK_HOME}/kiosk_watchdog.sh" << 'EOF'
#!/bin/bash

# Läs konfigfil
source /home/kiosk/.config/kiosk.conf

URL=$(grep "^chromium" /home/kiosk/.config/wayfire.ini | grep -oP 'http[s]?://[^\s"]+')
LOG="/home/kiosk/kiosk_watchdog.log"

PIDFILE="/tmp/kiosk_watchdog.pid"
if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"

DEVICE=$(hostname)
NOTIFIED=false

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

send_mail() {
    local SUBJECT="$1"
    local MESSAGE="$2"
    curl -s --ssl-reqd \
        --url "smtp://$SMTP_HOST:$SMTP_PORT" \
        --user "$SMTP_USER:$SMTP_PASS" \
        --mail-from "$SMTP_USER" \
        --mail-rcpt "$MAIL_TO" \
        -T <(printf "From: $SMTP_USER\nTo: $MAIL_TO\nSubject: $SUBJECT\n\n$MESSAGE")
}

reload_browser() {
    log "Startar om Chromium..."
    pkill chromium
    sleep 3
    rm -f /home/kiosk/.config/chromium/Singleton*
    WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 chromium \
        --noerrdialogs --disable-infobars --no-first-run \
        --disable-session-crashed-bubble --disable-restore-session-state \
        --kiosk --disable-features=TranslateUI,Translate \
        --lang=sv --accept-lang=sv "$URL" &
    log "Chromium omstartad."
}

check_url() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$URL"
}

sleep 30
log "=== Watchdog startad. Övervakar: $URL ==="

while true; do
    HTTP=$(check_url)
    if [ "$HTTP" == "200" ]; then
        if [ "$NOTIFIED" = true ]; then
            MSG="✅ $DEVICE – Kiosksidan är tillgänglig igen. URL: $URL"
            send_mail "[$DEVICE] Kiosksidan OK igen" "$MSG"
            log "Återhämtningsnotis skickad."
        fi
        NOTIFIED=false
        log "OK: $URL svarar (HTTP 200)"
        sleep 60
    else
        reload_browser
        if [ "$NOTIFIED" = false ]; then
            MSG="🚨 $DEVICE – Kiosksidan svarar INTE! URL: $URL | HTTP: $HTTP | Tid: $(date '+%Y-%m-%d %H:%M')"
            send_mail "[$DEVICE] LARM: Kiosksidan nere" "$MSG"
            log "Larmnotis skickad."
            NOTIFIED=true
        else
            log "FEL: Sidan fortfarande nere - försöker igen om 30 sek"
        fi
        sleep 30
    fi
done
EOF

chmod +x "${KIOSK_HOME}/kiosk_watchdog.sh"
chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/kiosk_watchdog.sh"
log "Watchdog-script skapat."

# ═══════════════════════════════════════════════════════════════════════════════
# KLART
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Setup klar! Starta om för att aktivera kiosken.${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${YELLOW}Starta om:${NC}"
echo -e "  sudo reboot"
echo ""
echo -e "  ${YELLOW}Om du ändrar konfigfilen senare:${NC}"
echo -e "  sudo systemctl restart kiosk"
echo -e "  pkill -f kiosk_watchdog.sh && rm -f /tmp/kiosk_watchdog.pid"
echo ""
echo -e "  ${YELLOW}Setup-logg sparad till:${NC}"
echo -e "  ${LOG_FILE}"
echo ""
