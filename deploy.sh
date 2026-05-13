#!/bin/bash
# Configuracion YiyoLMB v7.1 - SCRIPT CORREGIDO (printf sin heredoc)
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"
VMS="117 118"

for VM_ID in $VMS; do
    echo -e "\n[VM $VM_ID] === Iniciando deploy ==="

    # 1. Limpiar servicios viejos con unmask primero
    echo "[VM $VM_ID] 1. Limpiando servicios anteriores..."
    qm guest exec $VM_ID -- /bin/bash -c "systemctl stop yiyolmb.service 2>/dev/null; systemctl stop yiyobot.service 2>/dev/null; systemctl disable yiyolmb.service 2>/dev/null; systemctl disable yiyobot.service 2>/dev/null; systemctl unmask yiyolmb.service 2>/dev/null; systemctl unmask yiyobot.service 2>/dev/null; rm -f /etc/systemd/system/yiyolmb.service /etc/systemd/system/yiyobot.service; systemctl daemon-reload; pkill -f spotify_robot.py 2>/dev/null; true"

    # 2. Actualizar el repositorio
    echo "[VM $VM_ID] 2. Actualizando repositorio..."
    qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; cd $BOT_DIR && git pull origin main 2>&1 || git clone $REPO $BOT_DIR; $BOT_DIR/venv/bin/pip install -r $BOT_DIR/requirements.txt -q 2>/dev/null; chown -R localuser:localuser $BOT_DIR; true"

    # 3. Crear el archivo .service con printf (sin heredoc para evitar problemas con comillas)
    echo "[VM $VM_ID] 3. Creando servicio systemd..."
    qm guest exec $VM_ID -- /bin/bash -c "printf '[Unit]\\nDescription=YiyoLMB Spotify Bot\\nAfter=network.target\\n\\n[Service]\\nType=simple\\nUser=localuser\\nEnvironment=DISPLAY=:0\\nEnvironment=XAUTHORITY=/home/localuser/.Xauthority\\nEnvironment=HOME=/home/localuser\\nWorkingDirectory=/home/localuser/nuevo_spotify_bot\\nExecStartPre=/bin/bash -c xhost_+localhost\\nExecStart=/home/localuser/nuevo_spotify_bot/venv/bin/python3 /home/localuser/nuevo_spotify_bot/spotify_robot.py\\nRestart=on-failure\\nRestartSec=15\\n\\n[Install]\\nWantedBy=multi-user.target\\n' > /etc/systemd/system/yiyolmb.service && sed -i 's/xhost_+localhost/xhost +localhost 2>\/dev\/null || true/' /etc/systemd/system/yiyolmb.service && systemctl daemon-reload && echo SERVICE_OK"

    # 4. Habilitar e iniciar el servicio
    echo "[VM $VM_ID] 4. Habilitando e iniciando servicio..."
    qm guest exec $VM_ID -- /bin/bash -c "systemctl unmask yiyolmb.service; systemctl enable yiyolmb.service; systemctl start yiyolmb.service && echo START_OK || echo START_FAILED"

    # 5. Verificar estado
    echo "[VM $VM_ID] 5. Verificando estado..."
    qm guest exec $VM_ID -- /bin/bash -c "systemctl status yiyolmb.service --no-pager | head -20"

    echo "[VM $VM_ID] === Deploy completado ==="
done

echo -e "\nDeploy finalizado para todas las VMs: $VMS"
