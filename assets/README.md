# Spectre Suite visual assets

This folder holds README/marketing visuals.

## Current assets

| File | Type | Notes |
|---|---|---|
| `spectre-suite-banner.svg` | SVG banner | Hero banner used by the root README. Safe to edit/replace. |
| `monitoring-preview.svg` | SVG illustration | Illustrative monitoring/dispatch preview. |
| `spectre-cli-help.png` | PNG screenshot | Locally rendered terminal capture of `spectre --help`. |
| `spectre-actions-list.png` | PNG screenshot | Locally rendered terminal capture of `spectre actions list`. |
| `spectre-actions-verify.png` | PNG screenshot | Locally rendered terminal capture of `spectre actions verify` (dark). |
| `spectre-actions-show.png` | PNG screenshot | Locally rendered terminal capture of `spectre actions show backups/backup-all`. |
| `spectre-actions-verify-light.png` | PNG screenshot | Light-theme sample from the generator. |
| `render_terminal_screenshots.py` | Script | Regenerates terminal PNGs from real `spectre` output (themes, ANSI/plain modes, selectable commands). |

## Regenerate terminal screenshots

The terminal PNGs are rendered locally from live `spectre` output (Pillow, monospace font, no browser required):

```bash
# from repo root
python3 assets/render_terminal_screenshots.py

# all known captures
python3 assets/render_terminal_screenshots.py --commands all

# themes / variants
python3 assets/render_terminal_screenshots.py --theme dark --theme light --suffix-theme
python3 assets/render_terminal_screenshots.py --theme nord --color ansi --commands help,verify --suffix-theme

# custom output / width / font
python3 assets/render_terminal_screenshots.py --out assets --columns 110
python3 assets/render_terminal_screenshots.py --font /usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf
```

Available command keys: `help`, `list`, `verify`, `show`, `run-help`, `all`.  
Modes/themes: `--color plain|ansi`, `--theme dark|light|nord` (repeatable).

Requirements: Python 3, Pillow, and a monospace font (DejaVu Sans Mono / Noto Sans Mono / Liberation Mono). Review generated images before committing — terminal captures can include host-specific paths or names.

## Capture real browser/dashboard screenshots (running desktop/browser session)

Use these when the monitoring stack is running locally and you want **real Grafana/Alertmanager/UI** screenshots. Always use a clean/redacted environment first.

### 1. Prepare a safe capture target

```bash
# start stack (credentials required; see README)
docker compose -f docker-compose.monitoring.yml up -d
```

Before capturing: log in with a non-production/demo view if possible, hide sensitive panels, avoid showing webhook URLs/tokens, private IPs, hostnames, emails, API keys, or customer data. Crop/redact after capture.

### 2. Headless browser capture (scriptable)

Chrome/Chromium can capture local pages without a full desktop workflow:

```bash
# Grafana (adjust port/path; authenticate first if needed, or capture a safe public view)
google-chrome --headless=new --disable-gpu --window-size=1600,1000 \
  --screenshot=assets/grafana-overview.png \
  "http://localhost:3002/"

# Alertmanager
google-chrome --headless=new --disable-gpu --window-size=1600,1000 \
  --screenshot=assets/alertmanager-routes.png \
  "http://localhost:9093/"
```

Notes:
- Authenticated pages may screenshot the login screen in headless mode. For authenticated dashboards, prefer a desktop session, a temporary read-only demo user, or a pre-authenticated browser profile used only for safe captures.
- Replace `google-chrome` with `chromium`, `google-chrome-stable`, or your local binary.

### 3. Desktop capture (interactive, best for authenticated dashboards)

| Environment | Tools / commands |
|---|---|
| **X11** | `maim -s assets/grafana-overview.png` (select region), `scrot assets/grafana-overview.png`, Flameshot (`flameshot gui`) |
| **Wayland (GNOME)** | `gnome-screenshot -a -f assets/grafana-overview.png`, or Screenshot app |
| **Wayland (KDE)** | Spectacle (region/window capture) |
| **Wayland (wlroots/Sway)** | `grim -g "$(slurp)" assets/grafana-overview.png` |
| **Cross-desktop** | Flameshot (`flameshot gui`) where supported; browser DevTools “Capture screenshot” for full-page captures |

Tips:
- Use a consistent window size (e.g., 1600×1000) for README images.
- Prefer PNG. Crop tightly to the relevant panel/terminal/dashboard.
- Re-run `python3 assets/render_terminal_screenshots.py` after CLI/output changes so README terminal screenshots stay truthful.

## Recommended filenames

1. `grafana-overview.png` — Grafana home/dashboard view (redacted).
2. `alertmanager-routes.png` — Alertmanager UI (redacted).
3. `grafana-dashboard-<name>.png` — specific dashboard panels (redacted).

**Safety:** never commit secrets, API keys, webhook URLs, private IPs you don’t want published, emails, tokens, or customer data.
