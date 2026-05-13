#!/bin/bash
# Configuracion YiyoLMB v7.0 - SCRIPT CORREGIDO
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
BOT_DIR="/home/localuser/nuevo_spotify_bot"
VMS="117 118"

for VM_ID in $VMS; do
   echo -e "\n[VM $VM_ID] === Iniciando deploy ==="

        # 1. Limpiar servicios viejos con unmask primero
            echo "[VM $VM_ID] 1. Limpiando servicios anteriores..."
                qm guest exec $VM_ID -- /bin/bash -c "systemctl stop yiyolmb.service 2>/dev/null; systemctl stop yiyobot.service 2>/dev/null; systemctl disable yiyolmb.service 2>/dev/null; systemctl disable yiyobot.service 2>/dev/null; systemctl unmask yiyolmb.service 2>/dev/null; systemctl unmask yiyobot.service 2>/dev/null; rm -f /etc/systemd/system/yiyolmb.service; rm -f /etc/systemd/system/yiyobot.service; systemctl daemon-reload; pkill -f spotify_robot.py 2>/dev/null; true"

                    # 2. Actualizar el repositorio
                        echo "[VM $VM_ID] 2. Actualizando repositorio..."
                            qm guest exec $VM_ID -- /bin/bash -c "export HOME=/home/localuser; git config --global --add safe.directory $BOT_DIR; cd $BOT_DIR && git pull origin main 2>&1 || (git clone $REPO $BOT_DIR && cd $BOT_DIR); cd $BOT_DIR && python3 -m venv venv 2>/dev/null; $BOT_DIR/venv/bin/pip install -r $BOT_DIR/requirements.txt -q 2>/dev/null; chown -R localuser:localuser $BOT_DIR"

                                # 3. Crear el archivo .service correctamente dentro de la VM
                                    echo "[VM $VM_ID] 3. Creando servicio systemd..."
                                        qm guest exec $VM_ID -- /bin/bash -c "cat > /etc/systemd/system/yiyolmb.service << 'EOF'
                                        [Unit]
                                        Description=YiyoLMB Spotify Bot
                                        After=network.target graphical-session.target
                                        Wants=graphical-session.target

                                        [Service]
                                        Type=simple
                                        User=localuser
                                        Environment=DISPLAY=:0
                                        Environment=XAUTHORITY=/home/localuser/.Xauthority
                                        Environment=HOME=/home/localuser
                                        WorkingDirectory=/home/localuser/nuevo_spotify_bot
                                        ExecStartPre=/bin/bash -c 'xhost +localhost 2>/dev/null; pgrep -x spotify > /dev/null || (spotify &); sleep 20'
                                        ExecStart=/home/localuser/nuevo_spotify_bot/venv/bin/python3 /home/localuser/nuevo_spotify_bot/spotify_robot.py
                                        Restart=on-failure
                                        RestartSec=10

                                        [Install]
                                        WantedBy=graphical-session.target
                                        EOF
                                        systemctl daemon-reload"

                                            # 4. Habilitar e iniciar el servicio
                                                echo "[VM $VM_ID] 4. Habilitando e iniciando servicio..."
                                                    qm guest exec $VM_ID -- /bin/bash -c "systemctl unmask yiyolmb.service; systemctl enable yiyolmb.service; systemctl start yiyolmb.service"

                                                        # 5. Verificar estado
                                                            echo "[VM $VM_ID] 5. Verificando estado..."
                                                                qm guest exec $VM_ID -- systemctl status yiyolmb.service

                                                                    echo "[VM $VM_ID] === Deploy completado ==="
                                                                    done

                                                                    echo -e "\nDeploy finalizado para todas las VMs: $VMS"
