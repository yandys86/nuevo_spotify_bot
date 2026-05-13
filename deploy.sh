#!/bin/bash
# Configuración para YiyoLMB v6.5 - Auto-Arranque y Persistencia
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs ---
VMS="117 118" 

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] 1. Limpieza y Desbloqueo..."
    # Quitamos bloqueos de servicios previos y matamos procesos colgados
    qm guest exec $VM_ID -- /bin/bash -c "systemctl unmask yiyobot.service; systemctl stop yiyobot.service 2>/dev/null; pkill -f spotify; pkill -f python"

    echo "[VM $VM_ID] 2. Actualizando Código..."
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; [ -d $BOT_DIR ] && cd $BOT_DIR && git pull || git clone $REPO $BOT_DIR"
    
    # Sincronizar cuenta desde la 111
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    echo "[VM $VM_ID] 3. Configurando Script de Arranque..."
    # Este script abre Spotify, espera y lanza el bot
    START_SCRIPT="#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/localuser/.Xauthority
xhost +localhost
# Abrir Spotify si no está corriendo
pgrep -x spotify > /dev/null || (spotify &)
sleep 15
cd $BOT_DIR
./venv/bin/python3 spotify_robot.py"

    echo "$START_SCRIPT" > /tmp/run_yiyo.sh
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/run_yiyo.sh && chmod +x $BOT_DIR/run_yiyo.sh"

    echo "[VM $VM_ID] 4. Instalando Servicio de Persistencia..."
    SERVICE_FILE="[Unit]
Description=Spotify Bot YiyoLMB
After=graphical.target

[Service]
Type=simple
User=localuser
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/localuser/.Xauthority
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/run_yiyo.sh
Restart=always
RestartSec=20

[Install]
WantedBy=graphical.target"

    echo "$SERVICE_FILE" > /tmp/yiyobot.service
    qm guest exec $VM_ID -- /bin/bash -c "cat > /etc/systemd/system/yiyobot.service" < /tmp/yiyobot.service
    
    # Activar todo
    qm guest exec $VM_ID -- /bin/bash -c "systemctl daemon-reload; systemctl enable yiyobot.service; systemctl restart yiyobot.service"

    echo "[VM $VM_ID] ¡Listo! Autogestionado y persistente."
done
