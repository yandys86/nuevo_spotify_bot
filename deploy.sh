#!/bin/bash
# Configuración YiyoLMB v6.9 - BYPASS TOTAL MASK
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"
VMS="117 118" 

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] 1. Limpieza de nombres viejos..."
    # Eliminamos el servicio viejo que está bloqueado y matamos procesos
    qm guest exec $VM_ID -- /bin/bash -c "systemctl stop yiyobot.service 2>/dev/null; systemctl disable yiyobot.service 2>/dev/null; rm -f /etc/systemd/system/yiyobot.service; pkill -f spotify; pkill -f python"

    echo "[VM $VM_ID] 2. Instalando versión limpia..."
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; cd $BOT_DIR && git reset --hard origin/main && git pull"

    # 3. Nuevo Lanzador
    START_SCRIPT="#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/localuser/.Xauthority
xhost +localhost
pgrep -x spotify > /dev/null || (spotify &)
sleep 20
cd $BOT_DIR
./venv/bin/python3 spotify_robot.py"

    echo "$START_SCRIPT" > /tmp/run_yiyo.sh
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/run_yiyo.sh && chmod +x $BOT_DIR/run_yiyo.sh"

    echo "[VM $VM_ID] 4. Creando NUEVO servicio (yiyolmb.service)..."
    SERVICE_FILE="[Unit]
Description=YiyoLMB Oficial
After=graphical.target
[Service]
User=localuser
Environment=DISPLAY=:0
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/run_yiyo.sh
Restart=always
RestartSec=20
[Install]
WantedBy=graphical.target"

    echo "$SERVICE_FILE" > /tmp/yiyolmb.service
    qm guest exec $VM_ID -- /bin/bash -c "cat > /etc/systemd/system/yiyolmb.service; systemctl daemon-reload; systemctl enable yiyolmb.service; systemctl restart yiyolmb.service"
    
    echo "[VM $VM_ID] ¡Cambio de nombre completado!"
done
