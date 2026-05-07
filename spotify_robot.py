import os
import time
import pyautogui
import random
import subprocess
import logging
import configparser
import requests
from enum import Enum
from datetime import datetime

# Configuración de pantalla para Proxmox
os.environ['XAUTHORITY'] = '/home/localuser/.Xauthority'
os.environ['DISPLAY'] = ':0'

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'global_config.ini')


class PlayerState(Enum):
    IDLE = 1
    PLAYING = 2


def load_config():
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    return config


def setup_logging(level_str='INFO'):
    level = getattr(logging, level_str.upper(), logging.INFO)
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('spotify_robot.log'),
            logging.StreamHandler()
        ]
    )


def send_telegram(message, chat_ids, token):
    for chat_id in chat_ids:
        try:
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            requests.post(url, data={'chat_id': chat_id.strip(), 'text': message}, timeout=10)
        except Exception as e:
            logging.warning(f"Telegram error: {e}")


def is_spotify_running():
    try:
        result = subprocess.run(['pgrep', '-x', 'spotify'], capture_output=True)
        return result.returncode == 0
    except Exception:
        return False


def get_current_song():
    """Obtiene la canción actual via D-Bus (MPRIS), más fiable que el título de ventana."""
    try:
        result = subprocess.run(
            ['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
             '/org/mpris/MediaPlayer2',
             'org.freedesktop.DBus.Properties.Get',
             'string:org.mpris.MediaPlayer2.Player',
             'string:Metadata'],
            capture_output=True, text=True
        )
        output = result.stdout
        title, artist = '', ''
        lines = output.split('\n')
        for i, line in enumerate(lines):
            if 'xesam:title' in line and i + 1 < len(lines):
                title = lines[i + 1].strip().strip('"')
            if 'xesam:artist' in line and i + 2 < len(lines):
                artist = lines[i + 2].strip().strip('"')
        if title:
            return f"{artist} - {title}" if artist else title
    except Exception:
        pass

    # Fallback: título de ventana con xdotool
    try:
        result = subprocess.run(
            'xdotool search --name "Spotify" | head -1 | xargs xdotool getwindowname',
            shell=True, capture_output=True, text=True
        )
        title = result.stdout.strip()
        if title and title.lower() != 'spotify' and ' - ' in title:
            return title
    except Exception:
        pass

    return None


def dar_like(corazon_x, corazon_y):
    logging.info(f"Dando Like en coordenadas: ({corazon_x}, {corazon_y})")
    pyautogui.click(corazon_x, corazon_y)
    time.sleep(0.5)


def iniciar_spotify():
    if is_spotify_running():
        logging.info("Spotify ya estaba corriendo, no se abre otra instancia")
        return True

    logging.info("Abriendo Spotify...")
    subprocess.Popen(['spotify'])
    time.sleep(10)

    if is_spotify_running():
        logging.info("Spotify iniciado correctamente")
        return True

    logging.error("No se pudo iniciar Spotify")
    return False


def abrir_playlist(playlist_id):
    """Abre una playlist en Spotify via D-Bus usando su URI."""
    uri = f"spotify:playlist:{playlist_id}"
    logging.info(f"Cambiando a playlist: {playlist_id}")
    try:
        subprocess.run(
            ['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
             '/org/mpris/MediaPlayer2',
             'org.mpris.MediaPlayer2.Player.OpenUri',
             f'string:{uri}'],
            capture_output=True
        )
        time.sleep(4)  # Espera a que Spotify cargue la playlist
        pyautogui.press('space')  # Inicia reproducción
        time.sleep(1)
        return True
    except Exception as e:
        logging.error(f"Error abriendo playlist {playlist_id}: {e}")
        return False


def esperar_horario(scheduled_hours):
    now = datetime.now().strftime('%H:%M')
    horas = [h.strip() for h in scheduled_hours.split(',') if h.strip()]
    if now in horas:
        return True
    logging.info(f"Hora actual {now} no está en horarios {horas}, esperando...")
    return False


