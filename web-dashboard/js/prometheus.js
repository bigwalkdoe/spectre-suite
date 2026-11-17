import { PROMETHEUS_URL } from './config.js';
import { fetchWithTimeout } from './dom.js';

export async function queryPrometheus(query) {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`);
        if (!response.ok) {
            console.error(`Prometheus query HTTP ${response.status} for: ${query}`);
            return null;
        }
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.result) || data.data.result.length === 0) {
            return null;
        }
        return parseFloat(data.data.result[0].value[1]);
    } catch (error) {
        console.error('Error querying Prometheus:', error);
        return null;
    }
}

export async function queryPrometheusFirst(query) {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`);
        if (!response.ok) return null;
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.result) || data.data.result.length === 0) {
            return null;
        }
        return data.data.result[0];
    } catch (error) {
        return null;
    }
}

export async function queryPrometheusRange(query, start, end, step, timeoutMs = 20000) {
    return fetchWithTimeout(
        `${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(query)}&start=${start}&end=${end}&step=${step}`,
        {},
        timeoutMs
    );
}

export async function queryPrometheusRaw(query, timeoutMs) {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`, {}, timeoutMs);
        if (!response.ok) return null;
        return await response.json();
    } catch (_error) {
        return null;
    }
}

export async function queryPrometheusVector(query, timeoutMs) {
    const data = await queryPrometheusRaw(query, timeoutMs);
    if (!data || data.status !== 'success' || !Array.isArray(data.data?.result)) return null;
    return data.data.result;
}

export async function queryPrometheusSeries(query, timeoutMs) {
    const data = await queryPrometheusRaw(query, timeoutMs);
    if (!data || data.status !== 'success' || !Array.isArray(data.data?.result)) return [];
    return data.data.result;
}

export async function checkTargetUp(job) {
    const result = await queryPrometheusSeries(`up{job="${String(job).replace(/"/g, '\\"')}"}`);
    if (!result.length) return { status: 'missing', reason: `No target for job "${job}"` };
    const upValues = result.map(r => parseFloat(r.value?.[1])).filter(v => !Number.isNaN(v));
    const anyUp = upValues.some(v => v === 1);
    const allDown = upValues.length > 0 && upValues.every(v => v === 0);
    if (anyUp) return { status: 'ok', reason: 'Target up' };
    if (allDown) return { status: 'down', reason: `Target down (job "${job}")` };
    return { status: 'unknown', reason: `Unknown target state (job "${job}")` };
}
