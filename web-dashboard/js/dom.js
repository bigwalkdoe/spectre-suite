import { FETCH_TIMEOUT_MS } from './config.js';

export async function fetchWithTimeout(url, options = {}, timeoutMs = FETCH_TIMEOUT_MS) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
        return await fetch(url, { ...options, signal: controller.signal });
    } finally {
        clearTimeout(timeoutId);
    }
}

export function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

export function setText(id, value) {
    const el = document.getElementById(id);
    if (!el) return false;
    el.textContent = value;
    return true;
}

export function setCardLoading(cardId, isLoading) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.toggle('card--loading', isLoading);
    card.setAttribute('aria-busy', isLoading ? 'true' : 'false');
}

export function setCardError(cardId, message) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--loading');
    card.setAttribute('aria-busy', 'false');
    card.classList.add('card--error');
    let errorEl = card.querySelector('.error-message');
    if (!errorEl) {
        errorEl = document.createElement('div');
        errorEl.className = 'error-message';
        errorEl.setAttribute('role', 'alert');
        const body = card.querySelector('.card-body') || card;
        body.appendChild(errorEl);
    }
    errorEl.innerHTML = `<i class="fas fa-exclamation-circle" aria-hidden="true"></i> ${escapeHtml(message)}`;
}

export function clearCardError(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--error', 'card--loading');
    card.setAttribute('aria-busy', 'false');
    const errorEl = card.querySelector('.error-message');
    if (errorEl) errorEl.remove();
}

export function runCardUpdate(cardId, fn) {
    try {
        fn();
    } catch (error) {
        console.error(`Error rendering ${cardId}:`, error);
        setCardError(cardId, 'Render failed');
    }
}

export function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast--${type}`;
    toast.setAttribute('role', type === 'error' ? 'alert' : 'status');
    const iconClass = type === 'success' ? 'fa-check-circle' : type === 'error' ? 'fa-exclamation-triangle' : 'fa-info-circle';
    toast.innerHTML = `<i class="fas ${iconClass}" aria-hidden="true"></i><span class="toast-message">${escapeHtml(message)}</span>`;
    container.appendChild(toast);
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    setTimeout(() => {
        if (!reduceMotion) {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(120%)';
            setTimeout(() => toast.remove(), 300);
        } else {
            toast.remove();
        }
    }, 4000);
}

export function setCardUpdated(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    let el = card.querySelector('.card-updated');
    const text = `Updated ${new Date().toLocaleTimeString()}`;
    if (!el) {
        el = document.createElement('div');
        el.className = 'card-updated';
        const target = card.querySelector('.stat-content') || card.querySelector('.card-body') || card;
        target.appendChild(el);
    }
    el.innerHTML = `<i class="fas fa-clock" aria-hidden="true"></i> ${escapeHtml(text)}`;
}

export function formatBytes(bytes) {
    if (bytes === null || bytes === undefined || isNaN(bytes)) return 'No data';
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const val = bytes / Math.pow(1024, i);
    return `${val.toFixed(val >= 10 ? 0 : 1)} ${units[i]}`;
}

export function formatBytesPerSec(bytesPerSec) {
    if (bytesPerSec === null || bytesPerSec === undefined || isNaN(bytesPerSec)) return 'No data';
    if (bytesPerSec <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
    const i = Math.min(Math.floor(Math.log(bytesPerSec) / Math.log(1024)), units.length - 1);
    const val = bytesPerSec / Math.pow(1024, i);
    return `${val.toFixed(val >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
}

export function formatRelativeTime(epochSeconds) {
    if (!epochSeconds || epochSeconds <= 0) return 'Never';
    const diff = Math.floor(Date.now() / 1000 - epochSeconds);
    if (diff < 0) return 'Just now';
    if (diff < 60) return `${diff}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
}

export function formatUptime(seconds) {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
}
