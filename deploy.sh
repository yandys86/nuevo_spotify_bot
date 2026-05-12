#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
VMS="118 119" 

echo "================================================"
echo "   YiyoLMB - Despliegue Total v5.1"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] 1. Actualizando código..."
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    echo "[VM $VM_ID] 2. Asegurando Librerías..."
    qm guest exec $VM_ID -- /bin/bash -c "cd $BOT_DIR; [ ! -d venv ] && python3 -m venv venv; ./venv/bin/python3 -m pip install --upgrade pip; ./venv/bin/python3 -m pip install pyautogui requests"

    echo "[VM $VM_ID] 3. Sincronizando Cuenta..."
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    echo "[VM $VM_ID] 4. Lanzando Bot..."
    qm guest exec $VM_ID -- /bin/bash -c "chown -R localuser:localuser $BOT_DIR; touch /home/localuser/.Xauthority; chown localuser:localuser /home/localuser/.Xauthority; pkill -f spotify_robot.py; sudo -u localuser bash -c 'export HOME=/home/localuser; export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &'"

    echo "[VM $VM_ID] 5. Programando Play (Fondo)..."
    # Usamos nohup también para el comando de Play para que no se corte
    qm guest exec $VM_ID -- /bin/bash -c "sudo -u localuser bash -c 'export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; cd $BOT_DIR; nohup ./venv/bin/python3 -c \"import pyautogui; import time; time.sleep(15); pyautogui.press(\\\"esc\\\"); time.sleep(2); pyautogui.click(600, 400); time.sleep(1); pyautogui.press(\\\"space\\\")\" > /dev/null 2>&1 &'"
    
    echo "[VM $VM_ID] ¡Configuración enviada!"
done
