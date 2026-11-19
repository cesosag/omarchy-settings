#!/usr/bin/env python3
"""Full Omarchy keybinding catalog for the settings GUI."""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
HYPR_BINDINGS = HOME / ".config" / "hypr" / "bindings.lua"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / "omarchy" / "cesosag.settings"
STATE_FILE = STATE_DIR / "binding-overrides.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "omarchy"
CUSTOM_BEGIN = "-- >>> cesosag.settings:custom"
CUSTOM_END = "-- <<< cesosag.settings:custom"


def _arrow_split(display: str) -> tuple[str, str]:
    if "→" in display:
        left, right = display.split("→", 1)
        return left.strip(), right.strip()
    return display.strip(), ""


def load_records() -> list[dict]:
    # Refresh cache via --print (side effect: output_binding_records).
    subprocess.run(["omarchy-menu-keybindings", "--print"], capture_output=True, text=True, check=False)
    files = sorted(CACHE_DIR.glob("keybindings-*.records"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        return []
    rows = []
    for line in files[0].read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        keys, label = _arrow_split(parts[0])
        # Alternative chords "A / B" — keep leading chord as identity keys.
        primary = keys.split(" / ")[0].strip()
        rows.append(
            {
                "id": primary + "\x1f" + label,
                "originalKeys": primary,
                "keys": primary,
                "label": label,
                "allKeys": keys,
                "dispatcher": parts[1].strip() if len(parts) > 1 else "",
                "arg": "\t".join(parts[2:]).strip() if len(parts) > 2 else "",
                "status": "default",
            }
        )
    return rows


def load_state() -> dict:
    if not STATE_FILE.is_file():
        return {"overrides": [], "customs": []}
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"overrides": [], "customs": []}
    if not isinstance(data, dict):
        return {"overrides": [], "customs": []}
    data.setdefault("overrides", [])
    data.setdefault("customs", [])
    return data


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    tmp.replace(STATE_FILE)


def merge_catalog(records: list[dict], state: dict) -> list[dict]:
    overrides = {str(o.get("id") or ""): o for o in state.get("overrides") or [] if o.get("id")}
    out = []
    for row in records:
        item = dict(row)
        ov = overrides.get(item["id"])
        if ov:
            status = str(ov.get("status") or "rebound")
            item["status"] = status
            if status == "unbound":
                item["keys"] = str(ov.get("keys") or item["originalKeys"])
            else:
                item["keys"] = str(ov.get("keys") or item["originalKeys"])
                if ov.get("label"):
                    item["label"] = str(ov["label"])
                if ov.get("dispatcher"):
                    item["dispatcher"] = str(ov["dispatcher"])
                if "arg" in ov:
                    item["arg"] = str(ov.get("arg") or "")
        out.append(item)

    for custom in state.get("customs") or []:
        keys = str(custom.get("keys") or "").strip()
        label = str(custom.get("label") or "").strip()
        if not keys:
            continue
        out.append(
            {
                "id": "custom\x1f" + keys + "\x1f" + label,
                "originalKeys": keys,
                "keys": keys,
                "label": label,
                "allKeys": keys,
                "dispatcher": "exec",
                "arg": str(custom.get("command") or custom.get("arg") or ""),
                "status": "custom",
            }
        )
    return out


def lua_str(value: str) -> str:
    return json.dumps(str(value))


def render_override_lines(state: dict) -> str:
    lines = [
        "-- Keybinding overrides managed by cesosag.settings.",
        "-- Generated from the Settings GUI. Custom Lua below the marker is preserved.",
        "",
    ]
    for ov in state.get("overrides") or []:
        status = str(ov.get("status") or "")
        original = str(ov.get("originalKeys") or "").strip()
        keys = str(ov.get("keys") or original).strip()
        label = str(ov.get("label") or "")
        dispatcher = str(ov.get("dispatcher") or "")
        arg = str(ov.get("arg") or "")
        if not original:
            continue
        if status == "unbound":
            lines.append(f"hl.unbind({lua_str(original)})")
            continue
        if status != "rebound":
            continue
        # Drop the original chord, then bind the (possibly new) chord.
        if keys != original:
            lines.append(f"hl.unbind({lua_str(original)})")
        else:
            lines.append(f"hl.unbind({lua_str(keys)})")
        if dispatcher == "exec" or dispatcher == "":
            label_l = "nil" if not label else lua_str(label)
            lines.append(f"o.bind({lua_str(keys)}, {label_l}, {lua_str(arg)})")
        elif dispatcher == "lua" and arg:
            # arg is already a Lua expression returning a dispatcher object.
            desc = f", {{ description = {lua_str(label)} }}" if label else ""
            lines.append(f"hl.bind({lua_str(keys)}, {arg}{desc})")
        else:
            # sendshortcut / other — keep as exec of hyprctl dispatch when possible
            label_l = "nil" if not label else lua_str(label)
            cmd = f"hyprctl dispatch {dispatcher} {arg}".strip()
            lines.append(f"o.bind({lua_str(keys)}, {label_l}, {lua_str(cmd)})")
        lines.append("")

    for custom in state.get("customs") or []:
        keys = str(custom.get("keys") or "").strip()
        label = str(custom.get("label") or "")
        command = str(custom.get("command") or custom.get("arg") or "").strip()
        if not keys:
            continue
        label_l = "nil" if not label else lua_str(label)
        lines.append(f"o.bind({lua_str(keys)}, {label_l}, {lua_str(command)})")

    lines.append("")
    return "\n".join(lines)


def extract_custom(text: str) -> str:
    if CUSTOM_BEGIN in text and CUSTOM_END in text:
        _, rest = text.split(CUSTOM_BEGIN, 1)
        custom, _ = rest.split(CUSTOM_END, 1)
        return custom.strip("\n")
    # Already a GUI-managed file (no marker yet): do not treat generated
    # overrides as custom on the next write.
    if "-- Keybinding overrides managed by cesosag.settings." in text:
        return ""
    # First GUI write on a hand-edited file: keep active bind lines only.
    active = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        if s.startswith(("hl.unbind", "o.bind", "o.rebind", "hl.bind")):
            active.append(line)
    return "\n".join(active).strip("\n")


def write_bindings_lua(state: dict) -> None:
    path = HYPR_BINDINGS
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    custom = extract_custom(text)
    if path.is_file():
        shutil = __import__("shutil")
        shutil.copy2(path, path.with_name(path.name + f".bak.{int(time.time())}"))
    body = render_override_lines(state)
    if custom.strip():
        body += f"\n{CUSTOM_BEGIN}\n{custom}\n{CUSTOM_END}\n"
    tmp = path.with_suffix(".tmp")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text(body, encoding="utf-8")
    tmp.replace(path)
    subprocess.run(["hyprctl", "reload"], capture_output=True, check=False)


def get_catalog() -> dict:
    records = load_records()
    state = load_state()
    items = merge_catalog(records, state)
    return {"items": items, "count": len(items)}


def set_catalog(payload: dict) -> None:
    overrides = payload.get("overrides")
    customs = payload.get("customs")
    if overrides is None or customs is None:
        # Accept full items list and derive overrides/customs.
        items = payload.get("items") or []
        overrides = []
        customs = []
        for item in items:
            status = str(item.get("status") or "default")
            if status == "custom":
                customs.append(
                    {
                        "keys": item.get("keys"),
                        "label": item.get("label"),
                        "command": item.get("arg") or item.get("command") or "",
                    }
                )
            elif status in ("rebound", "unbound"):
                overrides.append(
                    {
                        "id": item.get("id"),
                        "originalKeys": item.get("originalKeys"),
                        "keys": item.get("keys"),
                        "label": item.get("label"),
                        "dispatcher": item.get("dispatcher"),
                        "arg": item.get("arg"),
                        "status": status,
                    }
                )
    state = {"overrides": overrides or [], "customs": customs or []}
    save_state(state)
    write_bindings_lua(state)
    print("bindings catalog updated")
