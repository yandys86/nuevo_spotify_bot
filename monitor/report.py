#!/usr/bin/env python3
"""
Reporter diario del Spotify farm.

Corre en el host Proxmox (systemd timer diario ~10:00 AM).
Por cada VM viva:
  1. Lee activity.log de las últimas 24 h vía `qm guest exec <id> -- cat`
  2. Parsea eventos (SONG, LIKED, PLAYLIST, AD, AD_RESTART, ...)
  3. Chequea estado actual: bot vivo + Spotify Playing
Aggrega y envía a Telegram:
  - Mensaje corto con resumen visual
  - .txt attachment con el detalle completo de todas las VMs

Uso:
    python3 report.py                 # normal (últimas 24 h)
    python3 report.py --hours 4       # ventana custom
    python3 report.py --dry-run       # imprime sin enviar
    python3 report.py --to CHAT_ID    # override destino (test)

Env vars requeridas:
    TELEGRAM_TOKEN     Token del bot @YiyoLMB_Monitor_bot
    TELEGRAM_CHAT_IDS  IDs separados por coma
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path


VMS = [
    105, 106, 107, 108, 109, 111, 112, 113, 114, 115, 116,
    118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130,
]

ACTIVITY_LOG = "/home/localuser/nuevo_spotify_bot/activity.log"
STATE_FILE = Path(__file__).parent / "reporter_state.json"

# Formato de línea del log: "YYYY-MM-DD HH:MM:SS · EVENT · d1 [· d2 ...]"
LINE_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) · (?P<event>[A-Z_]+)(?: · (?P<details>.+))?$"
)


def load_env():
    """Lee .env del mismo directorio si existe (formato KEY=VALUE por línea)."""
    env_path = Path(__file__).parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def qm_exec(vmid: int, cmd: str, timeout: int = 20) -> tuple[int, str]:
    """Ejecuta un comando dentro de la VM vía qemu-guest-agent."""
    try:
        r = subprocess.run(
            ["qm", "guest", "exec", "--timeout", str(timeout), str(vmid), "--",
             "/bin/bash", "-c", cmd],
            capture_output=True, text=True, timeout=timeout + 10,
        )
        if r.returncode != 0:
            return 1, r.stderr.strip() or "qm exec failed"
        # qm devuelve JSON en stdout
        try:
            data = json.loads(r.stdout)
            return int(data.get("exitcode", 1)), data.get("out-data", "") or data.get("err-data", "")
        except json.JSONDecodeError:
            return 1, r.stdout
    except subprocess.TimeoutExpired:
        return 1, "timeout"
    except Exception as e:
        return 1, str(e)


def check_vm_health(vmid: int) -> dict:
    """Estado ligero: agent responde? service activo? Spotify Playing?"""
    # 1) Agent ping (qm agent primero, más rápido que guest exec)
    r = subprocess.run(["qm", "agent", str(vmid), "ping"],
                       capture_output=True, timeout=8)
    if r.returncode != 0:
        return {"agent": False, "service": None, "spotify": None}

    # 2) Servicio
    rc, out = qm_exec(vmid, "systemctl is-active yiyolmb.service", timeout=10)
    service = out.strip() if out else "unknown"

    # 3) Estado Spotify vía D-Bus/playerctl
    rc, out = subprocess.run(
        ["qm", "guest", "exec", "--timeout", "12", str(vmid), "--",
         "runuser", "-u", "localuser", "--", "/bin/bash", "-c",
         "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus playerctl -p spotify status 2>/dev/null"],
        capture_output=True, text=True, timeout=25,
    ), None
    spotify = None
    try:
        data = json.loads(rc.stdout)
        raw = (data.get("out-data") or "").strip()
        m = re.search(r"Playing|Paused|Stopped", raw)
        spotify = m.group(0) if m else "unknown"
    except Exception:
        spotify = "unknown"

    return {"agent": True, "service": service, "spotify": spotify}


def fetch_activity(vmid: int, since: datetime) -> list[dict]:
    """Devuelve las líneas parseadas de activity.log desde `since`."""
    # `awk` filtra en la VM para no transferir logs enormes.
    since_str = since.strftime("%Y-%m-%d %H:%M:%S")
    cmd = (
        f"awk -v s='{since_str}' "
        f"'$0 >= s' {ACTIVITY_LOG} 2>/dev/null || true"
    )
    rc, out = qm_exec(vmid, cmd, timeout=25)
    events = []
    for line in (out or "").splitlines():
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        events.append({
            "ts": m.group("ts"),
            "event": m.group("event"),
            "details": m.group("details") or "",
            "vm": vmid,
        })
    return events


def aggregate(all_events: dict[int, list[dict]]) -> dict:
    """Estadísticas globales + por VM."""
    per_vm = {}
    total_songs = 0
    total_likes = 0
    total_ads = 0
    total_restarts = 0
    playlist_counter = Counter()   # playlist_id → nº VMs que la tocaron
    songs_global = Counter()       # 'artist - title' → repeticiones globales

    for vmid, events in all_events.items():
        songs = [e for e in events if e["event"] == "SONG"]
        likes = [e for e in events if e["event"] == "LIKED"]
        ads = [e for e in events if e["event"] == "AD"]
        restarts = [e for e in events if e["event"] == "AD_RESTART"]
        playlists = [e for e in events if e["event"] == "PLAYLIST"]

        last_song = songs[-1]["details"] if songs else None
        last_playlist = playlists[-1]["details"].split(" · ")[0] if playlists else None

        per_vm[vmid] = {
            "songs": len(songs),
            "likes": len(likes),
            "ads": len(ads),
            "restarts": len(restarts),
            "unique_songs": len({s["details"] for s in songs}),
            "last_song": last_song,
            "last_playlist": last_playlist,
        }
        total_songs += len(songs)
        total_likes += len(likes)
        total_ads += len(ads)
        total_restarts += len(restarts)
        for p in playlists:
            pid = p["details"].split(" · ")[0]
            playlist_counter[pid] += 1
        for s in songs:
            songs_global[s["details"]] += 1

    return {
        "per_vm": per_vm,
        "total_songs": total_songs,
        "total_likes": total_likes,
        "total_ads": total_ads,
        "total_restarts": total_restarts,
        "unique_songs_global": len(songs_global),
        "top_songs": songs_global.most_common(10),
        "playlists": playlist_counter.most_common(),
    }


def format_message(agg: dict, health: dict[int, dict], window_hours: int) -> str:
    """Mensaje corto en HTML para Telegram (máx 4096 chars)."""
    ok_count = sum(1 for h in health.values()
                   if h["agent"] and h["service"] == "active" and h["spotify"] == "Playing")
    total = len(health)
    now = datetime.now().strftime("%H:%M")

    lines = []
    lines.append(f"🎵 <b>YiyoLMB Spotify Farm</b>")
    lines.append(f"Reporte últimas {window_hours}h · {now}")
    lines.append("")
    lines.append(f"✅ <b>{ok_count}/{total} VMs Playing</b>")

    problems = []
    for vmid, h in sorted(health.items()):
        if not h["agent"]:
            problems.append(f"VM {vmid} · off / no agent")
        elif h["service"] != "active":
            problems.append(f"VM {vmid} · bot {h['service']}")
        elif h["spotify"] != "Playing":
            problems.append(f"VM {vmid} · Spotify {h['spotify']}")

    if problems:
        lines.append("⚠️ <b>Problemas:</b>")
        for p in problems[:10]:
            lines.append(f"  • {p}")
        if len(problems) > 10:
            lines.append(f"  … y {len(problems) - 10} más")
    lines.append("")

    lines.append(f"📊 Total: {agg['total_songs']} plays · {agg['total_likes']} likes · {agg['total_ads']} anuncios")
    lines.append(f"🎼 Canciones únicas: {agg['unique_songs_global']}")

    if agg["top_songs"]:
        lines.append("")
        lines.append("<b>🏆 Top 5 canciones (global):</b>")
        for song, count in agg["top_songs"][:5]:
            lines.append(f"  <code>{count}×</code> {_esc(song)}")

    if agg["playlists"]:
        lines.append("")
        lines.append("<b>🎧 Playlists activas:</b>")
        for pid, count in agg["playlists"][:5]:
            lines.append(f"  {count} VMs · <code>{pid[:22]}…</code>")

    lines.append("")
    lines.append("<b>Por VM:</b>")
    for vmid in sorted(agg["per_vm"]):
        v = agg["per_vm"][vmid]
        if v["songs"] == 0:
            continue
        last = v["last_song"] or "?"
        lines.append(f"  <b>{vmid}</b> · {v['songs']}🎵 {v['likes']}❤ · <i>{_esc(last[:38])}</i>")

    return "\n".join(lines)


def build_attachment(agg: dict, all_events: dict[int, list[dict]], health: dict[int, dict]) -> bytes:
    """Genera el .txt con el detalle completo."""
    buf = io.StringIO()
    buf.write("YIYOLMB SPOTIFY FARM · REPORTE DETALLADO\n")
    buf.write(f"Generado: {datetime.now().isoformat(' ', 'seconds')}\n")
    buf.write("=" * 70 + "\n\n")

    buf.write("SALUD DE LAS VMs\n")
    buf.write("-" * 70 + "\n")
    for vmid in sorted(health):
        h = health[vmid]
        buf.write(f"VM {vmid:>3}  agent={('YES' if h['agent'] else 'NO'):3}  "
                  f"service={h['service'] or '-':10}  spotify={h['spotify'] or '-':10}\n")

    buf.write("\nRESUMEN GLOBAL\n")
    buf.write("-" * 70 + "\n")
    buf.write(f"Total plays          : {agg['total_songs']}\n")
    buf.write(f"Total likes          : {agg['total_likes']}\n")
    buf.write(f"Anuncios detectados  : {agg['total_ads']}\n")
    buf.write(f"Reinicios anti-ad    : {agg['total_restarts']}\n")
    buf.write(f"Canciones únicas     : {agg['unique_songs_global']}\n")

    buf.write("\nTOP 20 CANCIONES (global)\n")
    buf.write("-" * 70 + "\n")
    for song, count in agg["top_songs"][:20]:
        buf.write(f"  {count:>4}×  {song}\n")

    for vmid in sorted(all_events):
        events = all_events[vmid]
        v = agg["per_vm"].get(vmid, {})
        buf.write(f"\n\n{'='*70}\nVM {vmid}\n{'='*70}\n")
        buf.write(f"Plays: {v.get('songs',0)}  Likes: {v.get('likes',0)}  "
                  f"Ads: {v.get('ads',0)}  Restarts: {v.get('restarts',0)}  "
                  f"Únicas: {v.get('unique_songs',0)}\n\n")
        for e in events:
            det = f" · {e['details']}" if e["details"] else ""
            buf.write(f"  {e['ts']}  {e['event']:<14}{det}\n")

    return buf.getvalue().encode("utf-8")


def _esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def send_telegram_message(token: str, chat_id: str, text: str) -> bool:
    import urllib.request
    import urllib.parse
    try:
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=urllib.parse.urlencode({
                "chat_id": chat_id,
                "text": text,
                "parse_mode": "HTML",
                "disable_web_page_preview": "true",
            }).encode(),
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status == 200
    except Exception as e:
        print(f"send_telegram_message error: {e}", file=sys.stderr)
        return False


def send_telegram_document(token: str, chat_id: str, filename: str, content: bytes, caption: str = "") -> bool:
    """sendDocument via multipart/form-data. Sin dependencias externas."""
    import uuid
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in (("chat_id", chat_id), ("caption", caption[:1024]),
                        ("parse_mode", "HTML")):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode())
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"document\"; filename=\"{filename}\"\r\n"
        f"Content-Type: text/plain\r\n\r\n".encode() + content + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)

    import urllib.request
    try:
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendDocument",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status == 200
    except Exception as e:
        print(f"send_telegram_document error: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=int, default=24)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--to", type=str, help="Override chat_id destino")
    args = parser.parse_args()

    load_env()
    token = os.environ.get("TELEGRAM_TOKEN")
    chat_ids_raw = os.environ.get("TELEGRAM_CHAT_IDS", "")
    if not token and not args.dry_run:
        print("TELEGRAM_TOKEN no está configurado", file=sys.stderr)
        return 2

    chat_ids = [args.to] if args.to else [c.strip() for c in chat_ids_raw.split(",") if c.strip()]

    since = datetime.now() - timedelta(hours=args.hours)
    print(f"[reporter] Ventana: {since:%Y-%m-%d %H:%M:%S} → {datetime.now():%Y-%m-%d %H:%M:%S}")

    # Salud + eventos, en paralelo por VM sería ideal pero secuencial es OK
    # para 24 VMs (~30 s total).
    health = {}
    all_events = {}
    for vmid in VMS:
        print(f"[reporter] VM {vmid}…", end=" ", flush=True)
        health[vmid] = check_vm_health(vmid)
        if health[vmid]["agent"]:
            all_events[vmid] = fetch_activity(vmid, since)
            print(f"OK ({len(all_events[vmid])} eventos)")
        else:
            all_events[vmid] = []
            print("agent off")

    agg = aggregate(all_events)
    msg = format_message(agg, health, args.hours)
    txt = build_attachment(agg, all_events, health)
    fname = f"spotify_farm_{datetime.now():%Y%m%d_%H%M}.txt"

    if args.dry_run:
        print("=" * 70)
        print(msg)
        print("=" * 70)
        print(f"[dry-run] Attachment {fname}: {len(txt):,} bytes")
        return 0

    ok = True
    for cid in chat_ids:
        m_ok = send_telegram_message(token, cid, msg)
        d_ok = send_telegram_document(token, cid, fname, txt, f"Detalle completo · {len(txt):,} bytes")
        ok = ok and m_ok and d_ok
        print(f"[reporter] chat {cid}: msg={'OK' if m_ok else 'FAIL'} doc={'OK' if d_ok else 'FAIL'}")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
