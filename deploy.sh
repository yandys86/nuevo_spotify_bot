#!/bin/bash
# Despliegue MASIVO a múltiples VMs
# Llama a deploy_one.sh en bucle para cada VM_ID configurada
# Edita la variable VMS abajo con la lista de VMs que quieres actualizar

set -u

# Lista de VM_IDs a actualizar (separados por espacio)
VMS="120"

# Verificar que deploy_one.sh existe y es ejecutable
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_ONE="$SCRIPT_DIR/deploy_one.sh"
if [ ! -x "$DEPLOY_ONE" ]; then
    echo "ERROR: $DEPLOY_ONE no existe o no es ejecutable"
    echo "Ejecuta: chmod +x $DEPLOY_ONE"
    exit 1
fi

echo "################################################"
echo " DESPLIEGUE MASIVO"
echo " VMs: $VMS"
echo "################################################"

TOTAL=0
OK_COUNT=0
FAIL_COUNT=0
FAILED_VMS=""

for VM_ID in $VMS; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "################################################"
    echo " [$TOTAL] Procesando VM $VM_ID"
    echo "################################################"
    if "$DEPLOY_ONE" "$VM_ID"; then
        OK_COUNT=$((OK_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_VMS="$FAILED_VMS $VM_ID"
    fi
done

echo ""
echo "################################################"
echo " RESUMEN FINAL"
echo "################################################"
echo " Total VMs procesadas: $TOTAL"
echo " Exitosas: $OK_COUNT"
echo " Fallidas: $FAIL_COUNT"
if [ -n "$FAILED_VMS" ]; then
    echo " VMs con error:$FAILED_VMS"
fi
echo "################################################"
