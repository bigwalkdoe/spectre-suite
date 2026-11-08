"""Enterprise Spectre control-plane dashboard UI (single-file HTML)."""

CONTROL_PLANE_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Spectre Control Plane</title>
  <style>
    :root { --bg:#0b1020; --panel:#121a2b; --panel2:#172238; --line:#24314d; --fg:#e6edf7; --muted:#9fb0cc; --accent:#59d0ff; --good:#39d98a; --warn:#ffcc66; --bad:#ff6b6b; --vio:#b794ff; }
    *{box-sizing:border-box} body{margin:0;font:14px/1.45 ui-sans-serif,system-ui,Segoe UI,Roboto,sans-serif;background:radial-gradient(1200px 500px at 10% -10%,#17255433,transparent),var(--bg);color:var(--fg)}
    header{position:sticky;top:0;z-index:5;background:linear-gradient(180deg,#0b1020ee,#0b1020cc);backdrop-filter:blur(8px);border-bottom:1px solid var(--line);padding:14px 18px;display:flex;gap:12px;align-items:center;justify-content:space-between}
    h1{margin:0;font:700 18px/1.1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.04em} .sub{color:var(--muted);font-size:12px}
    .wrap{padding:16px;max-width:1500px;margin:0 auto} .grid{display:grid;gap:12px} .kpis{grid-template-columns:repeat(auto-fit,minmax(180px,1fr))}
    .card{background:linear-gradient(180deg,var(--panel),var(--panel2));border:1px solid var(--line);border-radius:14px;padding:14px;box-shadow:0 10px 30px #0003}
    .card h2{margin:0 0 10px;font:600 12px ui-monospace,monospace;color:var(--muted);text-transform:uppercase;letter-spacing:.08em}
    .kpi{font:700 28px/1 ui-monospace,monospace} .good{color:var(--good)} .warn{color:var(--warn)} .bad{color:var(--bad)} .accent{color:var(--accent)}
    .row{display:flex;gap:8px;flex-wrap:wrap;align-items:center} button,input,select{background:#0d1526;color:var(--fg);border:1px solid var(--line);border-radius:10px;padding:8px 10px;font:inherit}
    button{cursor:pointer} button.primary{background:#113a55;border-color:#1f6a8f} button.danger{background:#3d1a1a;border-color:#6b2a2a}
    .pill{display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid var(--line);font-size:11px;color:var(--muted)} .pill.ok{color:var(--good);border-color:#1f5a3a}
    .pill.err{color:var(--bad);border-color:#5a1f1f} .pill.mut{color:var(--warn);border-color:#5a4a1f}
    table{width:100%;border-collapse:collapse;font-size:12px} th,td{padding:8px 6px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}
    th{color:var(--muted);font-weight:600;position:sticky;top:0;background:var(--panel)} .table-wrap{max-height:420px;overflow:auto;border:1px solid var(--line);border-radius:10px}
    code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,monospace} pre{margin:0;white-space:pre-wrap;word-break:break-word;color:#cfe1ff;background:#09101d;padding:10px;border-radius:10px;border:1px solid var(--line);max-height:260px;overflow:auto}
    .cols{grid-template-columns:1.2fr .8fr} @media (max-width:1100px){.cols{grid-template-columns:1fr}}
    .muted{color:var(--muted)} .mono{font-family:ui-monospace,monospace} .footer{padding:8px 2px;color:var(--muted);font-size:12px}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>☤ SPECTRE CONTROL PLANE</h1>
      <div class="sub">Integrated view: dispatch · backups/restic · monitoring/alerts · security · maintenance · runs</div>
    </div>
    <div class="row">
      <button onclick="setKey()">API Key</button>
      <button class="primary" onclick="refreshAll()">Refresh</button>
      <span id="stamp" class="sub"></span>
    </div>
  </header>
  <div class="wrap grid" style="gap:12px">
    <section class="grid kpis">
      <div class="card"><h2>Control Health</h2><div id="kpiHealth" class="kpi muted">—</div><div id="kpiHealthSub" class="sub"></div></div>
      <div class="card"><h2>Dispatch Registry</h2><div id="kpiJobs" class="kpi accent">—</div><div id="kpiJobsSub" class="sub"></div></div>
      <div class="card"><h2>Monitoring</h2><div id="kpiMon" class="kpi muted">—</div><div id="kpiMonSub" class="sub"></div></div>
      <div class="card"><h2>Recent Runs</h2><div id="kpiRuns" class="kpi muted">—</div><div id="kpiRunsSub" class="sub"></div></div>
    </section>

    <section class="grid cols">
      <div class="card">
        <h2>Component Status</h2>
        <div id="components">Loading…</div>
      </div>
      <div class="card">
        <h2>Verify / Dispatch Findings</h2>
        <pre id="findings">Loading…</pre>
      </div>
    </section>

    <section class="card">
      <h2>Actions (Registry)</h2>
      <div class="row" style="margin-bottom:8px">
        <input id="q" placeholder="Filter actions…" oninput="renderActions()" style="min-width:260px;flex:1" />
        <select id="group" onchange="renderActions()"><option value="">All groups</option></select>
        <label class="sub"><input type="checkbox" id="mutOnly" onchange="renderActions()" /> mutating only</label>
      </div>
      <div class="table-wrap"><table><thead><tr><th>Job</th><th>Flags</th><th>Schedule</th><th>Summary</th><th>Run</th></tr></thead><tbody id="actionsBody"></tbody></table></div>
      <div class="footer">Run uses authenticated <code>POST /api/control-plane/actions/&lt;job&gt;/run</code> (normal <code>spectre run</code> path: resolve/lock/sudo/provenance/records). Confirm before triggering mutating/sudo jobs.</div>
    </section>

    <section class="grid cols">
      <div class="card">
        <h2>Recent Run History</h2>
        <div class="table-wrap"><table><thead><tr><th>Time</th><th>Action</th><th>Status</th><th>Dur</th><th>Trigger</th><th>Commit</th></tr></thead><tbody id="runsBody"></tbody></table></div>
      </div>
      <div class="card">
        <h2>Action / Operation Result</h2>
        <pre id="result">No operation yet.</pre>
      </div>
    </section>

    <section class="card">
      <h2>Backup / Restic State Signals</h2>
      <pre id="backup">Loading…</pre>
    </section>
  </div>

<script>
const KEY='spectre_api_key'; let OVERVIEW=null, ACTIONS=[];
function getKey(){let k=sessionStorage.getItem(KEY); if(!k){k=prompt('Spectre API key (X-API-Key):')||''; if(k) sessionStorage.setItem(KEY,k);} return k;}
function setKey(){const k=prompt('Spectre API key (X-API-Key):',sessionStorage.getItem(KEY)||''); if(k!==null){ if(k) sessionStorage.setItem(KEY,k); else sessionStorage.removeItem(KEY);} refreshAll();}
async function api(path,opts={}){const k=getKey(); if(!k) throw new Error('No API key'); const r=await fetch(path,{...opts,headers:{'X-API-Key':k,'Content-Type':'application/json',...(opts.headers||{})}}); const t=await r.text(); let j; try{j=JSON.parse(t)}catch{j={raw:t}}; if(!r.ok) throw new Error(j?.detail?.error||j?.detail||j?.error||t||r.status); return j;}
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]))}
function pill(text,cls){return `<span class="pill ${cls||''}">${esc(text)}</span>`}
function renderOverview(d){OVERVIEW=d; const h=d.health||{};
  const hk=document.getElementById('kpiHealth'); hk.textContent=(h.status||'—').toUpperCase(); hk.className='kpi '+(h.status==='ok'?'good':h.blocking_findings?'bad':'warn');
  document.getElementById('kpiHealthSub').textContent=`blocking findings: ${h.blocking_findings??'—'}`;
  document.getElementById('kpiJobs').textContent=d.dispatch?.job_count??'—'; document.getElementById('kpiJobsSub').textContent=`groups: ${Object.keys(d.dispatch?.groups||{}).length}`;
  document.getElementById('kpiMon').textContent=`${h.monitoring_up??0}/${h.monitoring_total??0}`; document.getElementById('kpiMonSub').textContent='Prometheus/Alertmanager/Grafana/Blackbox probes';
  const runs=d.recent_runs||[]; document.getElementById('kpiRuns').textContent=runs.length; const ok=runs.filter(r=>r.status==='success'||r.status==='ok').length; document.getElementById('kpiRunsSub').textContent=`success in window: ${ok}`;
  const comps=(d.monitoring||[]).map(c=>`<div class="row" style="justify-content:space-between;margin:6px 0"><div><strong>${esc(c.name)}</strong> <span class="sub mono">${esc(c.url)}</span></div><div>${pill(c.status,c.status==='ok'?'ok':'err')} <span class="sub">${esc(c.latency_ms??'')}ms</span></div></div>`).join('') || '<div class="muted">No monitoring probes.</div>';
  document.getElementById('components').innerHTML=comps + `<hr style="border:0;border-top:1px solid var(--line);margin:10px 0"/>` + [`Dispatch verify: blocking ${d.dispatch?.verify?.blocking??'—'}, advisory ${d.dispatch?.verify?.advisory??'—'}`, `Backup state dirs: ${(d.backup?.state_dirs_checked||[]).join(', ')||'—'}`, `Generated: ${d.generated_at||'—'}`].map(x=>`<div class="sub">${esc(x)}</div>`).join('');
  document.getElementById('findings').textContent=JSON.stringify(d.dispatch?.verify||{},null,2);
  document.getElementById('backup').textContent=JSON.stringify(d.backup||{},null,2);
  const rb=document.getElementById('runsBody'); rb.innerHTML=runs.map(r=>`<tr><td class="mono">${esc((r.started_at||'').replace('T',' ').slice(0,19))}</td><td class="mono">${esc(r.action)}</td><td>${pill(r.status,r.status==='success'||r.status==='ok'?'ok':r.status==='failed'?'err':'')}</td><td>${esc(r.duration_ms??'')}</td><td>${esc(r.trigger||'')}</td><td class="mono">${esc((r.git_commit||'').slice(0,8))}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">No run history available.</td></tr>';
}
function renderActions(){const q=(document.getElementById('q').value||'').toLowerCase(); const g=document.getElementById('group').value; const mut=document.getElementById('mutOnly').checked;
  const rows=ACTIONS.filter(a=>(!g||a.group===g)&&(!mut||a.mutates)&&(!q||[a.name,a.group,a.summary,a.action].join(' ').toLowerCase().includes(q)));
  document.getElementById('actionsBody').innerHTML=rows.map(a=>`<tr><td class="mono">${esc(a.name)}</td><td>${a.sudo?pill('sudo','mut'):''} ${a.mutates?pill('mutates','mut'):pill('read','ok')} ${pill(a.concurrency||'')}</td><td class="mono">${esc(a.schedule_hint||'manual')}</td><td>${esc(a.summary||'')}</td><td><button class="${a.mutates||a.sudo?'danger':''}" onclick="runJob('${esc(a.name).replace(/'/g,"\\'")}')">Run</button></td></tr>`).join('') || '<tr><td colspan="5" class="muted">No matching actions.</td></tr>';}
async function loadActions(){const d=await api('/api/control-plane/actions'); ACTIONS=d.actions||[]; const sel=document.getElementById('group'); const gs=[...new Set(ACTIONS.map(a=>a.group).filter(Boolean))].sort(); sel.innerHTML='<option value="">All groups</option>'+gs.map(g=>`<option>${esc(g)}</option>`).join(''); renderActions();}
async function runJob(job){if(!confirm(`Run action via normal spectre dispatch?\n\n${job}\n\nThis may mutate state depending on the job.`)) return; const out=document.getElementById('result'); out.textContent=`Running ${job}...`; try{const d=await api(`/api/control-plane/actions/${encodeURIComponent(job)}/run`,{method:'POST'}); out.textContent=JSON.stringify(d,null,2); await refreshAll(false);}catch(e){out.textContent=String(e.message||e);}}
async function refreshAll(loadActs=true){document.getElementById('stamp').textContent='Refreshing…'; try{const o=await api('/api/control-plane/overview'); renderOverview(o); if(loadActs) await loadActions(); document.getElementById('stamp').textContent='Updated '+new Date().toLocaleTimeString();}catch(e){document.getElementById('stamp').textContent='Error'; document.getElementById('findings').textContent=String(e.message||e);}}
refreshAll(); setInterval(()=>refreshAll(false), 30000);
</script>
</body></html>
"""
