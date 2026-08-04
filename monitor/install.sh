#!/bin/bash
# Instalador del monitor en el host Proxmox.
# Uso: bash /root/nuevo_spotify_bot/monitor/install.sh
set -e

BASE="/root/nuevo_spotify_bot/monitor"
SYSTEMD_DIR="/etc/systemd/system"

echo "[install] Verificando .env…"
if [ ! -f "$BASE/.env" ]; then
    echo "  ⚠️  No existe $BASE/.env — copio el ejemplo. Edítalo con tu chat_id real."
    cp "$BASE/.env.example" "$BASE/.env"
    chmod 600 "$BASE/.env"
fi

echo "[install] Copiando units systemd…"
for unit in yiyolmb-report.service yiyolmb-report.timer \
            yiyolmb-alerts.service yiyolmb-alerts.timer; do
    cp "$BASE/systemd/$unit" "$SYSTEMD_DIR/$unit"
done

echo "[install] daemon-reload + enable + start de los timers…"
systemctl daemon-reload
systemctl enable --now yiyolmb-report.timer yiyolmb-alerts.timer

echo "[install] Timers activos:"
systemctl list-timers yiyolmb-*.timer --no-pager

echo
echo "✅ Instalado. Prueba manual:"
echo "   python3 $BASE/report.py --dry-run --hours 24"
echo "   python3 $BASE/report.py --to <TU_CHAT_ID>"
