#!/usr/bin/env python3
"""Render Spectre Suite README terminal screenshots locally.

This generates PNG "terminal" snapshots from real `spectre` command output using
Pillow. It is intentionally small and headless-friendly.

Usage:
  python3 assets/render_terminal_screenshots.py
  python3 assets/render_terminal_screenshots.py --out assets --columns 110

Requirements:
  - Python 3
  - Pillow (`python3 -c 'import PIL'`)
  - A monospace font (DejaVu Sans Mono or Noto Sans Mono recommended)

Notes:
  - Output is derived from live command output in this checkout.
  - Review generated images before committing; while terminal output usually has
    no secrets, host-specific paths/config may appear.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
FONT_CANDIDATES = [
    "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/google-noto/NotoSansMono-Regular.ttf",
    "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
]
BG = (15, 23, 42)
PANEL = (2, 6, 23)
BORDER = (51, 65, 85)
FG = (226, 232, 240)
DIM = (148, 163, 184)
ACCENT = (34, 211, 238)
GREEN = (74, 222, 128)
AMBER = (251, 191, 36)
DOTS = [(251, 113, 133), (251, 191, 36), (52, 211, 153)]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return path
    raise SystemExit(
        "No supported monospace font found. Install DejaVu Sans Mono/Noto Sans Mono "
        "or add a path to FONT_CANDIDATES."
    )


def run_capture(args: list[str], columns: int, max_lines: int) -> list[str]:
    env = os.environ.copy()
    env.update({"NO_COLOR": "1", "COLUMNS": str(columns), "TERM": "dumb"})
    proc = subprocess.run(args, capture_output=True, text=True, env=env, check=False)
    text = proc.stdout or proc.stderr or ""
    text = ANSI_RE.sub("", text)
    lines = [line.rstrip() for line in text.splitlines()]
    while lines and not lines[-1].strip():
        lines.pop()
    if proc.returncode != 0 and not lines:
        lines = [f"$ {' '.join(args)}", f"(command exited {proc.returncode})"]
    return lines[:max_lines]


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont) -> tuple[int, int]:
    bbox = draw.textbbox((0, 0), text, font=font)
    return bbox[2] - bbox[0], bbox[3] - bbox[1]


def render_terminal(
    title: str,
    lines: list[str],
    out_path: Path,
    font_path: str,
    font_size: int = 18,
    highlight_rules: list[tuple] | None = None,
) -> None:
    highlight_rules = highlight_rules or []
    font = ImageFont.truetype(font_path, font_size)
    title_font = ImageFont.truetype(font_path, max(14, font_size - 2))
    dummy = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    cw, ch = text_size(dummy, "M", font)
    pad_x, pad_y, top_bar = 28, 24, 46
    max_cols = min(max((len(line) for line in lines), default=40), 120)
    max_cols = max(max_cols, len(title) + 8)
    width = pad_x * 2 + cw * max_cols + 20
    height = top_bar + pad_y * 2 + ch * max(len(lines), 1) + 16

    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([14, 14, width - 14, height - 14], radius=14, fill=PANEL, outline=BORDER)
    for i, color in enumerate(DOTS):
        x = 36 + i * 24
        draw.ellipse([x - 7, 23, x + 7, 37], fill=color)
    draw.text((110, 21), title, font=title_font, fill=DIM)

    y = top_bar + pad_y - 4
    for line in lines:
        color = FG
        for predicate, picked in highlight_rules:
            if predicate(line):
                color = picked
                break
        draw.text((pad_x + 8, y), line, font=font, fill=color)
        y += ch

    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"wrote {out_path} ({width}x{height}, {len(lines)} lines)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="assets", help="Output directory (default: assets)")
    parser.add_argument("--columns", type=int, default=110, help="COLUMNS for command capture")
    parser.add_argument("--font", default=None, help="Path to a monospace .ttf font")
    parser.add_argument("--font-size", type=int, default=18)
    args = parser.parse_args()

    out = Path(args.out)
    font = args.font or find_font()
    py = os.environ.get("PYTHON", "python3")

    captures = [
        {
            "title": "spectre --help  ·  Spectre Suite",
            "cmd": [py, "-m", "spectre.cli.main", "--help"],
            "max_lines": 26,
            "file": "spectre-cli-help.png",
            "rules": [
                (lambda s: s.strip().startswith("Usage:"), ACCENT),
                (lambda s: "╭" in s or "╰" in s or "│ --" in s, DIM),
                (lambda s: any(k in s for k in ("│ run ", "│ actions ", "│ doctor ", "│ security ", "│ backup ")), GREEN),
            ],
        },
        {
            "title": "spectre actions list  ·  registry view",
            "cmd": [py, "-m", "spectre.cli.main", "actions", "list"],
            "max_lines": 22,
            "file": "spectre-actions-list.png",
            "rules": [
                (lambda s: s.startswith("job "), ACCENT),
                (lambda s: "backup" in s and not s.startswith("job"), (125, 211, 252)),
                (lambda s: "maintenance" in s, (167, 243, 208)),
                (lambda s: "security" in s or "deploy" in s, (253, 230, 138)),
            ],
        },
        {
            "title": "spectre actions verify  ·  truth gate",
            "cmd": [py, "-m", "spectre.cli.main", "actions", "verify"],
            "max_lines": 24,
            "file": "spectre-actions-verify.png",
            "rules": [
                (lambda s: s.startswith("actions root") or s.startswith("registry:"), ACCENT),
                (lambda s: "advisory" in s, AMBER),
                (lambda s: s.strip().endswith(" 0") and any(k in s for k in ("missing", "executable", "syntax", "mutation", "duplicate")), GREEN),
                (lambda s: "legacy-path" in s and s.rstrip().endswith("1"), AMBER),
            ],
        },
    ]

    for item in captures:
        lines = run_capture(item["cmd"], args.columns, item["max_lines"])
        render_terminal(item["title"], lines, out / item["file"], font, args.font_size, item["rules"])


if __name__ == "__main__":
    main()
