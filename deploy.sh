#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
VMS="112 113" 

echo "================================================"
echo "   YiyoLMB - Despliegue vía Proxmox (qm)"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] Iniciando configuración..."

    # 1. Actualizar código
    qm guest exec $VM_ID -- /bin/bash -c "if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    # 2. Entorno y Librerías
    qm guest exec $VM_ID -- /bin/bash -c "cd $BOT_DIR && [ ! -d venv ] && python3 -m venv venv; ./venv/bin/pip install -q pyautogui requests"

    # 3. Sincronizar cuenta desde la 111
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    # 4. Permisos y Arranque
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify_robot.py; chown -R localuser:localuser $BOT_DIR && sudo -u localuser bash -c 'export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &'"

    echo "[VM $VM_ID] ¡Bot lanzado con éxito!"
done
