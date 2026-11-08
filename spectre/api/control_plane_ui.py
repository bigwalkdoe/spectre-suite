"""Enterprise Spectre control-plane dashboard UI (single-file HTML)."""

CONTROL_PLANE_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>SPECTRE CONTROL PLANE — Observability</title>
  <style>
    :root {
      --bg: #0f1419; --bg-elev: #151c24; --panel: #1a232e; --panel-2: #1f2a36;
      --line: #2a3642; --line-strong: #364656; --fg: #e7edf3; --fg-muted: #9aafc4;
      --fg-subtle: #6f8499; --accent: #4da3ff; --accent-bg: #17324d;
      --ok: #3fb950; --ok-bg: #173b24; --warn: #d29922; --warn-bg: #3d2e12;
      --crit: #f85149; --crit-bg: #3d1715; --unknown: #8b949e; --unknown-bg: #242b33;
      --focus: #79c0ff; --radius: 8px; --shadow: 0 1px 2px rgba(0,0,0,.35);
      --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; min-height: 100%; background: var(--bg); color: var(--fg); font: 13px/1.5 var(--sans); }
    a { color: var(--accent); }
    :focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
    .skip { position: absolute; left: -9999px; } .skip:focus { left: 12px; top: 12px; z-index: 20; background: var(--panel); padding: 8px 10px; border-radius: 6px; }
    header { position: sticky; top: 0; z-index: 10; background: rgba(15,20,25,.92); backdrop-filter: blur(8px); border-bottom: 1px solid var(--line); }
    .header-inner { max-width: 1480px; margin: 0 auto; padding: 12px 20px; display: flex; gap: 16px; align-items: center; justify-content: space-between; flex-wrap: wrap; }
    .brand { display: flex; flex-direction: column; gap: 2px; }
    .brand h1 { margin: 0; font: 600 15px/1.2 var(--sans); letter-spacing: .01em; }
    .brand .meta { color: var(--fg-muted); font-size: 12px; }
    .toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
    button, input, select { font: inherit; color: var(--fg); background: var(--bg-elev); border: 1px solid var(--line-strong); border-radius: 6px; padding: 6px 10px; }
    button { cursor: pointer; } button:hover { border-color: #4a6078; } button.primary { background: var(--accent-bg); border-color: #2f6fb3; }
    .banner { max-width: 1480px; margin: 12px auto 0; padding: 0 20px; }
    .notice { display: flex; gap: 10px; align-items: flex-start; padding: 10px 12px; border-radius: var(--radius); border: 1px solid var(--line); background: var(--panel); color: var(--fg-muted); font-size: 12px; }
    .notice strong { color: var(--fg); }
    main { max-width: 1480px; margin: 0 auto; padding: 16px 20px 28px; display: grid; gap: 14px; }
    .kpis { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); }
    .cols { display: grid; gap: 14px; grid-template-columns: 1.2fr .8fr; }
    @media (max-width: 1100px) { .cols { grid-template-columns: 1fr; } }
    .card { background: var(--panel); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); overflow: hidden; }
    .card-h { padding: 12px 14px; border-bottom: 1px solid var(--line); display: flex; align-items: center; justify-content: space-between; gap: 8px; }
    .card-h h2 { margin: 0; font: 600 12px/1.2 var(--sans); color: var(--fg-muted); text-transform: uppercase; letter-spacing: .06em; }
    .card-b { padding: 14px; }
    .kpi-value { font: 600 26px/1.1 var(--mono); margin-top: 2px; }
    .kpi-sub { color: var(--fg-muted); font-size: 12px; margin-top: 6px; }
    .status { display: inline-flex; align-items: center; gap: 6px; padding: 2px 8px; border-radius: 999px; font: 600 11px/1.6 var(--sans); border: 1px solid transparent; white-space: nowrap; }
    .status::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; opacity: .95; }
    .s-ok { color: var(--ok); background: var(--ok-bg); border-color: rgba(63,185,80,.25); }
    .s-warn, .s-degraded { color: var(--warn); background: var(--warn-bg); border-color: rgba(210,153,34,.25); }
    .s-crit, .s-error, .s-failed { color: var(--crit); background: var(--crit-bg); border-color: rgba(248,81,73,.25); }
    .s-unknown { color: var(--unknown); background: var(--unknown-bg); border-color: rgba(139,148,158,.25); }
    .mono { font-family: var(--mono); }
    .muted { color: var(--fg-muted); }
    .subtle { color: var(--fg-subtle); font-size: 12px; }
    .table-wrap { overflow: auto; border: 1px solid var(--line); border-radius: 6px; background: var(--bg-elev); }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th, td { padding: 9px 10px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
    th { position: sticky; top: 0; background: var(--panel-2); color: var(--fg-muted); font-weight: 600; white-space: nowrap; }
    tr:last-child td { border-bottom: 0; }
    tbody tr:hover { background: rgba(77,163,255,.04); }
    pre { margin: 0; padding: 12px; background: var(--bg-elev); border: 1px solid var(--line); border-radius: 6px; color: #c9d7e3; font: 12px/1.45 var(--mono); white-space: pre-wrap; word-break: break-word; max-height: 320px; overflow: auto; }
    .filters { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; margin-bottom: 10px; }
    .filters input[type="search"] { flex: 1; min-width: 220px; }
    .list { display: grid; gap: 8px; }
    .list-row { display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; padding: 10px 0; border-bottom: 1px solid var(--line); }
    .list-row:last-child { border-bottom: 0; padding-bottom: 0; }
    .errbox { padding: 10px 12px; border-radius: 6px; border: 1px solid rgba(248,81,73,.35); background: var(--crit-bg); color: #ffd7d5; font-size: 12px; }
    .empty { color: var(--fg-muted); font-size: 12px; padding: 8px 0; }
  </style>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header>
    <div class="header-inner">
      <div class="brand">
        <h1>SPECTRE CONTROL PLANE</h1>
        <div class="meta">Sysadmin observability interface · read-only dashboard · executions run in terminal via <span class="mono">spectre run &lt;job&gt;</span></div>
      </div>
      <div class="toolbar" role="toolbar" aria-label="Dashboard controls">
        <button type="button" onclick="setKey()">API Key</button>
        <button type="button" class="primary" onclick="refreshAll()">Refresh</button>
        <span id="stamp" class="subtle" aria-live="polite">Not loaded</span>
      </div>
    </div>
  </header>
  <div class="banner">
    <div class="notice" role="note">
      <div><strong>Observability only.</strong> This view surfaces health, dispatch state, monitoring reachability, backup markers, and run history. It does not execute actions. Run jobs from an authorized terminal session: <span class="mono">python -m spectre.cli.main run &lt;job&gt;</span> (or the standard operator dispatch path).</div>
    </div>
  </div>

  <main id="main">
    <section class="kpis" aria-label="Key indicators">
      <div class="card"><div class="card-h"><h2>Control Status</h2></div><div class="card-b"><div id="kpiHealth" class="kpi-value muted">—</div><div id="kpiHealthSub" class="kpi-sub">Waiting for data</div></div></div>
      <div class="card"><div class="card-h"><h2>Dispatch Registry</h2></div><div class="card-b"><div id="kpiJobs" class="kpi-value" style="color:var(--accent)">—</div><div id="kpiJobsSub" class="kpi-sub">Jobs / groups</div></div></div>
      <div class="card"><div class="card-h"><h2>Monitoring Reachability</h2></div><div class="card-b"><div id="kpiMon" class="kpi-value muted">—</div><div id="kpiMonSub" class="kpi-sub">Probed endpoints</div></div></div>
      <div class="card"><div class="card-h"><h2>Recent Runs</h2></div><div class="card-b"><div id="kpiRuns" class="kpi-value muted">—</div><div id="kpiRunsSub" class="kpi-sub">History window</div></div></div>
    </section>

    <section class="cols">
      <div class="card">
        <div class="card-h"><h2>Component Status</h2><span id="compCount" class="subtle"></span></div>
        <div class="card-b"><div id="components" class="list"><div class="empty">Loading…</div></div></div>
      </div>
      <div class="card">
        <div class="card-h"><h2>Dispatch Verification</h2></div>
        <div class="card-b"><pre id="findings">Loading…</pre></div>
      </div>
    </section>

    <section class="card">
      <div class="card-h"><h2>Actions Registry (Reference)</h2><span class="subtle">No execution from UI</span></div>
      <div class="card-b">
        <div class="filters">
          <input id="q" type="search" placeholder="Filter by name, group, summary, or action…" oninput="renderActions()" aria-label="Filter actions" />
          <select id="group" onchange="renderActions()" aria-label="Filter by group"><option value="">All groups</option></select>
          <label class="subtle"><input type="checkbox" id="mutOnly" onchange="renderActions()" /> Mutating/sudo only</label>
        </div>
        <div class="table-wrap"><table aria-label="Dispatch actions registry">
          <thead><tr><th>Job</th><th>Group</th><th>Properties</th><th>Schedule</th><th>Summary</th><th>Terminal command</th></tr></thead>
          <tbody id="actionsBody"><tr><td colspan="6" class="empty">Loading…</td></tr></tbody>
        </table></div>
      </div>
    </section>

    <section class="cols">
      <div class="card">
        <div class="card-h"><h2>Recent Run History</h2></div>
        <div class="card-b"><div class="table-wrap"><table aria-label="Recent runs">
          <thead><tr><th>Started (UTC)</th><th>Action</th><th>Status</th><th>Duration</th><th>Trigger</th><th>Commit</th></tr></thead>
          <tbody id="runsBody"><tr><td colspan="6" class="empty">Loading…</td></tr></tbody>
        </table></div></div>
      </div>
      <div class="card">
        <div class="card-h"><h2>Backup / State Markers</h2></div>
        <div class="card-b"><pre id="backup">Loading…</pre></div>
      </div>
    </section>

    <section class="card" id="errorCard" hidden>
      <div class="card-h"><h2>Last Error</h2></div>
      <div class="card-b"><div id="errorText" class="errbox"></div></div>
    </section>
  </main>

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
    const url = c.url ? `<div class="subtle mono">${esc(c.url)}</div>` : '';
    const lat = (c.latency_ms === 0 || c.latency_ms) ? `<span class="subtle">${esc(c.latency_ms)} ms</span>` : '';
    const err = c.error ? `<div class="subtle" style="color:var(--crit);margin-top:4px">${esc(c.error)}</div>` : '';
    return `<div class="list-row"><div><div><strong>${esc(c.name || 'component')}</strong> <span class="subtle">${esc(c.kind || '')}</span></div>${url}${err}</div><div style="text-align:right">${badge(c.status)}<div>${lat}</div></div></div>`;
  }).join('');
  document.getElementById('components').innerHTML = comps || '<div class="empty">No monitoring probes reported.</div>';

  const verify = d.dispatch?.verify || {};
  const vSummary = {
    blocking: verify.blocking ?? '—',
    advisory: verify.advisory ?? '—',
    generated_at: d.generated_at || null,
    findings: Array.isArray(verify.findings) ? verify.findings : verify.findings
  };
  document.getElementById('findings').textContent = JSON.stringify(vSummary, null, 2);

  const backup = d.backup || {};
  document.getElementById('backup').textContent = JSON.stringify(backup, null, 2);

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
