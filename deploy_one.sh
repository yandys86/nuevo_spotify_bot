#!/bin/bash
# Despliegue a UNA SOLA VM via qm guest exec (v7.1 + limpieza del bot viejo + xauth fix)
# Uso: ./deploy_one.sh <VM_ID>
# Ejemplo: ./deploy_one.sh 120

set -u

if [ -z "${1:-}" ]; then
    echo "Uso: $0 <VM_ID>"
    echo "Ejemplo: $0 120"
    exit 1
fi

VM_ID="$1"
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"
OLD_BOT_DIR="/home/localuser/spotify_robot"

# Helper: ejecutar comando corto en la VM con timeout corto
gexec() {
    local timeout="$1"; shift
    qm guest exec --timeout "$timeout" "$VM_ID" -- /bin/bash -c "$1"
}

echo "================================================"
echo " Despliegue a UNA VM (v7.1 + cleanup + xauth fix)"
echo " VM ID: $VM_ID"
echo "================================================"

# 0. Verificar agente
echo -e "\n[VM $VM_ID] 0. Verificando QEMU guest agent..."
if ! qm agent "$VM_ID" ping 2>/dev/null; then
    echo "[VM $VM_ID] ERROR: qm guest agent no responde. Prueba 'qm reboot $VM_ID' y espera 30s."
    exit 1
fi
echo "[VM $VM_ID] Agent OK"

# === FASE 1: LIMPIEZA DEL BOT VIEJO (partida en comandos cortos) ===

echo -e "\n[VM $VM_ID] 1a. Deteniendo servicios systemd anteriores..."
gexec 30 "systemctl stop yiyolmb.service 2>/dev/null; systemctl stop yiyobot.service 2>/dev/null; systemctl disable yiyolmb.service 2>/dev/null; rm -f /etc/systemd/system/yiyolmb.service /etc/systemd/system/yiyobot.service; systemctl daemon-reload; echo STEP1A_OK"

echo -e "\n[VM $VM_ID] 1b. Matando bot VIEJO (spotify_monitor.py y qterminal envoltorio)..."
gexec 30 "pkill -f spotify_monitor.py 2>/dev/null; pkill -f spotify_app_control.py 2>/dev/null; pkill -f spotify_like.py 2>/dev/null; pkill -f init_launcher_main.py 2>/dev/null; pkill -f 'qterminal.*spotify' 2>/dev/null; sleep 1; pkill -9 -f spotify_monitor.py 2>/dev/null; echo STEP1B_OK"

echo -e "\n[VM $VM_ID] 1c. Eliminando autostart .desktop del bot viejo..."
gexec 30 "for f in /home/localuser/.config/autostart/*.desktop; do [ -f \"\$f\" ] || continue; if grep -qE 'spotify_monitor|spotify_robot/|init_launcher_main|spotify_humandroid' \"\$f\"; then echo \"Eliminando: \$f\"; rm -f \"\$f\"; fi; done; echo STEP1C_OK"

echo -e "\n[VM $VM_ID] 1d. Limpiando crontab de localuser..."
gexec 30 "if crontab -u localuser -l 2>/dev/null | grep -qE 'spotify_robot|spotify_humandroid|init_launcher_main|spotify_monitor'; then crontab -u localuser -l 2>/dev/null | grep -vE 'spotify_robot|spotify_humandroid|init_launcher_main|spotify_monitor' | crontab -u localuser -; echo 'Crontab limpiado'; else echo 'Crontab sin entradas viejas'; fi; echo STEP1D_OK"

echo -e "\n[VM $VM_ID] 1e. Verificando que el bot viejo está muerto..."
gexec 15 "pgrep -af spotify_monitor.py || echo OLD_BOT_DEAD_OK"

# === FASE 2: PREPARAR REPO Y VENV ===

echo -e "\n[VM $VM_ID] 2a. Actualizando repositorio..."
gexec 60 "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR/.git ]; then cd $BOT_DIR && git pull origin main 2>&1 | tail -5; else git clone $REPO $BOT_DIR 2>&1 | tail -5; fi; echo STEP2A_OK"

echo -e "\n[VM $VM_ID] 2b. Instalando python3-venv si falta..."
gexec 120 "if ! dpkg -l python3-venv 2>/dev/null | grep -q '^ii'; then echo 'Instalando python3-venv...'; apt-get install -y python3-venv 2>&1 | tail -3; else echo 'python3-venv ya instalado'; fi; echo STEP2B_OK"

