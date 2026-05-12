#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
VMS="114 115" 

echo "================================================"
echo "   YiyoLMB - Despliegue Total (qm)"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] Configurando..."

    # 1. Preparar Git y Clonar/Actualizar
    qm guest exec $VM_ID -- /bin/bash -c "git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    # 2. Asegurar Entorno Virtual (VENV) y Librerías
    qm guest exec $VM_ID -- /bin/bash -c "cd $BOT_DIR; [ ! -d venv ] && python3 -m venv venv; ./venv/bin/pip install -q pyautogui requests"

    # 3. Sincronizar cuenta desde la 111
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    # 4. Permisos de pantalla y arranque limpio
    qm guest exec $VM_ID -- /bin/bash -c "chown -R localuser:localuser $BOT_DIR; touch /home/localuser/.Xauthority; chown localuser:localuser /home/localuser/.Xauthority"

    # 5. Lanzar Bot y forzar Play (separado para evitar cortes)
    echo "[VM $VM_ID] Lanzando bot..."
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify_robot.py; sudo -u localuser bash -c 'export HOME=/home/localuser; export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &'"
    
    sleep 2 # Respiro para el sistema
    
    echo "[VM $VM_ID] Forzando Play..."
    qm guest exec $VM_ID -- /bin/bash -c "sudo -u localuser bash -c 'export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; cd $BOT_DIR; sleep 10; ./venv/bin/python3 -c \"import pyautogui; pyautogui.click(600, 400); pyautogui.press(\\\"space\\\")\"'"
done
