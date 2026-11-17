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
    if (!result.length) return { status: 'missing', reason: `No target for job "${job}"`, up: 0, total: 0 };
    const upValues = result.map(r => parseFloat(r.value?.[1])).filter(v => !Number.isNaN(v));
    const upCount = upValues.filter(v => v === 1).length;
    const total = upValues.length || result.length;
    const anyUp = upCount > 0;
    const allDown = total > 0 && upCount === 0;
    const reason = total ? `${upCount}/${total} targets up (job "${job}")` : `Unknown target state (job "${job}")`;
    if (anyUp && upCount === total) return { status: 'ok', reason, up: upCount, total };
    if (anyUp) return { status: 'down', reason, up: upCount, total };
    if (allDown) return { status: 'down', reason, up: upCount, total };
    return { status: 'unknown', reason: `Unknown target state (job "${job}")`, up: upCount, total };
}

export async function querySampleAgeSeconds(metricSelector, timeoutMs) {
    // Returns age in seconds for newest sample of selector, or null if unavailable.
    const query = `time() - max(timestamp(${metricSelector}))`;
    const value = await queryPrometheus(query);
    if (value === null || Number.isNaN(value) || value < 0) return null;
    return value;
}