echo -e "\n[VM $VM_ID] 2c. Creando venv si no existe..."
gexec 120 "if [ ! -x $BOT_DIR/venv/bin/python3 ]; then echo 'Creando venv...'; rm -rf $BOT_DIR/venv; python3 -m venv $BOT_DIR/venv && echo VENV_CREATED_OK || echo VENV_CREATE_FAILED; else echo 'venv ya existe'; fi"

echo -e "\n[VM $VM_ID] 2d. Instalando dependencias del bot (requests + pyautogui)..."
gexec 300 "$BOT_DIR/venv/bin/pip install -q --upgrade pip 2>&1 | tail -3; $BOT_DIR/venv/bin/pip install -q requests pyautogui 2>&1 | tail -5; $BOT_DIR/venv/bin/python3 -c 'import pyautogui, requests; print(\"DEPS_OK\")' 2>&1 | tail -3"

echo -e "\n[VM $VM_ID] 2e. Permisos para localuser..."
gexec 60 "chown -R localuser:localuser $BOT_DIR && echo PERMS_OK"

# === FASE 3: CREAR SCRIPT DE PRE-ARRANQUE (copia xauth + xhost) ===

echo -e "\n[VM $VM_ID] 3a. Creando /usr/local/bin/yiyolmb-prestart.sh..."
gexec 30 "cat > /usr/local/bin/yiyolmb-prestart.sh << 'PRESTART_EOF'
#!/bin/bash
# Pre-arranque para yiyolmb.service: copia xauth de SDDM y abre X
XAUTH=\$(ls -t /run/sddm/xauth_* /tmp/xauth_* 2>/dev/null | head -1)
if [ -n \"\$XAUTH\" ] && [ -r \"\$XAUTH\" ]; then
    cp -f \"\$XAUTH\" /home/localuser/.Xauthority
    chown localuser:localuser /home/localuser/.Xauthority
    chmod 600 /home/localuser/.Xauthority
fi
xhost +localhost 2>/dev/null || true
exit 0
PRESTART_EOF
chmod +x /usr/local/bin/yiyolmb-prestart.sh && echo PRESTART_OK"

# === FASE 4: CREAR/RECREAR SERVICIO SYSTEMD ===

echo -e "\n[VM $VM_ID] 4a. Creando servicio systemd yiyolmb.service..."
gexec 30 "cat > /etc/systemd/system/yiyolmb.service << 'SERVICE_EOF'
[Unit]
Description=YiyoLMB Spotify Bot
After=network.target graphical.target
Wants=graphical.target

[Service]
Type=simple
User=localuser
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/localuser/.Xauthority
Environment=HOME=/home/localuser
WorkingDirectory=/home/localuser/nuevo_spotify_bot
PermissionsStartOnly=true
ExecStartPre=/usr/local/bin/yiyolmb-prestart.sh
ExecStart=/home/localuser/nuevo_spotify_bot/venv/bin/python3 /home/localuser/nuevo_spotify_bot/spotify_robot.py
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
SERVICE_EOF
systemctl daemon-reload && echo SERVICE_CREATED_OK"

echo -e "\n[VM $VM_ID] 4b. Habilitando e iniciando servicio..."
gexec 30 "systemctl unmask yiyolmb.service 2>/dev/null; systemctl enable yiyolmb.service 2>&1 | tail -3; systemctl restart yiyolmb.service && echo START_OK || echo START_FAILED"

# === FASE 5: VERIFICACIÓN ===

echo -e "\n[VM $VM_ID] 5a. Estado del servicio (después de 5s)..."
sleep 5
gexec 30 "systemctl status yiyolmb.service --no-pager | head -15"

echo -e "\n[VM $VM_ID] 5b. Procesos del bot NUEVO y VIEJO..."
gexec 15 "echo '--- Bot NUEVO (debe haber 1+) ---'; pgrep -af spotify_robot.py || echo 'NO HAY PROCESOS DEL BOT NUEVO'; echo '--- Bot VIEJO (debe ser 0) ---'; pgrep -af spotify_monitor.py || echo 'NO HAY PROCESOS DEL BOT VIEJO (OK)'"

echo -e "\n[VM $VM_ID] 5c. Últimas líneas del log del bot..."
gexec 15 "tail -20 $BOT_DIR/spotify_robot.log 2>/dev/null || echo 'Aún no hay log'"

echo -e "\n================================================"
echo " Despliegue en VM $VM_ID completado"
echo "================================================"
echo "Para ver logs en vivo:"
echo "  qm guest exec $VM_ID -- tail -f $BOT_DIR/spotify_robot.log"
echo "  qm guest exec $VM_ID -- journalctl -u yiyolmb.service -f"
