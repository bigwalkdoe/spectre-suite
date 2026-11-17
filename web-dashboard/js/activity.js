import { ACTIONS_BASE, ACTIONS_ALLOWED, READ_ONLY } from './config.js';
import { fetchWithTimeout, escapeHtml, showToast } from './dom.js';
import { getActionToken } from './actions.js';

function formatRunTime(value) {
    if (!value) return '--';
    const t = Date.parse(value);
    if (Number.isNaN(t)) return String(value);
    return new Date(t).toLocaleString();
}

function statusBadge(status) {
    const s = String(status || 'unknown').toLowerCase();
    if (s === 'succeeded') return '<span class="badge badge-success">succeeded</span>';
    if (s === 'failed' || s === 'rejected') return '<span class="badge badge-danger">' + escapeHtml(s) + '</span>';
    if (s === 'running' || s === 'queued') return '<span class="badge badge-warning">' + escapeHtml(s) + '</span>';
    return '<span class="badge">' + escapeHtml(s || 'unknown') + '</span>';
}

export async function fetchActionRuns(limit = 20) {
    if (!ACTIONS_BASE) return { ok: false, error: 'disabled', message: 'Actions disabled (actionsBase=off).' };
    const token = getActionToken();
    const headers = {};
    if (token) headers['X-Dashboard-Action-Token'] = token;
    try {
        const res = await fetchWithTimeout(`${ACTIONS_BASE.replace(/\/$/, '')}/runs?limit=${encodeURIComponent(String(limit))}`, { headers }, 12000);
        let payload = null;
        try { payload = await res.json(); } catch (_) {}
        if (res.status === 401) return { ok: false, error: 'unauthorized', message: 'Unauthorized (missing/invalid action token).' };
        if (res.status === 503 && payload?.error === 'not_configured') return { ok: false, error: 'not_configured', message: 'Action service not configured (DASHBOARD_ACTION_TOKEN unset).' };
        if (!res.ok) return { ok: false, error: payload?.error || 'http_error', message: payload?.message || `HTTP ${res.status}` };
        return { ok: true, runs: Array.isArray(payload?.runs) ? payload.runs : [] };
    } catch (e) {
        return { ok: false, error: 'unreachable', message: 'Action run status endpoint unreachable.' };
    }
}

export function renderActionRuns(result) {
    const list = document.getElementById('actionRunsList');
    const status = document.getElementById('actionRunsStatus');
    if (!list) return;
    if (!result || !result.ok) {
        const msg = result?.message || 'Action activity unavailable.';
        if (status) { status.textContent = result?.error === 'disabled' ? 'Disabled' : 'Unavailable'; status.className = 'badge badge-warning'; }
        list.innerHTML = `<div class="no-alerts no-alerts--degraded"><i class="fas fa-clock-rotate-left" aria-hidden="true"></i><span><strong>Action activity unavailable.</strong> ${escapeHtml(msg)}</span></div>`;
        return;
    }
    const runs = Array.isArray(result.runs) ? result.runs : [];
    if (status) { status.textContent = `${runs.length} recent`; status.className = runs.length ? 'badge badge-success' : 'badge'; }
    if (!runs.length) {
        list.innerHTML = '<div class="no-alerts"><i class="fas fa-clock-rotate-left" aria-hidden="true"></i><span>No recorded action runs yet.</span></div>';
        return;
    }
    list.innerHTML = runs.map((run) => {
        const id = escapeHtml(run.id || '');
        const action = escapeHtml(run.action || '');
        const msg = escapeHtml(run.message || '');
        const reason = run.reason ? `<div class="muted">Reason: ${escapeHtml(run.reason)}</div>` : '';
        const actor = run.actor ? `<span class="muted"> · actor: ${escapeHtml(run.actor)}</span>` : '';
        const exit = (run.exitCode !== null && run.exitCode !== undefined) ? ` · exit ${escapeHtml(String(run.exitCode))}` : '';
        return `<div class="activity-item">
            <div class="activity-main">
                <div class="activity-title"><strong>${action || 'action'}</strong> ${statusBadge(run.status)} <span class="muted mono">${id}</span></div>
                <div class="activity-meta muted">requested ${escapeHtml(formatRunTime(run.requestedAt))} · started ${escapeHtml(formatRunTime(run.startedAt))} · finished ${escapeHtml(formatRunTime(run.finishedAt))}${exit}${actor}</div>
                ${msg ? `<div class="activity-message">${msg}</div>` : ''}
                ${reason}
            </div>
        </div>`;
    }).join('');
}

let activityTimer = null;
export function initActionActivity({ intervalMs = 30000 } = {}) {
    const refreshBtn = document.getElementById('actionRunsRefreshBtn');
    const refresh = async () => {
        const result = await fetchActionRuns(20);
        renderActionRuns(result);
    };
    if (refreshBtn) refreshBtn.addEventListener('click', () => { refresh().catch(() => {}); });
    refresh().catch(() => {});
    if (activityTimer) clearInterval(activityTimer);
    activityTimer = setInterval(() => {
        if (document.hidden) return;
        if (READ_ONLY) return; // still useful, but avoid noisy unauth polling in viewer mode without token context; can refresh manually
        refresh().catch(() => {});
    }, intervalMs);
}