def main():
    config = load_config()

    log_level = config.get('SETTINGS', 'log_level', fallback='INFO').strip()
    setup_logging(log_level)

    # Telegram
    send_msg = config.get('telegram', 'send_msg', fallback='no').strip().lower() == 'yes'
    chat_ids = config.get('telegram', 'chat_ids', fallback='').split(',')
    telegram_token = os.environ.get('TELEGRAM_TOKEN', '')

    # Coordenadas del corazón
    corazon_x = int(config.get('SETTINGS', 'heart_x', fallback='500'))
    corazon_y = int(config.get('SETTINGS', 'heart_y', fallback='710'))

    # Playlists
    raw_ids = config.get('Play_Lists', 'spotify_playlist_ids', fallback='')
    playlists = [p.strip() for p in raw_ids.split(',') if p.strip()]
    shuffle_playlists = config.get('scheduled_time', 'shuffle', fallback='no').strip().lower() == 'yes'
    # Tiempo en horas por playlist (0 = sin límite)
    horas_por_playlist = int(config.get('scheduled_time', 'time', fallback='0'))

    if not playlists:
        logging.error("No hay playlists configuradas en global_config.ini")
        return

    if shuffle_playlists:
        random.shuffle(playlists)
        logging.info(f"Playlists mezcladas: {playlists}")
    else:
        logging.info(f"Playlists en orden: {playlists}")

    # Horario programado
    use_schedule = config.get('scheduled_time', 'scheduled', fallback='no').strip().lower() == 'yes'
    scheduled_hours = config.get('scheduled_time', 'scheduled_hours', fallback='')

    state = PlayerState.IDLE
    last_song = None
    songs_liked = 0
    playlist_index = 0
    playlist_start_time = None

    logging.info("=== Spotify Robot iniciado ===")

    while True:
        try:
            # Verificar horario programado
            if use_schedule and scheduled_hours and not esperar_horario(scheduled_hours):
                time.sleep(60)
                continue

            if state == PlayerState.IDLE:
                if iniciar_spotify():
                    current_playlist = playlists[playlist_index % len(playlists)]
                    logging.info(f"Abriendo playlist [{playlist_index + 1}/{len(playlists)}]: {current_playlist}")

                    if abrir_playlist(current_playlist):
                        playlist_start_time = time.time()
                        state = PlayerState.PLAYING

                        if send_msg and telegram_token:
                            send_telegram(
                                f"Robot iniciado\nPlaylist: {current_playlist}\n({playlist_index + 1}/{len(playlists)})",
                                chat_ids, telegram_token
                            )
                    else:
                        logging.warning("No se pudo abrir la playlist, reintentando en 30s...")
                        time.sleep(30)
                else:
                    logging.warning("Spotify no disponible, reintentando en 30s...")
                    time.sleep(30)

            elif state == PlayerState.PLAYING:
                # Verificar si es hora de cambiar de playlist
                if horas_por_playlist > 0 and playlist_start_time:
                    elapsed_hours = (time.time() - playlist_start_time) / 3600
                    if elapsed_hours >= horas_por_playlist:
                        playlist_index += 1
                        current_playlist = playlists[playlist_index % len(playlists)]
                        logging.info(f"Tiempo cumplido. Cambiando a playlist: {current_playlist}")

                        if send_msg and telegram_token:
                            send_telegram(
                                f"Cambiando playlist\nNueva: {current_playlist}\n({(playlist_index % len(playlists)) + 1}/{len(playlists)})\nTotal likes: {songs_liked}",
                                chat_ids, telegram_token
                            )

                        abrir_playlist(current_playlist)
                        playlist_start_time = time.time()

                wait = random.randint(30, 60)
                logging.info(f"Esperando {wait}s...")
                time.sleep(wait)

                # Verificar que Spotify sigue corriendo
                if not is_spotify_running():
                    logging.warning("Spotify se cerró inesperadamente, reiniciando...")
                    state = PlayerState.IDLE
                    continue

                # Detectar cambio de canción y dar like
                current_song = get_current_song()
                if current_song and current_song != last_song:
                    logging.info(f"Nueva canción: {current_song}")
                    dar_like(corazon_x, corazon_y)
                    songs_liked += 1
                    last_song = current_song

                    if send_msg and telegram_token:
                        send_telegram(
                            f"Like dado a: {current_song}\nTotal likes: {songs_liked}",
                            chat_ids, telegram_token
                        )
                elif not current_song:
                    logging.warning("No se detectó canción activa en Spotify")

        except KeyboardInterrupt:
            logging.info(f"Robot detenido manualmente. Total likes dados: {songs_liked}")
            break
        except Exception as e:
            logging.error(f"Error inesperado: {e}")
            time.sleep(10)


if __name__ == '__main__':
    main()
