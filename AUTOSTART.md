# Auto-arranque del bot en la VM

Este repositorio incluye soporte para que el bot arranque automáticamente
cuando inicia la sesión gráfica de LXQt (autologin con SDDM).

## Componentes

- `autostart_bot.sh` — Script principal. Re-descubre el `Xauthority` de SDDM,
  exporta las variables necesarias de D-Bus / DISPLAY / XDG_RUNTIME_DIR,
  lanza Spotify (snap) si no está corriendo, espera a que se registre en
  MPRIS y finalmente lanza `spotify_robot.py` dentro del venv.
- `autostart/spotify-bot-autostart.desktop` — Entrada XDG Autostart. Debe
  copiarse a `~/.config/autostart/` para que LXQt la ejecute al iniciar
  sesión.

## Instalación en una VM nueva

```bash
# 1. Clonar el repo
git clone https://github.com/yandys86/nuevo_spotify_bot.git \
  /home/localuser/nuevo_spotify_bot
cd /home/localuser/nuevo_spotify_bot

# 2. Crear venv e instalar dependencias
python3 -m venv venv
./venv/bin/pip install requests pyautogui

# 3. Hacer el script ejecutable
chmod +x autostart_bot.sh

# 4. Instalar la entrada de autostart de LXQt
mkdir -p ~/.config/autostart
cp autostart/spotify-bot-autostart.desktop ~/.config/autostart/

# 5. (opcional) Variable TELEGRAM_TOKEN
echo 'export TELEGRAM_TOKEN="tu_token"' >> ~/.profile
```

Tras reiniciar la VM, el autologin entra al usuario, LXQt lanza el `.desktop`,
y este invoca `autostart_bot.sh`. Logs en:

- `/home/localuser/nuevo_spotify_bot/autostart.log`
- `/home/localuser/nuevo_spotify_bot/spotify_robot.log`
- `/home/localuser/nuevo_spotify_bot/bot_stdout.log`
- `/tmp/spotify_autostart.log`

## Control manual

```bash
# Parar el bot
pkill -f spotify_robot.py

# Lanzar manualmente
/home/localuser/nuevo_spotify_bot/autostart_bot.sh

# Ver logs en vivo
tail -f /home/localuser/nuevo_spotify_bot/spotify_robot.log
```
