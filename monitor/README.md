# Monitor Spotify Farm

Recolector centralizado que corre en el **host Proxmox** (no en las VMs) y manda a Telegram:

- **Digest diario** (10:00 AM) con canciones, likes, playlists activas y salud de las 24 VMs
- **Alertas instantáneas** cuando una VM cambia de estado (bot muerto, Spotify apagado, VM off)

## Componentes

| Fichero | Cuándo corre | Qué hace |
|---|---|---|
| `report.py` | 1×/día por systemd timer | Genera y envía el digest completo + `.txt` adjunto |
| `alerts.py` | cada 5 min por systemd timer | Compara estado vs anterior, alerta si cambia |
| `.env` | — | `TELEGRAM_TOKEN` + `TELEGRAM_CHAT_IDS` |
| `install.sh` | 1 vez | Instala los systemd units, enable + start timers |

## Instalación (una sola vez)

```bash
# En el host Proxmox
cd /root/nuevo_spotify_bot
git pull
bash monitor/install.sh
# Editar .env si el chat_id no es el correcto
nano monitor/.env
```

## Cómo funciona

El monitor **no toca las VMs directamente** para consultar canciones — el propio
`spotify_robot.py` ya escribe `activity.log` con eventos estructurados en cada VM.

El reporter:
1. Pide `qm agent <id> ping` a cada VM (rápido, 8s timeout)
2. Si responde: pide `systemctl is-active yiyolmb.service` + `playerctl status`
3. Si el bot está vivo: pide `cat activity.log` filtrado por timestamp (awk en la VM)
4. Aggrega en memoria (Counter de canciones/playlists/likes)
5. Envía a Telegram: mensaje HTML corto + attachment `.txt` con el detalle

## Prueba manual

```bash
# Dry-run: aggrega y muestra el mensaje sin enviar
python3 /root/nuevo_spotify_bot/monitor/report.py --dry-run

# Enviar reporte de las últimas 4 horas
python3 /root/nuevo_spotify_bot/monitor/report.py --hours 4

# Enviar SOLO a un chat_id de test
python3 /root/nuevo_spotify_bot/monitor/report.py --to 123456789
```

## Formato del activity.log

```
2026-08-04 14:32:11 · BOT_START · 3 playlists · shuffle=no
2026-08-04 14:32:15 · SPOTIFY_START
2026-08-04 14:32:19 · PLAYLIST · 779uIDTTsL3NcTEHKg8TAC · 1/3
2026-08-04 14:32:22 · SONG · Rauw Alejandro - Baila Conmigo
2026-08-04 14:34:41 · LIKED · Rauw Alejandro - Baila Conmigo
2026-08-04 14:36:22 · AD · detected 1/8
2026-08-04 14:36:25 · SONG · Bad Bunny - Titi Me Preguntó
```

## Troubleshooting

**"No agent responde" en muchas VMs**: puede ser que un cleanup masivo colgara al
`qemu-guest-agent`. Reinicia la agent en cada VM: `qm reboot <id>` (evítalo si el
bot está haciendo streams — pierdes minutos).

**Alerts no llegan pero el reporte diario sí**: revisa `/var/log/journal` para
`yiyolmb-alerts.service`. El script usa el mismo Telegram token, si el reporte
funciona el problema es en la lógica (probablemente `alerts_state.json` está
corrupto — bórralo y prueba).

**Mensaje truncado en Telegram**: el límite del `sendMessage` es 4096 chars. El
detalle completo va siempre en el `.txt` adjunto — abre eso si el mensaje se
corta.
