# nuevo_spotify_bot

Bot automatizado que reproduce playlists de Spotify y da "like" automáticamente a las canciones, diseñado para correr en VMs Linux (Lubuntu/LXQt) administradas por Proxmox.

## ¿Qué hace el bot?

1. **Lanza Spotify** si no está abierto (`subprocess.Popen(['spotify'])`)
2. **Abre playlist** vía D-Bus MPRIS (`org.mpris.MediaPlayer2.Player.OpenUri`)
3. **Manda Play** vía D-Bus si Spotify está pausado
4. **Detecta canciones** vía `playerctl` o `dbus-send` (PlaybackStatus + Metadata)
5. **Da Like** usando `pyautogui.locateOnScreen()` con imagen de referencia del corazón
6. **Salta a la siguiente playlist** automáticamente cuando termina (>90s sin reproducir)
7. **Notifica por Telegram** (opcional) cambios de canción, likes, cambios de playlist

## Archivos del proyecto

| Archivo | Descripción |
|---------|-------------|
| `spotify_robot.py` | Script principal del bot (Python) |
| `global_config.ini` | Configuración: playlists, Telegram, horarios, coordenadas |
| `deploy_one.sh` | Despliega/actualiza el bot en UNA VM (por ID) |
| `deploy.sh` | Despliega a TODAS las VMs configuradas en la variable `VMS` |
| `autostart_bot.sh` | Script de arranque alternativo vía LXQt autostart (no usado por defecto) |
| `autostart/spotify-bot-autostart.desktop` | Entry .desktop de LXQt (no usado por defecto) |
| `images/Click_Like.png` | Imagen del icono de corazón para `pyautogui.locateOnScreen()` |

## Arquitectura

```
Proxmox host
   │
   │ qm guest exec (ejecuta como root dentro de la VM)
   ▼
VM (Lubuntu LXQt con autologin SDDM)
   │
   ├─ /etc/systemd/system/yiyolmb.service
   │     ├─ ExecStartPre=/usr/local/bin/yiyolmb-prestart.sh
   │     │     ├─ Copia /run/sddm/xauth_* o /tmp/xauth_* a ~/.Xauthority
   │     │     └─ xhost +localhost
   │     └─ ExecStart=python3 spotify_robot.py
   │
   ├─ User=localuser
   ├─ Environment=DISPLAY=:0
   ├─ Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus  ← CLAVE
   ├─ WantedBy=graphical.target  ← arranca al boot tras SDDM
   ├─ Restart=on-failure + StartLimitIntervalSec=0  ← reintenta siempre
   │
   └─ /home/localuser/nuevo_spotify_bot/
         ├─ venv/  (Python 3.12, requests, pyautogui, opencv-python, pillow)
         ├─ spotify_robot.py
         ├─ images/Click_Like.png
         └─ spotify_robot.log
```

## Despliegue

### Pre-requisitos en el host Proxmox

- El repo clonado en `/root/nuevo_spotify_bot/`
- Acceso root al host Proxmox
- `qemu-guest-agent` instalado y corriendo en las VMs (necesario para `qm guest exec`)
- Las VMs deben tener autologin SDDM activo (para que `graphical.target` se alcance)

### Despliegue a una sola VM

```bash
cd /root/nuevo_spotify_bot
git pull
./deploy_one.sh <VM_ID>      # ej: ./deploy_one.sh 109
```

El script ejecuta paso a paso (todos imprimen un marker `_OK` cuando completan):

| Paso | Qué hace |
|------|----------|
| 0    | Verifica que `qm agent <VM_ID> ping` responde |
| 1a   | Detiene/desinstala servicios systemd anteriores (yiyolmb, yiyobot) |
| 1b   | Mata bot VIEJO (`spotify_monitor.py`, `qterminal` envoltorio, etc.) |
| 1c   | Elimina `.desktop` de autostart del bot viejo (busca por contenido) |
| 1d   | Limpia `crontab -u localuser` de entradas del bot viejo |
| 1e   | Verifica que no quedó proceso viejo vivo |
| 2a   | `git pull` del repo nuevo o `git clone` si no existe |
| 2b   | `apt install python3-venv gnome-screenshot` |
| 2c   | Crea `venv` si no existe |
| 2d   | `pip install requests pyautogui pillow opencv-python` |
| 2e   | `chown -R localuser:localuser /home/localuser/nuevo_spotify_bot` |
| 3a   | Crea `/usr/local/bin/yiyolmb-prestart.sh` (copia xauth + xhost) |
| 4a   | Crea `/etc/systemd/system/yiyolmb.service` |
| 4b   | `disable + enable` (limpia symlinks viejos) + `restart` |
| 5a   | Muestra `systemctl status yiyolmb.service` |
| 5b   | Confirma proceso del bot nuevo + ausencia del viejo |
| 5c   | Muestra últimas 20 líneas del log del bot |

### Despliegue a múltiples VMs

Edita `deploy.sh`:
```bash
VMS="109 110 117 118 120"   # IDs separados por espacio
```

