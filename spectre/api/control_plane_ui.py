"""Enterprise Spectre control-plane dashboard UI (single-file HTML)."""

CONTROL_PLANE_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SPECTRE CONTROL PLANE — Security Observability</title>
  <style>
    :root {
      --nav: #111827; --nav-2: #1f2937; --nav-fg: #e5eef8; --nav-muted: #9fb3c8; --nav-active: #2563eb;
      --bg: #f3f6fb; --surface: #ffffff; --surface-2: #f8fafc; --line: #dbe4ee; --line-soft: #e8eef5;
      --fg: #0f172a; --muted: #526277; --subtle: #6b7280; --accent: #2563eb; --accent-bg: #e8f0ff;
      --ok: #15803d; --ok-bg: #eaf7ef; --ok-br: #bfe3cb;
      --warn: #b45309; --warn-bg: #fff6e8; --warn-br: #f2ddb3;
      --crit: #dc2626; --crit-bg: #fdecec; --crit-br: #f3b7b7;
      --unknown: #475569; --unknown-bg: #eef2f6; --unknown-br: #cfd8e3;
      --focus: #3b82f6; --radius: 12px; --radius-sm: 8px; --shadow: 0 1px 2px rgba(15,23,42,.05), 0 8px 24px rgba(15,23,42,.04);
      --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      --sans: Inter, ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; background: var(--bg); color: var(--fg); font: 13px/1.5 var(--sans); }
    a { color: var(--accent); text-decoration: none; } a:hover { text-decoration: underline; }
    :focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
    .nav a:focus-visible, button:focus-visible, input:focus-visible, select:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
    .skip { position: absolute; left: -9999px; } .skip:focus { left: 12px; top: 12px; z-index: 50; background: var(--surface); padding: 8px 10px; border-radius: 8px; box-shadow: var(--shadow); }
    .app { display: grid; grid-template-columns: 248px 1fr; min-height: 100vh; }
    @media (max-width: 980px) { .app { grid-template-columns: 1fr; } .sidebar { position: static; min-height: auto; } }
    .sidebar { background: linear-gradient(180deg, var(--nav) 0%, #0b1220 100%); color: var(--nav-fg); padding: 18px 14px; position: sticky; top: 0; min-height: 100vh; display: flex; flex-direction: column; gap: 14px; }
    .brand { padding: 4px 8px 10px; border-bottom: 1px solid rgba(255,255,255,.08); }
    .brand-mark { display: flex; align-items: center; gap: 10px; }
    .logo { width: 34px; height: 34px; border-radius: 10px; background: linear-gradient(135deg, #2563eb, #60a5fa); display: grid; place-items: center; font: 700 13px/1 var(--mono); color: #fff; box-shadow: 0 8px 18px rgba(37,99,235,.35); }
    .brand h1 { margin: 0; font: 700 13px/1.15 var(--sans); letter-spacing: .08em; }
    .brand p { margin: 3px 0 0; color: var(--nav-muted); font-size: 11px; }
    .nav-group { display: grid; gap: 2px; }
    .nav-label { padding: 8px 10px 4px; color: #7f95ad; font: 600 10px/1 var(--sans); letter-spacing: .08em; text-transform: uppercase; }
    .nav a { display: flex; align-items: center; gap: 10px; padding: 9px 10px; border-radius: 8px; color: var(--nav-fg); font-size: 13px; }
    .nav a:hover { background: rgba(255,255,255,.06); text-decoration: none; }
    .nav a.active { background: rgba(37,99,235,.18); color: #fff; box-shadow: inset 0 0 0 1px rgba(96,165,250,.18); }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: #6b86a3; flex: 0 0 auto; }
    .nav a.active .dot { background: #60a5fa; }
    .sidebar-foot { margin-top: auto; padding: 10px; border: 1px solid rgba(255,255,255,.08); border-radius: 10px; background: rgba(255,255,255,.03); color: var(--nav-muted); font-size: 11px; }
    .shell { min-width: 0; }
    .topbar { position: sticky; top: 0; z-index: 20; background: rgba(243,246,251,.86); backdrop-filter: blur(10px); border-bottom: 1px solid var(--line); }
    .topbar-inner { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 22px; }
    .page-title h2 { margin: 0; font: 700 18px/1.2 var(--sans); letter-spacing: -.01em; }
    .page-title p { margin: 2px 0 0; color: var(--muted); font-size: 12px; }
    .toolbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    button, input, select { font: inherit; color: var(--fg); background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 8px 11px; }
    button { cursor: pointer; box-shadow: 0 1px 0 rgba(15,23,42,.02); } button:hover { border-color: #c6d3e1; }
    button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
    button.primary:hover { filter: brightness(1.03); }
    .stamp { color: var(--subtle); font-size: 12px; }
    main { padding: 18px 22px 28px; display: grid; gap: 16px; }
    .banner { padding: 12px 14px; border: 1px solid #cfe0ff; background: linear-gradient(180deg, #f3f8ff, #edf4ff); color: #294766; border-radius: var(--radius-sm); font-size: 12px; }
    .kpis { display: grid; gap: 12px; grid-template-columns: repeat(4, minmax(0, 1fr)); }
    @media (max-width: 1200px) { .kpis { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
    @media (max-width: 640px) { .kpis { grid-template-columns: 1fr; } .topbar-inner { flex-direction: column; align-items: stretch; } }
    .panel { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
    .panel-h { padding: 14px 16px; border-bottom: 1px solid var(--line-soft); display: flex; align-items: center; justify-content: space-between; gap: 10px; }
    .panel-h h3 { margin: 0; font: 650 13px/1.2 var(--sans); color: var(--fg); }
    .panel-h .hint { color: var(--subtle); font-size: 12px; }
    .panel-b { padding: 16px; }
    .kpi { padding: 16px; }
    .kpi-label { color: var(--muted); font-size: 12px; font-weight: 600; }
    .kpi-value { margin-top: 8px; font: 700 28px/1.05 var(--mono); color: var(--fg); font-variant-numeric: tabular-nums; }
    .kpi-sub { margin-top: 8px; color: var(--subtle); font-size: 12px; }
    .grid-2 { display: grid; gap: 16px; grid-template-columns: 1.2fr .8fr; }
    @media (max-width: 1100px) { .grid-2 { grid-template-columns: 1fr; } }
    .status { display: inline-flex; align-items: center; gap: 6px; padding: 3px 9px; border-radius: 999px; font: 650 11px/1.5 var(--sans); border: 1px solid var(--unknown-br); background: var(--unknown-bg); color: var(--unknown); white-space: nowrap; text-transform: lowercase; letter-spacing: .01em; }
    .status::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
    .s-ok { color: var(--ok); background: var(--ok-bg); border-color: var(--ok-br); }
    .s-warn, .s-degraded { color: var(--warn); background: var(--warn-bg); border-color: var(--warn-br); }
    .s-crit, .s-error, .s-failed { color: var(--crit); background: var(--crit-bg); border-color: var(--crit-br); }
    .s-unknown { color: var(--unknown); background: var(--unknown-bg); border-color: var(--unknown-br); }
    .mono { font-family: var(--mono); }
    .muted { color: var(--muted); }
    .table-wrap { overflow: auto; border: 1px solid var(--line); border-radius: 10px; background: var(--surface); }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th, td { padding: 11px 12px; border-bottom: 1px solid var(--line-soft); text-align: left; vertical-align: top; }
    th { background: var(--surface-2); color: #475569; font: 650 11px/1.2 var(--sans); letter-spacing: .04em; text-transform: uppercase; white-space: nowrap; position: sticky; top: 0; }
    tr:last-child td { border-bottom: 0; }
    tbody tr:hover { background: #f7faff; }
    .filters { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 12px; }
    .filters input[type="search"] { border-radius: 10px; }
    .mono { font-variant-numeric: tabular-nums; }
    @media (max-width: 640px) { .panel-h { flex-wrap: wrap; } .list-row { flex-direction: column; gap: 8px; } .list-row > div:last-child { text-align: left !important; } }
    .filters input[type="search"] { flex: 1; min-width: 240px; }
    pre { margin: 0; padding: 12px; background: #0f172a; color: #dbe7f3; border-radius: 10px; font: 12px/1.45 var(--mono); white-space: pre-wrap; word-break: break-word; max-height: 320px; overflow: auto; }
    .list { display: grid; }
    .list-row { display: flex; justify-content: space-between; gap: 14px; align-items: flex-start; padding: 12px 0; border-bottom: 1px solid var(--line-soft); }
    .list-row:first-child { padding-top: 0; } .list-row:last-child { border-bottom: 0; padding-bottom: 0; }
    .errbox { padding: 12px 14px; border-radius: 10px; border: 1px solid var(--crit-br); background: var(--crit-bg); color: #991b1b; font-size: 12px; }
    .empty { color: var(--subtle); font-size: 12px; padding: 8px 0; }
    .section-anchor { scroll-margin-top: 84px; }
  </style>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <div class="app">
    <aside class="sidebar" aria-label="Primary navigation">
      <div class="brand">
        <div class="brand-mark">
          <div class="logo" aria-hidden="true">S</div>
          <div>
            <h1>SPECTRE CONTROL PLANE</h1>
            <p>Security &amp; operations observability</p>
          </div>
        </div>
      </div>
      <nav class="nav">
        <div class="nav-group">
          <div class="nav-label">Monitor</div>
          <a href="#overview" class="active"><span class="dot"></span>Overview</a>
          <a href="#findings"><span class="dot"></span>Findings &amp; Verification</a>
          <a href="#components"><span class="dot"></span>Components</a>
        </div>
        <div class="nav-group">
          <div class="nav-label">Operations</div>
          <a href="#actions"><span class="dot"></span>Actions Registry</a>
          <a href="#runs"><span class="dot"></span>Run History</a>
          <a href="#backup"><span class="dot"></span>Backup &amp; State</a>
        </div>
      </nav>
      <div class="sidebar-foot">
        <div><strong>Read-only dashboard.</strong></div>
        <div style="margin-top:4px">Execute actions from an authorized terminal: <span class="mono">spectre run &lt;job&gt;</span></div>
      </div>
    </aside>

    <div class="shell">
      <header class="topbar">
        <div class="topbar-inner">
          <div class="page-title">
            <h2>Security Overview</h2>
            <p>Dispatch health, monitoring reachability, verification findings, and recent run history. Data via <span class="mono">/api/control-plane/overview</span>.</p>
          </div>
          <div class="toolbar" role="toolbar" aria-label="Dashboard controls">
            <button type="button" onclick="setKey()">API Key</button>
            <button type="button" class="primary" onclick="refreshAll()">Refresh</button>
            <span id="stamp" class="stamp" aria-live="polite">Not loaded</span>
          </div>
        </div>
      </header>

      <main id="main">
        <div class="banner" role="note"><strong>Observability only.</strong> This control-plane view surfaces health, dispatch state, monitoring reachability, backup markers, and run history. It does not execute actions. Use <span class="mono">python -m spectre.cli.main run &lt;job&gt;</span> from an authorized terminal session.</div>

        <section id="overview" class="kpis section-anchor" aria-label="Key indicators">
          <div class="panel kpi"><div class="kpi-label">Control Status</div><div id="kpiHealth" class="kpi-value muted">—</div><div id="kpiHealthSub" class="kpi-sub">Waiting for data</div></div>
          <div class="panel kpi"><div class="kpi-label">Dispatch Registry</div><div id="kpiJobs" class="kpi-value" style="color:var(--accent)">—</div><div id="kpiJobsSub" class="kpi-sub">Jobs / groups</div></div>
          <div class="panel kpi"><div class="kpi-label">Monitoring Reachability</div><div id="kpiMon" class="kpi-value muted">—</div><div id="kpiMonSub" class="kpi-sub">Probed endpoints</div></div>
          <div class="panel kpi"><div class="kpi-label">Recent Runs</div><div id="kpiRuns" class="kpi-value muted">—</div><div id="kpiRunsSub" class="kpi-sub">History window</div></div>
        </section>

        <section id="findings" class="grid-2 section-anchor">
          <div id="components" class="panel">
            <div class="panel-h"><h3>Monitored Components</h3><span id="compCount" class="hint"></span></div>
            <div class="panel-b"><div id="componentsBody" class="list"><div class="empty">Loading…</div></div></div>
          </div>
          <div class="panel">
            <div class="panel-h"><h3>Dispatch Verification</h3><span class="hint">Blocking/advisory findings</span></div>
            <div class="panel-b"><pre id="findingsBody">Loading…</pre></div>
          </div>
        </section>

        <section id="actions" class="panel section-anchor">
          <div class="panel-h"><h3>Actions Registry</h3><span class="hint">Reference only — no execution from UI</span></div>
          <div class="panel-b">
            <div class="filters">
              <input id="q" type="search" placeholder="Search by name, group, summary, or action…" oninput="renderActions()" aria-label="Filter actions" />
              <select id="group" onchange="renderActions()" aria-label="Filter by group"><option value="">All groups</option></select>
              <label class="muted"><input type="checkbox" id="mutOnly" onchange="renderActions()" /> Mutating/sudo only</label>
            </div>
            <div class="table-wrap"><table aria-label="Dispatch actions registry">
              <thead><tr><th>Job</th><th>Group</th><th>Properties</th><th>Schedule</th><th>Summary</th><th>Terminal command</th></tr></thead>
              <tbody id="actionsBody"><tr><td colspan="6" class="empty">Loading…</td></tr></tbody>
            </table></div>
          </div>
        </section>

        <section id="runs" class="grid-2 section-anchor">
          <div class="panel">
            <div class="panel-h"><h3>Recent Run History</h3><span class="hint">Latest dispatch runs</span></div>
            <div class="panel-b"><div class="table-wrap"><table aria-label="Recent runs">
              <thead><tr><th>Started (UTC)</th><th>Action</th><th>Status</th><th>Duration</th><th>Trigger</th><th>Commit</th></tr></thead>
              <tbody id="runsBody"><tr><td colspan="6" class="empty">Loading…</td></tr></tbody>
            </table></div></div>
          </div>
          <div id="backup" class="panel">
            <div class="panel-h"><h3>Backup &amp; State Markers</h3><span class="hint">Operational markers</span></div>
            <div class="panel-b"><pre id="backupBody">Loading…</pre></div>
          </div>
        </section>

        <section class="panel" id="errorCard" hidden>
          <div class="panel-h"><h3>Last Error</h3></div>
          <div class="panel-b"><div id="errorText" class="errbox"></div></div>
        </section>
      </main>
    </div>
  </div>

<script>
const KEY = 'spectre_api_key';
let OVERVIEW = null, ACTIONS = [];

function getKey() {
  let k = sessionStorage.getItem(KEY);
  if (!k) { k = prompt('Spectre API key (X-API-Key):') || ''; if (k) sessionStorage.setItem(KEY, k); }
  return k;
}
function setKey() {
  const k = prompt('Spectre API key (X-API-Key):', sessionStorage.getItem(KEY) || '');
  if (k !== null) { if (k) sessionStorage.setItem(KEY, k); else sessionStorage.removeItem(KEY); }
  refreshAll();
}
async function api(path, opts = {}) {
  const k = getKey();
  if (!k) throw new Error('No API key configured. Use “API Key” to set X-API-Key for this session.');
  const r = await fetch(path, { ...opts, headers: { 'X-API-Key': k, 'Content-Type': 'application/json', ...(opts.headers || {}) } });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { j = { raw: t }; }
  if (!r.ok) throw new Error(j?.detail?.error || j?.detail || j?.error || t || ('HTTP ' + r.status));
  return j;
}
function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
function statusClass(s) {
  const v = String(s || '').toLowerCase();
  if (['ok','success','healthy','up'].includes(v)) return 's-ok';
  if (['degraded','warn','warning'].includes(v)) return 's-warn';
  if (['error','crit','critical','failed','down'].includes(v)) return 's-crit';
  return 's-unknown';
}
function badge(s) { const t = String(s ?? 'unknown'); return `<span class="status ${statusClass(t)}">${esc(t)}</span>`; }
function fmtTime(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return esc(String(iso).replace('T',' ').slice(0,19));
  return esc(d.toISOString().replace('T',' ').slice(0,19)) + 'Z';
}
function showError(msg) {
  const card = document.getElementById('errorCard');
  const text = document.getElementById('errorText');
  if (!msg) { card.hidden = true; text.textContent = ''; return; }
  card.hidden = false; text.textContent = String(msg);
}

function renderOverview(d) {
  OVERVIEW = d;
  showError(null);
  const h = d.health || {};
  const hStatus = String(h.status || 'unknown');
  document.getElementById('kpiHealth').innerHTML = badge(hStatus);
  document.getElementById('kpiHealthSub').textContent = `Blocking findings: ${h.blocking_findings ?? '—'}`;
  document.getElementById('kpiJobs').textContent = d.dispatch?.job_count ?? '—';
  document.getElementById('kpiJobsSub').textContent = `Groups: ${Object.keys(d.dispatch?.groups || {}).length}`;
  document.getElementById('kpiMon').innerHTML = `${esc(String(h.monitoring_up ?? 0))}<span class="muted"> / ${esc(String(h.monitoring_total ?? 0))}</span>`;
  document.getElementById('kpiMonSub').textContent = 'Endpoints responding';
  const runs = Array.isArray(d.recent_runs) ? d.recent_runs : [];
  document.getElementById('kpiRuns').textContent = String(runs.length);
  const ok = runs.filter(r => ['success','ok'].includes(String(r.status||'').toLowerCase())).length;
  const failed = runs.filter(r => ['failed','error','crit'].includes(String(r.status||'').toLowerCase())).length;
  document.getElementById('kpiRunsSub').textContent = `Success: ${ok} · Failed: ${failed}`;

  const monitoring = Array.isArray(d.monitoring) ? d.monitoring : [];
  document.getElementById('compCount').textContent = monitoring.length ? `${monitoring.length} components` : '';
  const comps = monitoring.map(c => {
    const url = c.url ? `<div class="muted mono" style="font-size:11px;margin-top:2px">${esc(c.url)}</div>` : '';
    const lat = (c.latency_ms === 0 || c.latency_ms) ? `<span class="muted" style="font-size:11px">${esc(c.latency_ms)} ms</span>` : '';
    const err = c.error ? `<div style="color:var(--crit);font-size:11px;margin-top:4px">${esc(c.error)}</div>` : '';
    return `<div class="list-row"><div><div><strong>${esc(c.name || 'component')}</strong> <span class="muted">${esc(c.kind || '')}</span></div>${url}${err}</div><div style="text-align:right">${badge(c.status)}<div>${lat}</div></div></div>`;
  }).join('');
  document.getElementById('componentsBody').innerHTML = comps || '<div class="empty">No monitoring probes reported.</div>';

  const verify = d.dispatch?.verify || {};
  const vSummary = {
    blocking: verify.blocking ?? '—',
    advisory: verify.advisory ?? '—',
    generated_at: d.generated_at || null,
    findings: Array.isArray(verify.findings) ? verify.findings : verify.findings
  };
  document.getElementById('findingsBody').textContent = JSON.stringify(vSummary, null, 2);
  document.getElementById('backupBody').textContent = JSON.stringify(d.backup || {}, null, 2);

  const rb = document.getElementById('runsBody');
  rb.innerHTML = runs.map(r => {
    const st = (r && r.error && !r.action) ? 'error' : (r.status || 'unknown');
    const dur = (r.duration_ms === 0 || r.duration_ms) ? esc(r.duration_ms) + ' ms' : '—';
    return `<tr><td class="mono">${fmtTime(r.started_at)}</td><td class="mono">${esc(r.action || r.error || '—')}</td><td>${badge(st)}</td><td class="mono">${dur}</td><td>${esc(r.trigger || '—')}</td><td class="mono">${esc((r.git_commit || '').slice(0, 12) || '—')}</td></tr>`;
  }).join('') || '<tr><td colspan="6" class="empty">No run history available.</td></tr>';
}

function renderActions() {
  const q = (document.getElementById('q').value || '').toLowerCase();
  const g = document.getElementById('group').value;
  const mut = document.getElementById('mutOnly').checked;
  const rows = ACTIONS.filter(a => (!g || a.group === g) && (!mut || a.mutates || a.sudo) && (!q || [a.name, a.group, a.summary, a.action].join(' ').toLowerCase().includes(q)));
  document.getElementById('actionsBody').innerHTML = rows.map(a => {
    const props = [a.sudo ? badge('sudo') : '', a.mutates ? badge('mutating') : badge('read-only'), a.concurrency ? `<span class="status s-unknown">${esc(a.concurrency)}</span>` : ''].filter(Boolean).join(' ');
    const cmd = `spectre run ${a.name || ''}`;
    return `<tr><td class="mono">${esc(a.name)}</td><td>${esc(a.group || '—')}</td><td>${props}</td><td class="mono">${esc(a.schedule_hint || 'manual')}</td><td>${esc(a.summary || '—')}</td><td class="mono">${esc(cmd)}</td></tr>`;
  }).join('') || '<tr><td colspan="6" class="empty">No matching actions.</td></tr>';
}

async function loadActions() {
  const d = await api('/api/control-plane/actions');
  ACTIONS = Array.isArray(d.actions) ? d.actions : [];
  const sel = document.getElementById('group');
  const gs = [...new Set(ACTIONS.map(a => a.group).filter(Boolean))].sort();
  sel.innerHTML = '<option value="">All groups</option>' + gs.map(g => `<option value="${esc(g)}">${esc(g)}</option>`).join('');
  renderActions();
}

async function refreshAll(loadActs = true) {
  const stamp = document.getElementById('stamp');
  stamp.textContent = 'Refreshing…';
  try {
    const o = await api('/api/control-plane/overview');
    renderOverview(o);
    if (loadActs) await loadActions();
    stamp.textContent = 'Updated ' + new Date().toLocaleTimeString() + ' (auto 30s)';
  } catch (e) {
    stamp.textContent = 'Refresh failed';
    showError(e && e.message ? e.message : String(e));
  }
}

refreshAll();
setInterval(() => refreshAll(false), 30000);
</script>
</body></html>
"""
