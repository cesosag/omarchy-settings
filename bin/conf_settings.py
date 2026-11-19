#!/usr/bin/env python3
"""Hypr-style .conf backends (hyprsunset, xdph)."""

from __future__ import annotations

import re
import shutil
import subprocess
import time
from pathlib import Path

HOME = Path.home()
HYPR = HOME / ".config" / "hypr"
AUTOSTART = HYPR / "autostart.lua"
CUSTOM_BEGIN = "# >>> cesosag.settings:custom"
CUSTOM_END = "# <<< cesosag.settings:custom"

HYPRSUNSET = HYPR / "hyprsunset.conf"
XDPH = HYPR / "xdph.conf"

HYPRSUNSET_DEFAULTS = {
    "dayTime": "07:00",
    "nightEnabled": False,
    "nightTime": "20:00",
    "temperature": 4000,
    "gamma": None,
    "launchOnStart": False,
}

XDPH_DEFAULTS = {
    "allow_token_by_default": True,
    "custom_picker_binary": "hyprland-preview-share-picker",
}


def backup(path: Path) -> None:
    if path.is_file():
        shutil.copy2(path, path.with_name(path.name + f".bak.{int(time.time())}"))


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def extract_custom(text: str) -> str:
    if CUSTOM_BEGIN in text and CUSTOM_END in text:
        _, rest = text.split(CUSTOM_BEGIN, 1)
        custom, _ = rest.split(CUSTOM_END, 1)
        return custom.strip("\n")
    # First GUI write: keep original comments / extras rather than dropping them.
    if text.strip() and "# Managed by cesosag.settings." not in text:
        return text.strip("\n")
    return ""


def wrap_custom(custom: str) -> str:
    custom = (custom or "").strip("\n")
    if not custom.strip():
        return ""
    return f"\n{CUSTOM_BEGIN}\n{custom}\n{CUSTOM_END}\n"


def parse_blocks(text: str, name: str) -> list[dict]:
    """Parse `name { key = value }` blocks; skip commented lines."""
    blocks: list[dict] = []
    # Strip full-line comments for matching, but only match uncommented blocks.
    pattern = re.compile(
        rf"(?m)^(?!\s*#)\s*{re.escape(name)}\s*\{{(.*?)^(?!\s*#)\s*\}}",
        re.S,
    )
    for m in pattern.finditer(text):
        body = m.group(1)
        entry: dict = {}
        for line in body.splitlines():
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if "=" not in s:
                continue
            key, raw = s.split("=", 1)
            key = key.strip()
            raw = raw.strip().rstrip(";")
            if raw.lower() in ("true", "false"):
                entry[key] = raw.lower() == "true"
            else:
                try:
                    if "." in raw:
                        entry[key] = float(raw)
                    else:
                        entry[key] = int(raw)
                except ValueError:
                    entry[key] = raw.strip('"').strip("'")
        blocks.append(entry)
    return blocks


