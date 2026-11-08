#!/usr/bin/env python3
"""Render Spectre Suite README terminal screenshots locally.

Generates PNG "terminal" snapshots from real `spectre` command output using
Pillow. Headless-friendly; no browser required.

Usage:
  python3 assets/render_terminal_screenshots.py
  python3 assets/render_terminal_screenshots.py --theme dark --theme light
  python3 assets/render_terminal_screenshots.py --color ansi --theme dark
  python3 assets/render_terminal_screenshots.py --commands help,verify,show --out assets

Requirements:
  - Python 3
  - Pillow (`python3 -c 'import PIL'`)
  - A monospace font (DejaVu Sans Mono / Noto Sans Mono recommended)

Notes:
  - Output is derived from live command output in this checkout.
  - Review generated images before committing; captures can include host-specific
    paths/names. Never commit secrets.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ANSI_RE = re.compile(r"\x1b\[([0-9;]*)m")
FONT_CANDIDATES = [
    "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/google-noto/NotoSansMono-Regular.ttf",
    "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
]
BOLD_FONT_CANDIDATES = [p.replace("Regular", "Bold").replace(".ttf", "-Bold.ttf") for p in FONT_CANDIDATES]

ANSI16 = {
    30: (15, 23, 42), 31: (248, 113, 113), 32: (74, 222, 128), 33: (251, 191, 36),
    34: (96, 165, 250), 35: (167, 139, 250), 36: (34, 211, 238), 37: (226, 232, 240),
    90: (148, 163, 184), 91: (252, 165, 165), 92: (134, 239, 172), 93: (253, 230, 138),
    94: (147, 197, 253), 95: (196, 181, 253), 96: (103, 232, 249), 97: (248, 250, 252),
}


@dataclass
class Theme:
    name: str
    bg: tuple[int, int, int]
    panel: tuple[int, int, int]
    border: tuple[int, int, int]
    fg: tuple[int, int, int]
    dim: tuple[int, int, int]
    accent: tuple[int, int, int]
    green: tuple[int, int, int]
    amber: tuple[int, int, int]
    dots: list[tuple[int, int, int]]


THEMES = {
    "dark": Theme("dark", (15, 23, 42), (2, 6, 23), (51, 65, 85), (226, 232, 240), (148, 163, 184), (34, 211, 238), (74, 222, 128), (251, 191, 36), [(251, 113, 133), (251, 191, 36), (52, 211, 153)]),
    "light": Theme("light", (241, 245, 249), (255, 255, 255), (203, 213, 225), (15, 23, 42), (71, 85, 105), (2, 132, 199), (22, 163, 74), (217, 119, 6), [(239, 68, 68), (245, 158, 11), (34, 197, 94)]),
    "nord": Theme("nord", (46, 52, 64), (59, 66, 82), (76, 86, 106), (236, 239, 244), (216, 222, 233), (136, 192, 208), (163, 190, 140), (235, 203, 139), [(191, 97, 106), (235, 203, 139), (163, 190, 140)]),
}


def find_font(candidates: list[str]) -> str | None:
    for path in candidates:
        if Path(path).exists():
            return path
    return None


def run_capture(args: list[str], columns: int, max_lines: int, keep_ansi: bool) -> str:
    env = os.environ.copy()
    env.update({"COLUMNS": str(columns), "TERM": "xterm-256color" if keep_ansi else "dumb"})
    if keep_ansi:
        env.update({"FORCE_COLOR": "1", "CLICOLOR_FORCE": "1"})
        env.pop("NO_COLOR", None)
    else:
        env.update({"NO_COLOR": "1"})
        env.pop("FORCE_COLOR", None)
    proc = subprocess.run(args, capture_output=True, text=True, env=env, check=False)
    text = proc.stdout or proc.stderr or ""
    if not keep_ansi:
        text = ANSI_RE.sub("", text)
    lines = text.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    if proc.returncode != 0 and not lines:
        return f"$ {' '.join(args)}\n(command exited {proc.returncode})"
    return "\n".join(lines[:max_lines])


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text or " ", font=font)
    return max(1, bbox[2] - bbox[0]), max(1, bbox[3] - bbox[1])


def draw_plain_line(draw, x, y, line, font, theme, rules):
    color = theme.fg
    for predicate, picked in rules:
        if predicate(line):
            color = picked
            break
    draw.text((x, y), line, font=font, fill=color)


def draw_ansi_line(draw, x, y, line, font, theme, cw):
    # Minimal SGR parser: reset, bold/dim, standard 16 foreground colors.
    pos = x
    fg = theme.fg
    dim = False
    i = 0
    while i < len(line):
        m = ANSI_RE.match(line, i)
        if m:
            codes = [c for c in m.group(1).split(";") if c != ""]
            if not codes:
                codes = ["0"]
            for c in codes:
                n = int(c)
                if n == 0:
                    fg, dim = theme.fg, False
                elif n == 1:
                    dim = False
                elif n == 2:
                    dim = True
                elif n in ANSI16:
                    fg = ANSI16[n]
                elif n == 39:
                    fg = theme.fg
            i = m.end()
            continue
        ch = line[i]
        color = tuple(int(v * 0.72) for v in fg) if dim else fg
        draw.text((pos, y), ch, font=font, fill=color)
        pos += cw
        i += 1


def render_terminal(title, text, out_path: Path, theme: Theme, font_path: str, font_size: int, mode: str, rules):
    font = ImageFont.truetype(font_path, font_size)
    title_font = ImageFont.truetype(font_path, max(14, font_size - 2))
    lines = text.splitlines() or [""]
    plain_lines = [ANSI_RE.sub("", l) for l in lines]
    dummy = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    cw, ch = text_size(dummy, "M", font)
    pad_x, pad_y, top_bar = 28, 24, 46
    max_cols = min(max((len(l) for l in plain_lines), default=40), 120)
    max_cols = max(max_cols, len(title) + 8)
    width = pad_x * 2 + cw * max_cols + 20
    height = top_bar + pad_y * 2 + ch * max(len(lines), 1) + 16
    img = Image.new("RGB", (width, height), theme.bg)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([14, 14, width - 14, height - 14], radius=14, fill=theme.panel, outline=theme.border)
    for i, color in enumerate(theme.dots):
        x = 36 + i * 24
        draw.ellipse([x - 7, 23, x + 7, 37], fill=color)
    draw.text((110, 21), title, font=title_font, fill=theme.dim)
    y = top_bar + pad_y - 4
    for raw, plain in zip(lines, plain_lines):
        if mode == "ansi" and "\x1b[" in raw:
            draw_ansi_line(draw, pad_x + 8, y, raw, font, theme, cw)
        else:
            draw_plain_line(draw, pad_x + 8, y, plain, font, theme, rules)
        y += ch
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"wrote {out_path} ({theme.name}, {width}x{height})")


def command_specs(py: str) -> dict[str, dict]:
    return {
        "help": {"title": "spectre --help  ·  Spectre Suite", "cmd": [py, "-m", "spectre.cli.main", "--help"], "max_lines": 26, "file": "spectre-cli-help", "rules": [(lambda s: s.strip().startswith("Usage:"), "accent"), (lambda s: "╭" in s or "╰" in s or "│ --" in s, "dim"), (lambda s: any(k in s for k in ("│ run ", "│ actions ", "│ doctor ", "│ security ", "│ backup ")), "green")]},
        "list": {"title": "spectre actions list  ·  registry view", "cmd": [py, "-m", "spectre.cli.main", "actions", "list"], "max_lines": 22, "file": "spectre-actions-list", "rules": [(lambda s: s.startswith("job "), "accent"), (lambda s: "backup" in s and not s.startswith("job"), "accent"), (lambda s: "maintenance" in s, "green"), (lambda s: "security" in s or "deploy" in s, "amber")]},
        "verify": {"title": "spectre actions verify  ·  truth gate", "cmd": [py, "-m", "spectre.cli.main", "actions", "verify"], "max_lines": 24, "file": "spectre-actions-verify", "rules": [(lambda s: s.startswith("actions root") or s.startswith("registry:"), "accent"), (lambda s: "advisory" in s, "amber"), (lambda s: s.strip().endswith(" 0") and any(k in s for k in ("missing", "executable", "syntax", "mutation", "duplicate")), "green"), (lambda s: "legacy-path" in s and s.rstrip().endswith("1"), "amber")]},
        "show": {"title": "spectre actions show  ·  job metadata", "cmd": [py, "-m", "spectre.cli.main", "actions", "show", "backups/backup-all"], "max_lines": 18, "file": "spectre-actions-show", "rules": [(lambda s: s.startswith("job:"), "accent"), (lambda s: s.startswith("resolved:"), "dim"), (lambda s: "mutates:" in s or "sudo:" in s, "amber"), (lambda s: "schedule:" in s or "replaces:" in s, "green")]},
        "run-help": {"title": "spectre run --help  ·  dispatch args", "cmd": [py, "-m", "spectre.cli.main", "run", "--help"], "max_lines": 16, "file": "spectre-run-help", "rules": [(lambda s: s.strip().startswith("Usage:"), "accent"), (lambda s: "spectre run" in s, "green"), (lambda s: "exit 64" in s, "amber")]},
    }


def resolve_rules(theme: Theme, rules):
    out = []
    for pred, key in rules:
        color = getattr(theme, key, theme.fg) if isinstance(key, str) else key
        out.append((pred, color))
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets", help="Output directory")
    parser.add_argument("--columns", type=int, default=110)
    parser.add_argument("--font", default=None)
    parser.add_argument("--font-size", type=int, default=18)
    parser.add_argument("--theme", action="append", choices=sorted(THEMES), help="Theme(s): dark, light, nord. Repeatable.")
    parser.add_argument("--color", choices=["plain", "ansi"], default="plain", help="plain=rule highlighting; ansi=capture/render basic ANSI colors")
    parser.add_argument("--commands", default="help,list,verify", help="Comma-separated: help,list,verify,show,run-help,all")
    parser.add_argument("--suffix-theme", action="store_true", help="Add -dark/-light/-nord suffix to filenames")
    args = parser.parse_args()

    themes = [THEMES[t] for t in (args.theme or ["dark"])]
    font = args.font or find_font(FONT_CANDIDATES)
    if not font:
        raise SystemExit("No supported monospace font found; pass --font /path/to/Mono.ttf")
    py = os.environ.get("PYTHON", "python3")
    specs = command_specs(py)
    selected = list(specs.keys()) if args.commands.strip().lower() == "all" else [c.strip() for c in args.commands.split(",") if c.strip()]
    unknown = [c for c in selected if c not in specs]
    if unknown:
        raise SystemExit(f"Unknown commands: {unknown}. Available: {', '.join(specs)} or all")

    out = Path(args.out)
    keep_ansi = args.color == "ansi"
    for theme in themes:
        for key in selected:
            spec = specs[key]
            text = run_capture(spec["cmd"], args.columns, spec["max_lines"], keep_ansi)
            name = spec["file"] + (f"-{theme.name}" if args.suffix_theme or len(themes) > 1 else "") + ".png"
            render_terminal(spec["title"], text, out / name, theme, font, args.font_size, args.color, resolve_rules(theme, spec["rules"]))


if __name__ == "__main__":
    main()
