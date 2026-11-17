export const qs = new URLSearchParams(location.search);
export const host = location.hostname || 'localhost';
export const proto = location.protocol === 'https:' ? 'https:' : 'http:';

export const PROMETHEUS_URL = qs.get('prometheus') || '';
const actionsBaseParam = qs.get('actionsBase');
const readOnlyParam = (qs.get('readOnly') || qs.get('readonly') || '').toLowerCase();
export const READ_ONLY = readOnlyParam === '1' || readOnlyParam === 'true' || readOnlyParam === 'yes' || readOnlyParam === 'on';
export const ACTIONS_BASE = actionsBaseParam === 'off' ? '' : (actionsBaseParam || '/actions');
export const ACTIONS_ALLOWED = !READ_ONLY && !!ACTIONS_BASE;

function backendUrl(urlKey, portKey, _defaultPort, proxyBase) {
    const full = qs.get(urlKey);
    if (full) return String(full).replace(/\/$/, '');
    if (qs.get(portKey)) {
        return `${proto}//${host}:${qs.get(portKey)}${proxyBase}`;
    }
    return proxyBase;
}

export const EXTERNAL_BACKENDS = {
    grafana: backendUrl('grafanaUrl', 'grafanaPort', '3002', '/grafana'),
    prometheus: backendUrl('prometheusUrl', 'prometheusPort', '9090', '/prometheus'),
    alertmanager: backendUrl('alertmanagerUrl', 'alertmanagerPort', '9093', '/alertmanager'),
};

export function externalUrl(backend, path = '/') {
    const base = EXTERNAL_BACKENDS[backend];
    if (!base) return '#';
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${base}${p}`;
}

export function extBase(key) {
    const v = EXTERNAL_BACKENDS && EXTERNAL_BACKENDS[key] ? String(EXTERNAL_BACKENDS[key]) : '';
    return v.replace(/\/$/, '');
}

export const DEFAULT_REFRESH_INTERVAL = 30000;
export const FETCH_TIMEOUT_MS = 12000;
export const CHART_AUTO_REFRESH_MS = 5 * 60 * 1000;
export const SLOW_METRICS_REFRESH_MS = 5 * 60 * 1000;