def conf_literal(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and value.is_integer():
            return str(int(value))
        return str(value)
    return str(value)


def autostart_has_hyprsunset(text: str) -> bool:
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("--"):
            continue
        if 'launch_on_start("hyprsunset")' in s or "launch_on_start('hyprsunset')" in s:
            return True
    return False


def set_autostart_hyprsunset(enabled: bool) -> None:
    text = AUTOSTART.read_text(encoding="utf-8") if AUTOSTART.is_file() else "-- Extra autostart processes.\n"
    lines = text.splitlines()
    kept = []
    for line in lines:
        s = line.strip()
        if 'launch_on_start("hyprsunset")' in s or "launch_on_start('hyprsunset')" in s:
            continue
        kept.append(line)
    if enabled:
        kept.append('o.launch_on_start("hyprsunset")')
    body = "\n".join(kept).rstrip() + "\n"
    backup(AUTOSTART)
    write_atomic(AUTOSTART, body)


def get_hyprsunset() -> dict:
    out = dict(HYPRSUNSET_DEFAULTS)
    text = HYPRSUNSET.read_text(encoding="utf-8") if HYPRSUNSET.is_file() else ""
    profiles = parse_blocks(text, "profile")
    day = None
    night = None
    for p in profiles:
        if p.get("identity") is True:
            day = p
        elif "temperature" in p or p.get("identity") is False:
            night = p
        elif day is None:
            day = p
        else:
            night = p
    if day and day.get("time") is not None:
        out["dayTime"] = str(day["time"])
    if night:
        out["nightEnabled"] = True
        if night.get("time") is not None:
            out["nightTime"] = str(night["time"])
        if night.get("temperature") is not None:
            out["temperature"] = int(night["temperature"])
        if night.get("gamma") is not None:
            out["gamma"] = float(night["gamma"])
    if AUTOSTART.is_file():
        out["launchOnStart"] = autostart_has_hyprsunset(AUTOSTART.read_text(encoding="utf-8"))
    out["customPresent"] = CUSTOM_BEGIN in text
    return out


def render_hyprsunset(settings: dict, custom: str) -> str:
    day = str(settings.get("dayTime") or "07:00")
    night_enabled = bool(settings.get("nightEnabled"))
    night = str(settings.get("nightTime") or "20:00")
    temp = int(settings.get("temperature") or 4000)
    gamma = settings.get("gamma")

    lines = [
        "# Managed by cesosag.settings.",
        "# Custom lines are preserved below the marker.",
        "",
        "profile {",
        f"    time = {day}",
        "    identity = true",
        "}",
        "",
    ]
    if night_enabled:
        lines.append("profile {")
        lines.append(f"    time = {night}")
        lines.append(f"    temperature = {temp}")
        if gamma is not None and gamma != "":
            lines.append(f"    gamma = {conf_literal(gamma)}")
        lines.append("}")
        lines.append("")
    return "\n".join(lines) + wrap_custom(custom)


def set_hyprsunset(payload: dict) -> None:
    text = HYPRSUNSET.read_text(encoding="utf-8") if HYPRSUNSET.is_file() else ""
    custom = extract_custom(text)
    settings = dict(HYPRSUNSET_DEFAULTS)
    for key in HYPRSUNSET_DEFAULTS:
        if key in payload and payload[key] is not None:
            settings[key] = payload[key]
    if "gamma" in payload:
        settings["gamma"] = payload.get("gamma")
    backup(HYPRSUNSET)
    write_atomic(HYPRSUNSET, render_hyprsunset(settings, custom))
    if "launchOnStart" in payload:
        set_autostart_hyprsunset(bool(payload.get("launchOnStart")))
    subprocess.run(["omarchy", "restart", "hyprsunset"], capture_output=True, check=False)
    print("hyprsunset updated")


def get_xdph() -> dict:
    out = dict(XDPH_DEFAULTS)
    text = XDPH.read_text(encoding="utf-8") if XDPH.is_file() else ""
    blocks = parse_blocks(text, "screencopy")
    if blocks:
        out.update({k: blocks[0][k] for k in blocks[0]})
    out["customPresent"] = CUSTOM_BEGIN in text
    return out


def render_xdph(settings: dict, custom: str) -> str:
    allow = bool(settings.get("allow_token_by_default", True))
    picker = str(settings.get("custom_picker_binary") or "hyprland-preview-share-picker")
    body = (
        "# Managed by cesosag.settings.\n"
        "# Custom lines are preserved below the marker.\n"
        "\n"
        "screencopy {\n"
        f"    allow_token_by_default = {conf_literal(allow)}\n"
        f"    custom_picker_binary = {picker}\n"
        "}\n"
    )
    return body + wrap_custom(custom)


def set_xdph(payload: dict) -> None:
    text = XDPH.read_text(encoding="utf-8") if XDPH.is_file() else ""
    custom = extract_custom(text)
    settings = dict(XDPH_DEFAULTS)
    for key in XDPH_DEFAULTS:
        if key in payload and payload[key] is not None:
            settings[key] = payload[key]
    backup(XDPH)
    write_atomic(XDPH, render_xdph(settings, custom))
    print("xdph updated (applies on next portal restart / login)")
