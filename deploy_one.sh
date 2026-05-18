#!/bin/bash
# Despliegue a UNA SOLA VM via qm guest exec (v7.1 + limpieza del bot viejo)
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

echo "================================================"
echo " Despliegue de PRUEBA a UNA VM (estilo v7.1)"
echo " VM ID: $VM_ID"
echo "================================================"

# Verificar que qm guest agent responde
echo -e "\n[VM $VM_ID] 0. Verificando QEMU guest agent..."
if ! qm guest exec $VM_ID -- /bin/bash -c "echo OK" 2>/dev/null | grep -q OK; then
    echo "[VM $VM_ID] ERROR: qm guest agent no responde. Abortando."
    exit 1
fi

# 1. Limpiar bot VIEJO (/home/localuser/spotify_robot) y servicios systemd anteriores
echo -e "\n[VM $VM_ID] 1. Limpiando bot VIEJO y servicios anteriores..."
qm guest exec --timeout 120 $VM_ID -- /bin/bash -c "
# Detener systemd anterior
systemctl stop yiyolmb.service 2>/dev/null
systemctl stop yiyobot.service 2>/dev/null
systemctl disable yiyolmb.service 2>/dev/null
systemctl disable yiyobot.service 2>/dev/null
systemctl unmask yiyolmb.service 2>/dev/null
systemctl unmask yiyobot.service 2>/dev/null
rm -f /etc/systemd/system/yiyolmb.service /etc/systemd/system/yiyobot.service
systemctl daemon-reload

# Detener bot VIEJO: terminal envoltorio (qterminal/xterm/gnome-terminal) que lanza el bot
pkill -f 'qterminal.*spotify_monitor' 2>/dev/null
pkill -f 'xterm.*spotify_monitor' 2>/dev/null
pkill -f 'terminal.*spotify_monitor' 2>/dev/null

# Detener bot VIEJO: procesos python desde la ruta /home/localuser/spotify_robot/
pkill -f '$OLD_BOT_DIR/' 2>/dev/null
pkill -f spotify_monitor.py 2>/dev/null
pkill -f spotify_app_control.py 2>/dev/null
pkill -f spotify_like.py 2>/dev/null
pkill -f favorite_playlist.py 2>/dev/null
pkill -f stats_human.py 2>/dev/null
pkill -f init_launcher_main.py 2>/dev/null

