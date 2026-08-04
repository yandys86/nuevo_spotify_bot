#!/usr/bin/env python3
"""
Alertas instantáneas del Spotify farm.

Corre en el host Proxmox (systemd timer cada 5 min).
Compara el estado actual vs el guardado y solo alerta si cambia.

Estados considerados anomalías:
  - VM off (qm agent no responde)
  - Bot yiyolmb.service NO active
  - Spotify no está Playing (Paused/Stopped/None)

Almacena estado en alerts_state.json — un ping por transición, no por check.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from report import (  # noqa: E402
    VMS, check_vm_health, load_env,
    send_telegram_message,
)

STATE_FILE = Path(__file__).parent / "alerts_state.json"


def compute_state(health: dict) -> str:
    """Reduce el health a un string tag para comparar transiciones."""
    if not health["agent"]:
        return "vm_off"
    if health["service"] != "active":
        return f"bot_{health['service']}"
    if health["spotify"] != "Playing":
        return f"spotify_{health['spotify']}"
    return "ok"


def label_for(state: str) -> str:
    return {
        "ok": "✅ OK",
        "vm_off": "🔴 VM apagada",
    }.get(state, {
        "bot_inactive": "🟠 Bot inactivo",
        "bot_failed": "🔴 Bot fallido",
        "spotify_Paused": "🟡 Spotify pausado",
        "spotify_Stopped": "🟡 Spotify detenido",
        "spotify_None": "🟡 Spotify no responde",
        "spotify_unknown": "🟡 Estado desconocido",
    }.get(state, f"⚠️ {state}"))


def main():
    load_env()
    token = os.environ.get("TELEGRAM_TOKEN")
    chat_ids = [c.strip() for c in os.environ.get("TELEGRAM_CHAT_IDS", "").split(",") if c.strip()]
    if not token or not chat_ids:
        print("TELEGRAM_TOKEN/TELEGRAM_CHAT_IDS no configurados", file=sys.stderr)
        return 2

    prev = {}
    if STATE_FILE.exists():
        try:
            prev = json.loads(STATE_FILE.read_text())
        except Exception:
            prev = {}

    current = {}
    alerts = []

    for vmid in VMS:
        h = check_vm_health(vmid)
        st = compute_state(h)
        current[str(vmid)] = st
        prev_st = prev.get(str(vmid))
        if prev_st is not None and prev_st != st:
            arrow = f"{label_for(prev_st)} → {label_for(st)}"
            alerts.append(f"<b>VM {vmid}</b>\n{arrow}")

    STATE_FILE.write_text(json.dumps(current, indent=2))

    if not alerts:
        return 0

    now = datetime.now().strftime("%H:%M:%S")
    body = f"🚨 <b>Alerta Spotify Farm</b> · {now}\n\n" + "\n\n".join(alerts)
    for cid in chat_ids:
        send_telegram_message(token, cid, body)
    print(f"[alerts] Enviadas {len(alerts)} alerta(s) a {len(chat_ids)} chat(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
