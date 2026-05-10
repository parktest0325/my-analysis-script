#!/usr/bin/env python3
"""Send Codex CLI hook events to Telegram.

Codex CLI 0.129+ delivers hook payloads as JSON on **stdin**. Wire it via
~/.codex/hooks.json or the [hooks] table in ~/.codex/config.toml. The
codex_hooks feature flag must be enabled.

Stdin payload (Stop event example):
    {"session_id":"...","transcript_path":"...","cwd":"...",
     "hook_event_name":"Stop","model":"...","turn_id":"..."}

Credentials come from a .env next to this script:
    TELEGRAM_BOT_TOKEN=123:abc
    TELEGRAM_CHAT_ID=123456789

Manual test (no Codex):
    echo '{"hook_event_name":"Stop","cwd":"D:/proj","model":"gpt-5.5"}' | \
        python notify_telegram.py
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

TELEGRAM_TEXT_LIMIT = 4096


def log_invocation(script_dir: Path, note: str) -> None:
    try:
        with (script_dir / "notify.log").open("a", encoding="utf-8") as f:
            f.write(f"{datetime.now().isoformat()} {note}\n")
    except Exception:
        pass


def load_env(env_path: Path) -> None:
    if not env_path.exists():
        return
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key.strip(), value)


def truncate(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def short_cwd(cwd: str) -> str:
    if not cwd:
        return ""
    p = Path(cwd)
    return p.name or str(p)


def format_event(payload: dict) -> str:
    event = payload.get("hook_event_name") or payload.get("type") or "unknown"
    cwd = short_cwd(payload.get("cwd", ""))
    model = payload.get("model", "")
    suffix_lines = [x for x in (f"📁 {cwd}" if cwd else "", f"🤖 {model}" if model else "") if x]
    suffix = ("\n" + "\n".join(suffix_lines)) if suffix_lines else ""

    if event == "Stop":
        return f"✅ Codex turn complete{suffix}"

    if event == "PermissionRequest":
        tool = payload.get("tool_name") or ""
        return f"⏸️ Codex needs approval{(' — ' + tool) if tool else ''}{suffix}"

    if event == "UserPromptSubmit":
        prompt = (payload.get("prompt") or payload.get("user_prompt") or "").strip()
        head = f"\n📝 {truncate(prompt, 500)}" if prompt else ""
        return f"📨 Prompt submitted{head}{suffix}"

    if event == "PreToolUse":
        return f"🔧 PreTool: {payload.get('tool_name', '')}{suffix}"

    if event == "PostToolUse":
        return f"✔️ PostTool: {payload.get('tool_name', '')}{suffix}"

    if event == "SessionStart":
        return f"🚀 Codex session started{suffix}"

    # Legacy `notify` mechanism payload (kept for backward-compat).
    if event == "agent-turn-complete":
        inputs = payload.get("input-messages") or []
        first = (inputs[0] if inputs else "").strip()
        last = (payload.get("last-assistant-message") or "").strip()
        parts = ["✅ Codex turn complete"]
        if first:
            parts.append(f"\n📥 {truncate(first, 300)}")
        if last:
            parts.append(f"\n📤 {truncate(last, 1500)}")
        return "".join(parts)

    body = json.dumps(payload, ensure_ascii=False, indent=2)
    return truncate(f"🔔 {event}\n{body}", 3500)


def build_message(raw: str) -> str:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return raw
    if isinstance(payload, dict):
        return format_event(payload)
    return str(payload)


def read_payload(argv: list[str]) -> str:
    """Stdin first (real Codex hook), then argv[1] (manual test).

    Read stdin as raw bytes and decode as UTF-8 so we don't depend on
    sys.stdin.encoding (cp949 on Windows by default — would mangle non-ASCII).
    """
    raw = ""
    try:
        if not sys.stdin.isatty():
            data = sys.stdin.buffer.read()
            if data.startswith(b"\xef\xbb\xbf"):
                data = data[3:]
            elif data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
                # UTF-16 BOM (PowerShell 5.1 pipe)
                bom = data[:2]
                data = data[2:].decode("utf-16-le" if bom == b"\xff\xfe" else "utf-16-be").encode("utf-8")
            raw = data.decode("utf-8", errors="replace")
    except Exception:
        raw = ""
    raw = (raw or "").strip()
    if raw:
        return raw
    if len(argv) >= 2:
        return argv[1]
    return ""


def send_telegram(token: str, chat_id: str, text: str) -> None:
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = urllib.parse.urlencode(
        {
            "chat_id": chat_id,
            "text": truncate(text, TELEGRAM_TEXT_LIMIT),
            "disable_web_page_preview": "true",
        }
    ).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def main(argv: list[str]) -> int:
    script_dir = Path(__file__).resolve().parent
    load_env(script_dir / ".env")

    raw = read_payload(argv)
    log_invocation(script_dir, f"start raw={raw[:300]!r}")

    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    if not token or not chat_id:
        log_invocation(script_dir, "missing creds")
        print("TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set", file=sys.stderr)
        return 1

    if not raw:
        log_invocation(script_dir, "no payload")
        print("no payload on stdin or argv", file=sys.stderr)
        return 2

    text = build_message(raw)

    try:
        send_telegram(token, chat_id, text)
    except Exception as e:  # noqa: BLE001
        log_invocation(script_dir, f"send failed: {e}")
        print(f"telegram send failed: {e}", file=sys.stderr)
        return 3
    log_invocation(script_dir, "sent ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