Luego:
```bash
cd /root/nuevo_spotify_bot
git pull
./deploy.sh
```

Es un loop que llama `deploy_one.sh` por cada VM. Al final imprime resumen: exitosos / fallidos.

## Configuración

### `global_config.ini`

```ini
[Play_Lists]
spotify_playlist_ids = ID1,ID2,ID3   # IDs separados por coma

[scheduled_time]
scheduled = no                       # 'yes' = solo correr en horas específicas
scheduled_hours = 11:15,17:11        # horas de inicio (formato 24h)
shuffle = no                         # 'yes' = mezclar orden de playlists

[telegram]
send_msg = yes                       # 'yes' = mandar notificaciones
chat_ids = 699683569,828562504       # chat IDs (varios separados por coma)

[SETTINGS]
log_level = INFO                     # DEBUG / INFO / WARNING / ERROR
heart_x = 451                        # coordenada X del corazón (FALLBACK si imagen no matchea)
heart_y = 645                        # coordenada Y del corazón (FALLBACK)
```

**Token de Telegram**: debe estar en la variable de entorno `TELEGRAM_TOKEN` en `~/.profile` del localuser (no se almacena en el repo).

### Cambiar las playlists

1. Edita `global_config.ini` (campo `spotify_playlist_ids`)
2. `git add global_config.ini && git commit -m "Actualizar playlists" && git push`
3. En cada VM, basta con `systemctl restart yiyolmb.service` después de un `git pull` (no hace falta re-deploy completo)

O re-despliega normal con `./deploy_one.sh <VM_ID>` (también funciona).

### Rotación automática de playlists

El bot rota así:
- Reproduce playlist 1 hasta que termina (Spotify sin reproducir por **>90 segundos**)
- Cambia a playlist 2 vía D-Bus `OpenUri`
- ... y así sucesivamente
- Cuando termina la última, vuelve a la primera (loop infinito vía módulo)

## Operación día a día

### Ver logs del bot

```bash
qm guest exec <VM_ID> -- tail -f /home/localuser/nuevo_spotify_bot/spotify_robot.log
qm guest exec <VM_ID> -- journalctl -u yiyolmb.service -f
```

### Estado del servicio

```bash
qm guest exec <VM_ID> -- systemctl status yiyolmb.service --no-pager | head -15
qm guest exec <VM_ID> -- systemctl is-active yiyolmb.service
```

### Reiniciar el bot en una VM

```bash
qm guest exec <VM_ID> -- systemctl restart yiyolmb.service
```

### Detener el bot

```bash
qm guest exec <VM_ID> -- systemctl stop yiyolmb.service
```

### Actualizar la playlists sin redeploy completo

```bash
qm guest exec <VM_ID> -- /bin/bash -c "cd /home/localuser/nuevo_spotify_bot && git -c safe.directory=/home/localuser/nuevo_spotify_bot pull && systemctl restart yiyolmb.service"
```

### Ver canción actual

```bash
qm guest exec <VM_ID> -- /bin/bash -c "runuser -l localuser -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus playerctl -p spotify metadata --format \"{{artist}} - {{title}}\"'"
```

### Saltar a siguiente canción manualmente

```bash
qm guest exec <VM_ID> -- /bin/bash -c "runuser -l localuser -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus playerctl -p spotify next'"
```

### Ver la consola gráfica de la VM

Abre <https://192.168.1.65:8006/> → VM `<VM_ID>` → pestaña **Console**. Vas a ver la sesión LXQt con Spotify en pantalla.

## Troubleshooting

### El bot no arranca después de un reboot

1. Verifica agent: `qm agent <VM_ID> ping` (sin respuesta = agente caído)
2. Si agente caído: `qm reboot <VM_ID>` y esperar 60s
3. Verifica servicio: `qm guest exec <VM_ID> -- systemctl status yiyolmb.service`
4. Si `inactive (dead)` y `journalctl -u yiyolmb.service -b` dice "No entries": problema de dependencias en el .service (debería tener `WantedBy=graphical.target`, no `multi-user.target`)

### `qm guest exec` da timeout / agent crash

- El agente QEMU se cuelga si recibe comandos muy largos o pesados (paso 1 del deploy a veces lo tumba)
- Solución: `qm reboot <VM_ID>`, esperar 60s, re-correr `./deploy_one.sh <VM_ID>`
- A veces hay que reintentar 2-3 veces hasta que el agente quede estable

### Spotify aparece en pantalla blanca / cargando

- El bot lanza Spotify con `subprocess.Popen(['spotify'])` sin flags
- Snap Spotify a veces requiere `--no-sandbox` en VMs
- Fix manual:
  ```bash
  qm guest exec <VM_ID> -- /bin/bash -c '
  killall spotify
  sleep 3
  runuser -l localuser -c "DISPLAY=:0 XAUTHORITY=/home/localuser/.Xauthority setsid /snap/bin/spotify --no-sandbox </dev/null >/tmp/spotify.log 2>&1 &"
  '
  ```

### Bot detecta canciones pero `Estado de Spotify: None`

