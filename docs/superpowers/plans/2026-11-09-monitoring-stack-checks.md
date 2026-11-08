# Monitoring Stack Checks Implementation Plan

> **For agentic workers:** Track progress task-by-task.

**Goal:** Add a read-only `spectre` action that detects Prometheus route-prefix misconfiguration and Grafana↔Prometheus datasource/connectivity drift (the failure mode debugged on 2026-11-09).

**Architecture:** A bash action under `spectre/actions/monitoring/` performs host-level Prometheus checks (`/prometheus/-/healthy`, `/-/ready`, `api/v1/status/buildinfo` when route prefix is known), optional in-network checks via `docker exec grafana wget`, and optional Grafana datasource config/health checks via Grafana HTTP API when admin credentials are available from environment (never printed). Register in `spectre/dispatch/registry_data.json`. Add a small bash test with a mock HTTP server / local fixtures.

**Tech Stack:** bash, curl, python3 (stdlib) for safe JSON/env parsing, docker CLI (optional), spectre dispatch registry.

## Task List
- [x] Task 1: Inspect dispatch/registry/test patterns.
- [x] Task 2: Implement `spectre/actions/monitoring/check-monitoring-stack.sh`.
- [x] Task 3: Register `monitoring/check-monitoring-stack` in `spectre/dispatch/registry_data.json`.
- [x] Task 4: Add `tests/test_monitoring_stack_check.sh` and wire into `tests/run_tests.sh`.
- [x] Task 5: Run targeted verification (`bash -n`, test script, `spectre actions show/verify` if available).
- [x] Task 6: Commit and push the new monitoring check.
