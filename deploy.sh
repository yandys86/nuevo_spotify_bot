#!/bin/bash
# Configuración para YiyoLMB v6.1 - Persistencia y Auto-Arranque de App
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs ---
VMS="117 118" 

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] Configurando persistencia total..."

    # 1. Limpieza de procesos viejos y actualización
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify; pkill -f python; export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; [ -d $BOT_DIR ] && cd $BOT_DIR && git pull || git clone $REPO $BOT_DIR"

    # 2. Asegurar entorno y cuenta
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    # 3. CREAR EL SCRIPT DE ARRANQUE (wrapper)
    # Este pequeño script asegura que Spotify se abra antes que el bot
    START_SCRIPT="#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/localuser/.Xauthority
xhost +localhost
# Abrir Spotify si no está abierto
pgrep -x spotify > /dev/null || (spotify &)
sleep 15
# Lanzar el bot
cd $BOT_DIR
./venv/bin/python3 spotify_robot.py"

    echo "$START_SCRIPT" > /tmp/run_yiyo.sh
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/run_yiyo.sh && chmod +x $BOT_DIR/run_yiyo.sh"

    # 4. CREAR EL SERVICIO DEL SISTEMA
    SERVICE_FILE="[Unit]
Description=Spotify Bot YiyoLMB Service
After=graphical.target

[Service]
Type=simple
User=localuser
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/localuser/.Xauthority
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/run_yiyo.sh
Restart=always
RestartSec=15

[Install]
WantedBy=graphical.target"

    echo "$SERVICE_FILE" > /tmp/yiyobot.service
    qm guest exec $VM_ID -- /bin/bash -c "cat > /etc/systemd/system/yiyobot.service" < /tmp/yiyobot.service
    
    # 5. Activar y arrancar
    qm guest exec $VM_ID -- /bin/bash -c "systemctl daemon-reload; systemctl enable yiyobot.service; systemctl restart yiyobot.service"

    echo "[VM $VM_ID] ¡Instalado! Spotify y el Bot iniciarán automáticamente."
done