- D-Bus session bus equivocada: el servicio debe tener `Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`
- Verifica con: `qm guest exec <VM_ID> -- systemctl show yiyolmb.service --property=Environment`

### Bot loggea `Corazon vacio no encontrado` siempre

- La imagen `images/Click_Like.png` no matchea con la versión actual de Spotify (UI cambió)
- Hay que **recapturar el template del corazón**:
  1. En noVNC, posiciona el cursor JUSTO sobre el corazón vacío en la barra del player
  2. Toma nota de coordenadas: `qm guest exec <VM_ID> -- /bin/bash -c 'DISPLAY=:0 XAUTHORITY=/home/localuser/.Xauthority xdotool getmouselocation'`
  3. Mueve el cursor LEJOS (a una esquina vacía)
  4. Corre el script de recorte (ver sección abajo)

### Recapturar la imagen del corazón

```bash
qm guest exec --timeout 15 <VM_ID> -- /bin/bash -c '
cat > /tmp/crop_heart.py << "EOF"
from PIL import Image
import os, cv2
os.system("DISPLAY=:0 XAUTHORITY=/home/localuser/.Xauthority gnome-screenshot -f /tmp/screen.png")
HEART_X, HEART_Y = <X>, <Y>   # <-- pon las coordenadas del corazón
SIZE = 20
img = Image.open("/tmp/screen.png")
cropped = img.crop((HEART_X - SIZE, HEART_Y - SIZE, HEART_X + SIZE, HEART_Y + SIZE))
cropped.save("/home/localuser/nuevo_spotify_bot/images/Click_Like.png")
print("Template guardado")
EOF
chown localuser:localuser /tmp/crop_heart.py
runuser -l localuser -c "DISPLAY=:0 XAUTHORITY=/home/localuser/.Xauthority /home/localuser/nuevo_spotify_bot/venv/bin/python3 /tmp/crop_heart.py"
chown localuser:localuser /home/localuser/nuevo_spotify_bot/images/Click_Like.png
systemctl restart yiyolmb.service
'
```

Después: hacer `git add images/Click_Like.png && git commit && git push` desde el host Proxmox para que las otras VMs también tengan la nueva imagen.

### El bot da like en coordenadas equivocadas

- Image recognition no encontró el corazón y cayó al fallback de `heart_x/heart_y` del config
- O Spotify cambió de posición (no debería pasar normalmente)
- Solución: recapturar el template (sección de arriba)

## Decisiones de diseño importantes

### Por qué `WantedBy=graphical.target`

Probamos `WantedBy=multi-user.target` y el servicio nunca arrancaba al boot. Causa: tenemos `After=graphical.target` (porque necesitamos X), pero `graphical.target` viene DESPUÉS de `multi-user.target`. Dependencia circular silenciosa. Solución: el servicio debe ser parte de `graphical.target`.

### Por qué `Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`

Spotify (lanzado dentro de la sesión gráfica de localuser) se registra en MPRIS en la D-Bus session bus del usuario (`/run/user/1000/bus`). Sin este env var, el bot systemd usa su propia D-Bus session (creada por dbus-launch --autolaunch) y no puede ver a Spotify. Resultado: `playerctl status` y `dbus-send PlaybackStatus` siempre devuelven None.

### Por qué `gnome-screenshot` en las dependencias

`pyautogui.locateOnScreen()` necesita tomar screenshots. En Linux, Pillow >= 9.2 lo intenta vía `gnome-screenshot` por defecto. Sin esa herramienta de sistema, falla con error de Pillow incluso si Pillow está instalado.

### Por qué el script de pre-arranque `yiyolmb-prestart.sh`

Cuando SDDM hace autologin, crea un archivo Xauthority en `/run/sddm/xauth_XXXX` o `/tmp/xauth_XXXX` pero NO lo copia a `/home/localuser/.Xauthority`. El bot (systemd User=localuser) busca el xauth en `~/.Xauthority` y falla con `XauthError`. El prestart copia el xauth correcto antes de arrancar el bot.

### Por qué quitamos los `sudo -u localuser` del deploy

`sudo` requiere password o `NOPASSWD` configurado. En las VMs no había `NOPASSWD`, así que `sudo -u localuser` colgaba pidiendo contraseña hasta el timeout. Como `qm guest exec` corre como root, podemos usar `crontab -u localuser`, `chown`, etc. directamente sin necesidad de sudo.

### Por qué image recognition en vez de coordenadas fijas

La barra del player de Spotify reorganiza sus elementos según el largo del nombre de la canción. Las coordenadas (451, 645) que funcionaban con un nombre corto, fallan con uno largo. `pyautogui.locateOnScreen()` busca la imagen del corazón sin importar dónde esté, siempre la encuentra.

### Por qué `Restart=on-failure` con `StartLimitIntervalSec=0`

Por defecto, systemd se rinde después de 5 reintentos en 10 segundos. Si el bot crashea repetidamente al boot (porque Spotify aún no está abierto, etc.), systemd marca el servicio como `failed` permanente. `StartLimitIntervalSec=0` desactiva el límite, así el bot siempre reintenta.
