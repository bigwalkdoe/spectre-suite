import { DEFAULT_REFRESH_INTERVAL } from './config.js';

export const state = {
    refreshIntervalMs: DEFAULT_REFRESH_INTERVAL,
    refreshTimerId: null,
    isRefreshing: false,
    chart: null,
    chartRequestToken: 0,
    lastPrometheusConnected: null,
    currentAlerts: [],
    activeAlertFilter: 'all',
    lastQueryStats: { total: 0, succeeded: 0, failed: 0 },
    lastExporterStatus: { backup: false, agent: false, baseline: false },
    lastChartRefreshAt: 0,
    slowMetricsCache: null,
    slowMetricsCacheAt: 0,
    lastContainerSignature: null,
    lastRenderedContainerKey: null,
    currentContainerNames: [],
    lastContainerMeta: { hasUnlabeledRecent: false },
    countdownIntervalId: null,
    countdownSeconds: 0,
};

export function getChart() { return state.chart; }
export function setChart(chart) { state.chart = chart; }
