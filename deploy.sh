#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
# Aquí puedes ir sumando: 112 113 114 115...
VMS="114 115" 

echo "================================================"
echo "   YiyoLMB - Despliegue Automatizado (qm)"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] Iniciando configuración..."

    # 1. Actualizar código y asegurar permisos de Git
    qm guest exec $VM_ID -- /bin/bash -c "git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    # 2. Sincronizar cuenta desde la VM 111
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    # 3. Preparar entorno, crear llave .Xauthority y dar acceso a pantalla
    echo "[VM $VM_ID] Configurando acceso a pantalla..."
    qm guest exec $VM_ID -- /bin/bash -c "chown -R localuser:localuser $BOT_DIR; touch /home/localuser/.Xauthority; chown localuser:localuser /home/localuser/.Xauthority"

    # 4. Lanzar el bot con el comando de "Fuerza Bruta" para el Play
    echo "[VM $VM_ID] Lanzando bot y forzando Play..."
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify_robot.py; sudo -u localuser bash -c 'export HOME=/home/localuser; export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 & sleep 10; ./venv/bin/python3 -c \"import pyautogui; pyautogui.click(600, 400); pyautogui.press(\\\"space\\\")\" &'"

    echo "[VM $VM_ID] ¡Bot configurado y sonando!"
done
