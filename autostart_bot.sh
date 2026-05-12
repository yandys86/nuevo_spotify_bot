#!/bin/bash
# Auto-start script for nuevo_spotify_bot
# Runs as localuser inside LXQt session after autologin (SDDM).
# Steps: discover Xauth -> launch Spotify -> wait for MPRIS -> launch bot.

set -u
BOT_DIR="/home/localuser/nuevo_spotify_bot"
LOG_FILE="$BOT_DIR/autostart.log"
mkdir -p "$BOT_DIR"
exec >> "$LOG_FILE" 2>&1
echo "===== $(date '+%F %T') autostart begin ====="

# Ensure runtime dir / D-Bus env are present
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
export DISPLAY="${DISPLAY:-:0}"

# Re-discover SDDM Xauthority and copy to the path the bot expects
SDDM_XAUTH="$(ls -t /run/sddm/xauth_* /tmp/xauth_* 2>/dev/null | head -n1)"
if [ -n "${SDDM_XAUTH:-}" ] && [ -r "$SDDM_XAUTH" ]; then
  cp -f "$SDDM_XAUTH" "$HOME/.Xauthority"
  chmod 600 "$HOME/.Xauthority"
  echo "Copied Xauth from $SDDM_XAUTH to $HOME/.Xauthority"
else
  echo "WARN: no readable SDDM/tmp xauth found; relying on existing $HOME/.Xauthority"
fi
export XAUTHORITY="$HOME/.Xauthority"

# Wait for X server to be ready (up to ~30s)
for i in $(seq 1 30); do
  if xset q >/dev/null 2>&1; then
    echo "X server ready (try $i)"
    break
  fi
  sleep 1
done

# Launch Spotify if not already running
if ! pgrep -u "$USER" -f '/snap/bin/spotify|/snap/spotify/.*/spotify' >/dev/null 2>&1; then
  echo "Spotify not running, launching..."
  ( setsid /snap/bin/spotify --no-sandbox </dev/null >/tmp/spotify_autostart.log 2>&1 & )
else
  echo "Spotify already running"
fi

# Wait for Spotify to register on MPRIS (up to ~60s)
for i in $(seq 1 60); do
  if dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.ListNames 2>/dev/null | grep -q org.mpris.MediaPlayer2.spotify; then
    echo "Spotify MPRIS registered (try $i)"
    break
  fi
  sleep 1
done

# Avoid double-launching the bot
if pgrep -u "$USER" -f 'spotify_robot.py' >/dev/null 2>&1; then
  echo "Bot already running, exiting autostart"
  exit 0
fi

cd "$BOT_DIR" || { echo "ERROR: BOT_DIR missing"; exit 1; }

# Activate venv and launch bot detached
if [ ! -x "$BOT_DIR/venv/bin/python" ]; then
  echo "ERROR: venv missing at $BOT_DIR/venv"
  exit 1
fi

echo "Launching bot..."
( setsid "$BOT_DIR/venv/bin/python" "$BOT_DIR/spotify_robot.py" \
    </dev/null >>"$BOT_DIR/bot_stdout.log" 2>&1 & )

echo "===== $(date '+%F %T') autostart end ====="