# Quitar autostart del bot viejo de LXQt: cualquier .desktop que mencione spotify_monitor
# o la ruta del bot viejo
sudo -u localuser bash -c '
    for f in /home/localuser/.config/autostart/*.desktop; do
        [ -f \"\$f\" ] || continue
        if grep -qE \"spotify_monitor|spotify_robot/|init_launcher_main|spotify_humandroid\" \"\$f\"; then
            echo \"Eliminando autostart viejo: \$f\"
            rm -f \"\$f\"
        fi
    done
' 2>/dev/null || true

# Quitar de cron de localuser si existe
sudo -u localuser bash -c 'crontab -l 2>/dev/null | grep -v \"spotify_robot\\|spotify_humandroid\\|init_launcher_main\\|spotify_monitor\" | crontab - 2>/dev/null' || true

# Detener bot NUEVO si ya estaba corriendo (para reinicio limpio)
pkill -f spotify_robot.py 2>/dev/null

sleep 2

# Forzar kill -9 si algo del viejo quedó vivo
pkill -9 -f '$OLD_BOT_DIR/' 2>/dev/null
pkill -9 -f spotify_monitor.py 2>/dev/null
pkill -9 -f 'qterminal.*spotify_monitor' 2>/dev/null

# Reportar lo que quedó
remaining=\$(pgrep -af '$OLD_BOT_DIR/\\|spotify_monitor\\|init_launcher_main' 2>/dev/null)
if [ -n \"\$remaining\" ]; then
    echo \"WARN: Aún corriendo:\"
    echo \"\$remaining\"
else
    echo \"OLD_BOT_KILLED_OK\"
fi
true
"

# 2. Actualizar el repositorio nuevo (puede tardar - creación de venv + pip install)
echo -e "\n[VM $VM_ID] 2. Actualizando repositorio nuevo (esto puede tardar 1-2 minutos)..."
qm guest exec --timeout 300 $VM_ID -- /bin/bash -c "
export HOME=/home/localuser
git config --global --add safe.directory $BOT_DIR
if [ -d $BOT_DIR ]; then
    cd $BOT_DIR && git pull origin main 2>&1
else
    git clone $REPO $BOT_DIR
fi

# Asegurar que python3-venv está instalado (lo necesita 'python3 -m venv')
if ! dpkg -l python3-venv 2>/dev/null | grep -q '^ii'; then
    echo 'Instalando python3-venv...'
    apt-get install -y python3-venv 2>&1 | tail -3
fi

# Crear venv si no existe (o si está corrupto y le falta python)
if [ ! -x $BOT_DIR/venv/bin/python3 ]; then
    echo 'Creando venv en $BOT_DIR/venv...'
    rm -rf $BOT_DIR/venv
    python3 -m venv $BOT_DIR/venv && echo 'VENV_CREATED_OK' || echo 'VENV_CREATE_FAILED'
fi

# Instalar dependencias (sin tragarse errores)
echo 'Instalando dependencias...'
$BOT_DIR/venv/bin/pip install -q --upgrade pip 2>&1 | tail -3
$BOT_DIR/venv/bin/pip install -q requests pyautogui 2>&1 | tail -5

# Verificar que el python del venv responde
if $BOT_DIR/venv/bin/python3 --version 2>/dev/null; then
    echo 'VENV_PYTHON_OK'
else
    echo 'VENV_PYTHON_FAIL'
fi

chown -R localuser:localuser $BOT_DIR
true
"

# 3. Crear servicio systemd (igual que v7.1)
echo -e "\n[VM $VM_ID] 3. Creando servicio systemd..."
qm guest exec $VM_ID -- /bin/bash -c "printf '[Unit]\\nDescription=YiyoLMB Spotify Bot\\nAfter=network.target\\n\\n[Service]\\nType=simple\\nUser=localuser\\nEnvironment=DISPLAY=:0\\nEnvironment=XAUTHORITY=/home/localuser/.Xauthority\\nEnvironment=HOME=/home/localuser\\nWorkingDirectory=/home/localuser/nuevo_spotify_bot\\nExecStartPre=/bin/bash -c xhost_+localhost\\nExecStart=/home/localuser/nuevo_spotify_bot/venv/bin/python3 /home/localuser/nuevo_spotify_bot/spotify_robot.py\\nRestart=on-failure\\nRestartSec=15\\n\\n[Install]\\nWantedBy=multi-user.target\\n' > /etc/systemd/system/yiyolmb.service && sed -i 's/xhost_+localhost/xhost +localhost 2>\/dev\/null || true/' /etc/systemd/system/yiyolmb.service && systemctl daemon-reload && echo SERVICE_OK"

# 4. Habilitar e iniciar el servicio
echo -e "\n[VM $VM_ID] 4. Habilitando e iniciando servicio..."
qm guest exec $VM_ID -- /bin/bash -c "systemctl unmask yiyolmb.service; systemctl enable yiyolmb.service; systemctl start yiyolmb.service && echo START_OK || echo START_FAILED"

# 5. Verificar estado del servicio
echo -e "\n[VM $VM_ID] 5. Verificando estado del servicio..."
qm guest exec $VM_ID -- /bin/bash -c "systemctl status yiyolmb.service --no-pager | head -20"

# 6. Verificar que el proceso del bot está corriendo
echo -e "\n[VM $VM_ID] 6. Verificando proceso del bot..."
sleep 3
qm guest exec --timeout 60 $VM_ID -- /bin/bash -c "
echo '--- Procesos del bot NUEVO ---'
pgrep -af spotify_robot.py || echo 'NO HAY PROCESOS DEL BOT NUEVO'
echo '--- Procesos del bot VIEJO (deberían ser 0) ---'
pgrep -af '$OLD_BOT_DIR/\\|init_launcher_main\\|spotify_monitor' || echo 'NO HAY PROCESOS DEL BOT VIEJO (OK)'
echo '--- Últimas líneas del log del bot ---'
tail -20 $BOT_DIR/spotify_robot.log 2>/dev/null || echo 'Aún no hay log'
"

echo -e "\n================================================"
echo " Despliegue en VM $VM_ID completado"
echo "================================================"
echo "Para ver logs en vivo:"
echo "  qm guest exec $VM_ID -- tail -f $BOT_DIR/spotify_robot.log"
echo "  qm guest exec $VM_ID -- journalctl -u yiyolmb.service -f"
