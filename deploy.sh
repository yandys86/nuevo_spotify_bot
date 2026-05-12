#!/bin/bash
# Configuración para YiyoLMB
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# --- LISTA DE VMs A ACTIVAR ---
# Puedes añadir más aquí, separadas por espacio
VMS="114 115" 

echo "================================================"
echo "   YiyoLMB - Despliegue Total v2.0 (qm)"
echo "================================================"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] 1/4: Actualizando archivos..."
    # Configura Git para evitar errores de seguridad y baja el código
    qm guest exec $VM_ID -- /bin/bash -c "git config --global --add safe.directory $BOT_DIR; if [ -d $BOT_DIR ]; then cd $BOT_DIR && git pull; else git clone $REPO $BOT_DIR; fi"

    echo "[VM $VM_ID] 2/4: Sincronizando configuración..."
    # Copia el account.ini desde la 111 (La Maestra)
    qm guest exec 111 -- cat $BOT_DIR/account.ini > /tmp/acc_temp.ini
    qm guest exec $VM_ID -- /bin/bash -c "cat > $BOT_DIR/account.ini" < /tmp/acc_temp.ini

    echo "[VM $VM_ID] 3/4: Reparando permisos de pantalla..."
    # Crea la llave de acceso a la pantalla y asegura que localuser sea el dueño
    qm guest exec $VM_ID -- /bin/bash -c "chown -R localuser:localuser $BOT_DIR; touch /home/localuser/.Xauthority; chown localuser:localuser /home/localuser/.Xauthority"

    echo "[VM $VM_ID] 4/4: Lanzando Bot y dando Play..."
    # Detiene bots viejos y lanza el nuevo
    qm guest exec $VM_ID -- /bin/bash -c "pkill -f spotify_robot.py; sudo -u localuser bash -c 'export HOME=/home/localuser; export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; xhost +localhost; cd $BOT_DIR; nohup ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &'"
    
    # Espera a que Spotify cargue y fuerza el Play
    echo "[VM $VM_ID] Forzando inicio de reproducción..."
    sleep 5
    qm guest exec $VM_ID -- /bin/bash -c "sudo -u localuser bash -c 'export DISPLAY=:0; export XAUTHORITY=/home/localuser/.Xauthority; cd $BOT_DIR; sleep 10; ./venv/bin/python3 -c \"import pyautogui; pyautogui.press(\\\"esc\\\"); sleep(1); pyautogui.click(x=pyautogui.size().width//2, y=pyautogui.size().height//2); sleep(1); pyautogui.press(\\\"space\\\")\"'"
    
    echo "[VM $VM_ID] ¡Proceso completado!"
done

echo -e "\n================================================"
echo "   Todas las máquinas han sido procesadas."
echo "================================================"
