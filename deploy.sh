#!/bin/bash

# Configuración
REPO="https://github.com/yandys86/nuevo_spotify_bot.git"
USER="localuser"
BOT_DIR="/home/localuser/nuevo_spotify_bot"

# Rango de IPs
IP_BASE="192.168.65"
IP_START=30
IP_END=55

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo " Spotify Bot - Despliegue automático"
echo " VMs: $IP_BASE.$IP_START - $IP_BASE.$IP_END"
echo "================================================"

# Instalar dependencias necesarias en Proxmox
for pkg in sshpass expect; do
    if ! command -v $pkg &> /dev/null; then
        echo -e "${YELLOW}Instalando $pkg...${NC}"
        apt-get install -y $pkg > /dev/null 2>&1
    fi
done

# Generar clave SSH si no existe
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generando clave SSH en Proxmox..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N "" -q
fi

SUCCESS=0
FAILED=0
SKIPPED=0

for i in $(seq $IP_START $IP_END); do
    IP="$IP_BASE.$i"

    # Verificar si la VM responde al ping
    if ! ping -c 1 -W 2 "$IP" > /dev/null 2>&1; then
        echo -e "${YELLOW}[$IP] Sin respuesta, saltando...${NC}"
        ((SKIPPED++))
        continue
    fi

    echo -e "\n${GREEN}[$IP] Conectando...${NC}"

    # Copiar clave SSH a la VM (contraseña vacía)
    sshpass -p "" ssh-copy-id \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o PasswordAuthentication=yes \
        "$USER@$IP" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        # Intentar con expect si sshpass falla
        expect -c "
            spawn ssh-copy-id -o StrictHostKeyChecking=no $USER@$IP
            expect {
                \"password:\" { send \"\r\"; exp_continue }
                eof
            }
        " > /dev/null 2>&1
    fi

    # Desplegar el bot via SSH con key
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "$USER@$IP" bash << EOF
set -e

# Clonar o actualizar repositorio
if [ -d "$BOT_DIR" ]; then
    echo "[$IP] Actualizando repositorio..."
    cd "$BOT_DIR" && git pull -q
else
    echo "[$IP] Clonando repositorio..."
    git clone -q "$REPO" "$BOT_DIR"
fi

cd "$BOT_DIR"

# Crear entorno virtual si no existe
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

# Instalar dependencias
source venv/bin/activate
pip install -q pyautogui requests

# Detener bot anterior si está corriendo
pkill -f spotify_robot.py 2>/dev/null || true
sleep 1

# Iniciar bot en segundo plano
# --- BLOQUE ACTUALIZADO ---
    
    # 1. Asegurar que localuser sea dueño de su carpeta y logs
    sudo chown -R localuser:localuser "$BOT_DIR"
    
    # 2. Configurar acceso a la pantalla (evita el error de Xauthority)
    export DISPLAY=:0
    export XAUTHORITY=/home/localuser/.Xauthority
    touch $XAUTHORITY
    sudo chown localuser:localuser $XAUTHORITY
    
    # 3. Dar permiso explícito para que el bot "vea" el escritorio
    xhost +localhost > /dev/null 2>&1 || true

    # 4. Iniciar bot entrando a la carpeta para que el log NO se cree en la raíz
    echo "[$IP] Lanzando bot..."
    cd "$BOT_DIR"
    nohup sudo -u localuser DISPLAY=:0 XAUTHORITY=/home/localuser/.Xauthority ./venv/bin/python3 spotify_robot.py > nohup.log 2>&1 &
    
    echo "[$IP] Bot iniciado correctamente con PID \$!"
EOF
done

echo ""
echo "================================================"
echo " Resumen"
echo "================================================"
echo -e " ${GREEN}Exitosos: $SUCCESS${NC}"
echo -e " ${RED}Fallidos: $FAILED${NC}"
echo -e " ${YELLOW}Saltados: $SKIPPED${NC}"
echo "================================================"
