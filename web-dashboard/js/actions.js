import { ACTIONS_BASE, ACTIONS_ALLOWED, READ_ONLY } from './config.js';
import { showToast } from './dom.js';

const TOKEN_KEY = 'spectre-action-token';

export function getActionToken() {
    return sessionStorage.getItem(TOKEN_KEY) || '';
}

export function setActionToken(token) {
    const normalized = (token || '').trim();
    if (normalized) sessionStorage.setItem(TOKEN_KEY, normalized);
    else sessionStorage.removeItem(TOKEN_KEY);
}

export function clearActionToken({ notify = true } = {}) {
    sessionStorage.removeItem(TOKEN_KEY);
    if (notify) showToast('Stored dashboard action token cleared for this session', 'info');
}

export async function triggerAction(action, label, retry = true) {
    if (READ_ONLY || !ACTIONS_ALLOWED) {
        showToast(`${label}: dashboard is in read-only mode; actions are disabled.`, 'info');
        return;
    }
    if (!confirm(`This will request "${label}". Continue?`)) return;

    if (!ACTIONS_BASE) {
        showToast(`${label}: actions disabled (actionsBase=off).`, 'error');
        return;
    }

    const token = getActionToken();
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['X-Dashboard-Action-Token'] = token;

    try {
        const response = await fetch(`${ACTIONS_BASE.replace(/\/$/, '')}/${encodeURIComponent(action)}`, {
            method: 'POST',
            headers,
            body: JSON.stringify({ action, requestedAt: new Date().toISOString() })
        });

        let payload = null;
        try { payload = await response.json(); } catch (_) {}

        if (response.status === 401 && retry) {
            const entered = prompt('Action token required. Enter DASHBOARD_ACTION_TOKEN (leave blank to clear stored token for this session):');
            if (entered === null) {
                showToast(`${label}: action cancelled.`, 'info');
                return;
            }
            const normalized = entered.trim();
            if (normalized) {
                setActionToken(normalized);
                return triggerAction(action, label, false);
            }
            clearActionToken({ notify: false });
            showToast(`${label}: stored action token cleared; a token is required to run this action.`, 'error');
            return;
        }

        if (response.status === 503 && payload?.error === 'not_configured') {
            showToast(`${label}: action service not configured (set DASHBOARD_ACTION_TOKEN).`, 'error');
            return;
        }

        if (response.ok) {
            const tid = payload?.triggerId ? ` (trigger ${payload.triggerId})` : '';
            const msg = (payload?.message || `${label} accepted.`) + tid;
            showToast(msg, 'success');
        } else {
            const detail = payload?.message || payload?.error || `HTTP ${response.status}`;
            showToast(`${label} failed: ${detail}`, 'error');
        }
    } catch (e) {
        console.error('Action error:', e);
        showToast(`${label} failed: action endpoint unreachable. Is dashboard-actions running and proxied?`, 'error');
    }
}

export function initActionsApi() {
    window.spectreDashboard = window.spectreDashboard || {};
    window.spectreDashboard.clearActionToken = () => clearActionToken({ notify: true });
    window.spectreDashboard.hasActionToken = () => !!getActionToken();
    window.spectreDashboard.readOnly = READ_ONLY;
    window.spectreDashboard.actionsAllowed = ACTIONS_ALLOWED;
}
