from __future__ import annotations

import json
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

playwright_sync = pytest.importorskip("playwright.sync_api")
sync_playwright = playwright_sync.sync_playwright

ROOT = Path(__file__).resolve().parents[1] / "web-dashboard"


class DashboardStub(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.now = int(time.time())
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return

    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        from urllib.parse import parse_qs, urlparse

        parsed = urlparse(self.path)
        if parsed.path == "/api/v1/query":
            query = parse_qs(parsed.query).get("query", [""])[0]
            if "container_last_seen" in query:
                self._json({"status": "success", "data": {"resultType": "vector", "result": [
                    {"metric": {"name": "web-dashboard"}, "value": [self.now, str(self.now - 10)]},
                    {"metric": {"name": "prometheus"}, "value": [self.now, str(self.now - 12)]},
                ]}})
                return
            if "spectre_agent_up_reason" in query:
                self._json({"status": "success", "data": {"resultType": "vector", "result": [
                    {"metric": {"reason": "agent healthy"}, "value": [self.now, "1"]},
                ]}})
                return
            self._json({"status": "success", "data": {"resultType": "vector", "result": [{"metric": {}, "value": [self.now, "42"]}]}})
            return
        if parsed.path == "/api/v1/query_range":
            qs = parse_qs(parsed.query)
            start = int(float(qs.get("start", [str(self.now - 3600)])[0]))
            end = int(float(qs.get("end", [str(self.now)])[0]))
            self._json({"status": "success", "data": {"resultType": "matrix", "result": [{"metric": {}, "values": [[start, "41"], [end, "43"]]}]}})
            return
        if parsed.path == "/api/v1/alerts":
            self._json({"status": "success", "data": {"alerts": []}})
            return
        if parsed.path == "/api/v1/status/buildinfo":
            self._json({"status": "success", "data": {"version": "3.0.0"}})
            return
        return super().do_GET()


@pytest.fixture(scope="module")
def dashboard_url():
    server = ThreadingHTTPServer(("127.0.0.1", 0), DashboardStub)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address
        yield f"http://{host}:{port}/"
    finally:
        server.shutdown()
        thread.join(timeout=5)


def test_dashboard_loads_routes_and_refreshes(dashboard_url):
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        try:
            page.goto(dashboard_url)
            page.wait_for_function("() => document.getElementById('cpuUsage')?.textContent !== '--%' && !document.getElementById('refreshBtn')?.disabled", timeout=10000)
            assert page.locator("#cpuUsage").inner_text().endswith("%")
            assert page.locator("#prometheusStatus").inner_text() == "Connected"
            assert page.locator("img.brand-logo").get_attribute("src") == "assets/spectre-mark.svg"
            assert page.locator("[onclick]").count() == 0

            page.locator('.nav-item[data-page="alerts"]').click()
            page.wait_for_function("() => document.getElementById('pageHeadingText')?.textContent === 'Active Alerts'")
            assert page.locator("#alertsCard").is_visible()
            assert not page.locator("#healthCard").is_visible()

            page.locator('.nav-item[data-page="overview"]').click()
            page.wait_for_function("() => document.getElementById('pageHeadingText')?.textContent === 'Security Overview'")
            assert page.locator("#healthCard").is_visible()

            counts = page.evaluate(
                """async () => {
                while (document.getElementById('refreshBtn')?.disabled) await new Promise(r => setTimeout(r, 50));
                async function count(manual) {
                  const c = { query: 0, range: 0, alerts: 0 };
                  const orig = window.fetch;
                  window.fetch = (url, opts) => {
                    const u = String(url);
                    if (u.includes('/api/v1/query?')) c.query++;
                    if (u.includes('/api/v1/query_range')) c.range++;
                    if (u.includes('/api/v1/alerts')) c.alerts++;
                    return orig(url, opts);
                  };
                  try { await (manual ? fetchAllMetrics(new Event('click')) : fetchAllMetrics()); }
                  finally { window.fetch = orig; }
                  return c;
                }
                return { automatic: await count(false), manual: await count(true) };
                }"""
            )
            assert counts["automatic"]["query"] == 11
            assert counts["automatic"]["range"] == 0
            assert counts["manual"]["query"] == 37
            assert counts["manual"]["range"] == 4
            assert errors == []
        finally:
            browser.close()
