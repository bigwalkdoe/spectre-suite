# Grafana Container/Resource Dashboard Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `grafana-dashboards/resource-monitoring.json` into a container-focused, readable, denser Grafana dashboard while keeping existing cost/disk signals in a secondary section.

**Architecture:** Edit the single dashboard JSON in place. Introduce explicit `gridPos` layout and logical sections (Container overview, Container details, Other resources), improve panel types/field formatting/units for container metrics, and preserve existing Prometheus datasource and cost/disk intent. Use standard cAdvisor/node-exporter metric names already used in this repo where applicable.

**Tech Stack:** Grafana dashboard JSON, Prometheus/cAdvisor metrics (`container_memory_usage_bytes`, `container_cpu_usage_seconds_total`, `container_last_seen`, `node_filesystem_*`, `aws_cost_estimated`).

**Spec:** User-approved design in conversation (2026-11-11): **Option 2 — container-focused restructure**. Goals: layout/readability/density for the Grafana container/resource dashboard. Keep **Cost by Provider** and **Disk Usage Trend** in a secondary section; make containers the primary surface. Assumptions: standard cAdvisor labels/metrics (`container`/`container_name`, memory/CPU/last-seen) and resilient queries.

## Global Constraints

- Modify only `grafana-dashboards/resource-monitoring.json` unless a small, directly related fix is required.
- Keep existing signals available: `aws_cost_estimated` cost panel and disk usage trend (`node_filesystem_*` for `/`) must remain present (secondary section).
- Datasource remains `Prometheus`; dashboard must stay valid JSON and loadable as a Grafana dashboard file.
- Prefer resilient, standard cAdvisor queries (e.g. filter empty container labels where appropriate); do not depend on unverified environment-specific metrics beyond those already implied by this repo.
- Preserve or improve human-readable units/legends (bytes, cores/percent as appropriate) and clear panel titles.

## Review Focus

- **Container label mismatch (`container` vs `container_name`):** queries/panels should behave reasonably if series use either label where feasible, or clearly use the label implied by the metric; avoid an empty container view due to a label-name mismatch.
- **Raw bytes in container views:** memory panels/tables must display human units (bytes IEC/Binary) rather than unreadable raw integers.
- **Missing grid/layout metadata:** panels must have explicit `gridPos` (and consistent sizing) so sections render in intended order/density instead of Grafana auto-placement chaos.
- **Non-container panels lost:** Cost by Provider and Disk Usage Trend must still exist and show their original queries/intent after restructure.
- **Invalid JSON/schema regressions:** file must parse as JSON; avoid duplicate IDs and broken panel/target structures.

---

### Task 1: Restructure dashboard layout and container panels

**Files:**
- Modify: `grafana-dashboards/resource-monitoring.json`
- Test/Verify: JSON validity and structure via CLI checks

**Interfaces:**
- Consumes: current dashboard panels/queries in `grafana-dashboards/resource-monitoring.json`; metric patterns from repo (`container_memory_usage_bytes`, `container_last_seen`, `container_cpu_usage_seconds_total`, `node_filesystem_*`, `aws_cost_estimated`).
- Produces: updated dashboard JSON with container-primary sections, secondary cost/disk section, explicit `gridPos`, readable units/legends, and valid JSON.

- [ ] **Step 1: Inspect current dashboard and confirm baseline**

Run: `python3 -m json.tool grafana-dashboards/resource-monitoring.json >/tmp/opencode/resource-monitoring.before.json && wc -l /tmp/opencode/resource-monitoring.before.json`
Expected: command succeeds (valid JSON) and prints a line count.

- [ ] **Step 2: Rewrite `grafana-dashboards/resource-monitoring.json` with container-focused layout**

Implement the approved structure:
- **Container overview (top row/section):** compact stat panels such as active containers (from `container_last_seen`, using a resilient count expression) and aggregate container CPU/memory where sensible (standard cAdvisor metrics).
- **Container details (primary):** dense per-container visibility, e.g. a table of current container memory usage with human `bytes` unit/formatting and a timeseries for per-container memory and/or CPU rate (`rate(container_cpu_usage_seconds_total{container!=""}[5m])` or equivalent) with clear legends; prefer readable sorting/field config.
- **Other resources (secondary, below):** retain **Cost by Provider** (`sum(aws_cost_estimated) by (service)`) and **Disk Usage Trend** (`100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)`) with clear titles/units; keep or rework “Unused Resources” only if it adds value without clutter.
- Apply explicit `gridPos` to every panel, consistent widths/heights for density, unique panel IDs, and clear sectioning (row panels or ordered layout with descriptive titles). Keep `datasource: "Prometheus"` and reasonable dashboard metadata (`title`, `uid`, `tags`, `timezone`, `schemaVersion`/fields consistent with file style).

- [ ] **Step 3: Validate JSON and key content**

Run: `python3 -m json.tool grafana-dashboards/resource-monitoring.json >/tmp/opencode/resource-monitoring.after.json`
Expected: PASS (no parse errors).

Run: `rg -n "Cost by Provider|Disk Usage Trend|container_memory_usage_bytes|container_last_seen|aws_cost_estimated|node_filesystem" grafana-dashboards/resource-monitoring.json`
Expected: all named signals/panels present.

Run: `rg -n "gridPos" grafana-dashboards/resource-monitoring.json`
Expected: multiple matches (every panel positioned explicitly).

- [ ] **Step 4: Sanity-check for readability/density choices**

Run: `python3 - <<'PY'
import json
d=json.load(open('grafana-dashboards/resource-monitoring.json'))
panels=d.get('panels',[])
ids=[p.get('id') for p in panels]
assert len(ids)==len(set(ids)), 'duplicate panel ids'
assert all('gridPos' in p for p in panels), 'missing gridPos'
print('panels',len(panels),'ids_unique',len(ids)==len(set(ids)),'all_gridPos',True)
PY`
Expected: prints panel count with `ids_unique True all_gridPos True`.

- [ ] **Step 5: Commit**

```bash
git add grafana-dashboards/resource-monitoring.json docs/superpowers/plans/2026-11-11-grafana-container-resource-dashboard-layout.md
git commit -m "Improve container resource dashboard layout and readability"
```

## Execution Handoff

After saving and self-reviewing the plan, report completion and ask for review/approval to execute (user already approved the design and chose Option 2). If an execution method is requested: prefer **Native** for this single-file, low-dependency change unless subagent-driven review is desired.
