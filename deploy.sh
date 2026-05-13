#!/bin/bash
# Configuración YiyoLMB v6.8 - LIMPIEZA TOTAL Y PERSISTENCIA
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"
VMS="117 118" 

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] 1. Borrando rastro de scripts viejos..."
    # 1. Matar procesos, borrar crontab y eliminar archivos de arranque viejos conocidos
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify; pkill -f python; crontab -r 2>/dev/null; rm -f /home/localuser/start_bot.sh; rm -f /home/localuser/auto_run.sh"

    # 2. Desbloquear servicios de sistema
    qm guest exec $VM_ID -- /bin/bash -c "systemctl stop yiyobot.service 2>/dev/null; systemctl disable yiyobot.service 2>/dev/null; rm -f /etc/systemd/system/yiyobot.service; systemctl unmask yiyobot.service"
    
    echo "[VM $VM_ID] 2. Instalando versión limpia de YiyoLMB..."
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; cd $BOT_DIR && git reset --hard origin/main && git pull"

    # 3. Nuevo Lanzador (Solo lo que queremos ahora)
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

    # 4. Crear el servicio de persistencia nuevo
    SERVICE_FILE="[Unit]
Description=YiyoLMB Bot Oficial
After=graphical.target
[Service]
User=localuser
Environment=DISPLAY=:0
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/run_yiyo.sh
Restart=always
RestartSec=30
[Install]
WantedBy=graphical.target"

    echo "$SERVICE_FILE" > /tmp/yiyobot.service
    qm guest exec $VM_ID -- /bin/bash -c "cat > /etc/systemd/system/yiyobot.service; systemctl daemon-reload; systemctl enable yiyobot.service; systemctl restart yiyobot.service"
    
    echo "[VM $VM_ID] ¡Limpieza completa y bot nuevo activo!"
done
