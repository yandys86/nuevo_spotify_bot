#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
VMS="116 117" 

echo "================================================"
echo "   YiyoLMB - Despliegue Total v4.0 (Oficial)"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] Configurando entorno..."

    # 1. Reparar Git y actualizar código
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    # 2. ASEGURAR VENV (Si no existe, se crea)
    echo "[VM $VM_ID] Verificando Python Venv..."
    qm guest exec $VM_ID -- /bin/bash -c "cd $BOT_DIR; [ ! -d venv ] && python3 -m venv venv; ./venv/bin/pip install pyautogui requests"

    # 3. Sincronizar cuenta desde la 111
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    # 4. Permisos de pantalla y arranque del Bot
    qm guest exec $VM_ID -- /bin/bash -c "chown -R localuser:localuser $BOT_DIR; touch /home/localuser/.Xauthority; chown localuser:localuser /home/localuser/.Xauthority; pkill -f spotify_robot.py; sudo -u localuser bash -c 'export HOME=/home/localuser; export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &'"

    # 5. Forzar Play (Con espera para carga de Spotify)
    echo "[VM $VM_ID] Forzando inicio de música..."
    sleep 3
    qm guest exec $VM_ID -- /bin/bash -c "sudo -u localuser bash -c 'export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; cd $BOT_DIR; ./venv/bin/python3 -c \"import pyautogui; import time; time.sleep(15); pyautogui.press(\\\"esc\\\"); time.sleep(2); pyautogui.click(600, 400); time.sleep(1); pyautogui.press(\\\"space\\\")\" &'"
    
    echo "[VM $VM_ID] Completado."
done
