# Spectre MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local stdio MCP server for Spectre that exposes the suite's observe and act surfaces as MCP tools, reusing the registry, dispatch runner, database, and workflow engine.

**Architecture:** An in-process Python package `spectre/mcp/` (server, service, policy, redact) on the official MCP SDK (`mcp>=2.3,<3`, optional extra `mcp`, console script `spectre-mcp`). Read tools call the library directly; act tools run `resolve -> JobLock -> run_action -> save_run`. Mutations are gated by `SPECTRE_MCP_ALLOW_MUTATIONS`, root access by `SPECTRE_MCP_ALLOW_SUDO` plus euid.

**Tech Stack:** Python 3.12 (`/home/deon/.local/share/spectre-venv`), MCP Python SDK 2.3.0, existing spectre modules (SQLModel/SQLite store, WorkflowEngine, dispatch), pytest with the in-memory MCP client, typer for the CLI entry, ruff and mypy.

**Spec:** `docs/superpowers/specs/2026-11-28-spectre-mcp-design.md`

## Global Constraints

- MCP SDK pinned `mcp>=2.3,<3`; synchronous tool handlers run in worker threads via `anyio.to_thread.run_sync()` in v2, so blocking calls are safe.
- Env vars: `SPECTRE_MCP_ALLOW_MUTATIONS` (default off), `SPECTRE_MCP_ALLOW_SUDO` (default off), `SPECTRE_MCP_LOG_LEVEL` (default `INFO`), `SPECTRE_MCP_MAX_ROWS` (default `200`).
- Authorization model: `SPECTRE_MCP_ALLOW_MUTATIONS=1` is the real authorization; `confirm=true` returns a preview or runs. No nonce, no elicitation in v1.
- Redaction: shared best-effort redactor over every result; marker `[REDACTED]`; result carries `redacted: true` when a replacement happened.
- Output bounds: embedded text fields truncated via `spectre.dispatch.envelope.truncate_output(text, 16384)`.
- Act semantics: mutating actions, workflow runs, config writes, and schedule changes are gated by the mutation flag; workflows have no sudo gate and run unprivileged; workflow runs hold the act lock until completion and have no deadline.
- Schedule tools: operate on the database `scheduled_tasks` key; results report `scheduled: false` with the daemon-limitation note; `spectre_schedule_list` reads both the DB key and YAML `schedules` and labels each entry's source.

## Review Focus

Five input classes/failure modes the design implies that no task's tests must not exercise, with the owning task:

1. Client cancellation of a long-running workflow — owner Task 7; behavior: the tool returns control to the client while the workflow keeps running and holds the act lock; test: assert workflow run does not attempt to stop on cancel (Task 5 / Task 7).
2. Redaction that misses — owner Task 3; behavior: common patterns are replaced; best-effort by design. Test: task 3 covers private key, bearer, assignment, prefix; add an unquoted-value case.
3. `config_set` preview must not echo the current value — owner Task 5; behavior: preview carries key, profile, proposed value, key-exists flag, gate state only. Test: task 5.
4. `spectre_status` with an unknown agent name — owner Task 4; behavior: that agent returns an error, the call does not fail. Test: task 4.
5. `spectre_health` tool annotation must be `readOnlyHint=false` — owner Task 6; behavior: the tool writes records but is not mutation-gated. Test: task 6 asserts annotations.

## Tasks

### Task 1: Scaffold the `spectre/mcp` package and packaging

**Files:**
- Create: `spectre/mcp/__init__.py`
- Create: `spectre/mcp/__main__.py`
- Create: `spectre/mcp/server.py`
- Modify: `pyproject.toml:7` (version), `pyproject.toml:44-54` (optional deps), `pyproject.toml:56-57` (scripts)

**Interfaces:**
- Consumes: none.
- Produces: `spectre.mcp.server:main()`, module `spectre.mcp.server:mcp` (MCPServer), `python -m spectre.mcp`, console script `spectre-mcp = spectre.mcp.server:main`.

- [ ] **Step 1: Write the failing test**

```python
import pytest

mcp = pytest.importorskip("mcp")

def test_mcp_package_exports_main() -> None:
    import spectre.mcp.server as server_module

    assert callable(server_module.main)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/deon/.local/share/spectre-venv/bin/python -m pytest tests/agent/test_mcp_scaffold.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'spectre.mcp'`

- [ ] **Step 3: Implement**

Create `spectre/mcp/__init__.py` (package docstring), `spectre/mcp/server.py` (`from mcp.server import MCPServer`, `mcp = MCPServer("spectre")`, `def main() -> None: mcp.run()`), `spectre/mcp/__main__.py` (`from spectre.mcp.server import main; main()`).
Edit `pyproject.toml`: `version = "1.1.0"`, optional dep `mcp = ["mcp>=2.3,<3"]`, script `spectre-mcp = "spectre.mcp.server:main"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/deon/.local/share/spectre-venv/bin/python -m pytest tests/agent/test_mcp_scaffold.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add spectre/mcp tests/agent/test_mcp_scaffold.py pyproject.toml
git commit -m "build: scaffold spectre.mcp package and spectre-mcp console script"
```

### Task 2: Policy module

**Files:**
- Create: `spectre/mcp/policy.py`
- Create: `tests/agent/test_mcp_policy.py`

**Interfaces:**
- Produces:
  - `MUTATIONS_ENV = "SPECTRE_MCP_ALLOW_MUTATIONS"`, `SUDO_ENV = "SPECTRE_MCP_ALLOW_SUDO"`
  - `Decision` dataclass: `allowed: bool`, `status: str` (`"ok" | "confirmation_required" | "refused"`), `reason: str | None = None`
  - `def allow_mutations() -> bool`
  - `def allow_sudo() -> bool`
  - `def is_root() -> bool`
  - `def evaluate(*, confirm: bool, mutates: bool, sudo: bool, mutations_enabled: bool, sudo_enabled: bool, root: bool) -> Decision`

**Steps:**
- [ ] **Step 1: Write the failing tests**

Pin: `confirm=False` → `Decision(allowed=False, status="confirmation_required")`; `confirm=True, mutates=True, mutations_enabled=False` → `refused`; `confirm=True, sudo=True, root=False` → `refused`; `confirm=True, sudo=True, root=True, sudo_enabled=False` → `refused`; `confirm=True, mutates=True, mutations_enabled=True, sudo=True, root=True, sudo_enabled=True` → `allowed=True, status="ok"`.
- [ ] **Step 2: Run test to verify it fails** — `pytest tests/agent/test_mcp_policy.py -q` → FAIL on import.
- [ ] **Step 3: Implement** `policy.py` per interface.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 3: Redaction module

**Files:**
- Create: `spectre/mcp/redact.py`
- Create: `tests/agent/test_mcp_redact.py`

**Interfaces:**
- Produces: `REDACTED = "[REDACTED]"`, `def redact_text(text: str) -> tuple[str, bool]`, `def redact(value: Any) -> tuple[Any, bool]`.

**Steps:**
- [ ] **Step 1: Write failing tests** — pin replacement of private-key block, bearer token, `password = "longvalue..."` assignment, and known token prefix; pin ordinary text unchanged; pin `redact` recursion through nested dicts/lists and that it leaves non-strings alone.
- [ ] **Step 2: Run test to verify it fails** — FAIL on import.
- [ ] **Step 3: Implement** with the regexes from the design (private key block, bearer, assignment, known prefix).
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 4: Service read methods and serializers

**Files:**
- Create: `spectre/mcp/service.py`
- Create: `tests/agent/test_mcp_service.py`

**Interfaces:**
- Produces: `class SpectreService`:
  - `status(agent: str | None = None) -> dict[str, Any]`
  - `health() -> dict[str, Any]`
  - `actions_list(group: str | None = None, include_runs: bool = True) -> dict[str, Any]`
  - `action_show(job: str) -> dict[str, Any]`
  - `actions_verify() -> dict[str, Any]`
  - `runs(limit: int = 20, job: str | None = None) -> dict[str, Any]`
  - `workflows_list() -> dict[str, Any]`
  - `workflow_history(limit: int = 20, workflow: str | None = None) -> dict[str, Any]`
  - `events(event_type: str | None = None, limit: int = 20) -> dict[str, Any]`
  - `reports_list(report_type: str | None = None, limit: int = 20) -> dict[str, Any]`
  - `report_get(report_id: int) -> dict[str, Any]`
  - `security_summary() -> dict[str, Any]`
  - `config_show() -> dict[str, Any]`
  - `config_get(key: str, profile: str = "default") -> dict[str, Any]`
  - `schedule_list() -> dict[str, Any]`
  - `version() -> dict[str, Any]`

**Steps:**
- [ ] **Step 1: Write failing tests** — pin serialization shapes for jobs/runs/reports/events/workflow runs/security summary/version, `actions_list` group filtering, `runs` job filtering, `report_get` not found, `status` unknown-agent error capture, `config_show` redaction flag.
- [ ] **Step 2: Run test to verify it fails** — FAIL on import.
- [ ] **Step 3: Implement** serializers and read methods, delegating to existing modules (`spectre.dispatch.registry.JOBS`, `resolve`, `spectre.memory.db`, `spectre.workflow_engine.engine`).
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 5: Service act methods and gating

**Files:**
- Modify: `spectre/mcp/service.py` (add act methods + helpers `_truncated(text)`, `_serialize_*` for runs)
- Modify: `tests/agent/test_mcp_service.py` (add act tests)

**Interfaces:**
- Produces:
  - `def action_run(self, job: str, args: list[str] | None = None, confirm: bool = False, timeout_seconds: int | None = None) -> dict[str, Any]`
  - `def workflow_run(self, name: str, confirm: bool = False) -> dict[str, Any]`
  - `def config_set(self, key: str, value: str, profile: str = "default", confirm: bool = False) -> dict[str, Any]`
  - `def schedule_add(self, name: str, schedule: str, workflow: str, confirm: bool = False) -> dict[str, Any]`
  - `def schedule_remove(self, name: str, confirm: bool = False) -> dict[str, Any]`

**Steps:**
- [ ] **Step 1: Write failing tests** — pin: preview path (`confirm=False`) returns `status="confirmation_required"` without touching the runner; mutating job + `confirm=True` + gate off returns `refused`; read-only job + `confirm=True` runs via monkeypatched `run_action`/`JobLock` and returns envelope fields; `config_set` preview does not include the old value; `schedule_add` returns `scheduled: false` with the note.
- [ ] **Step 2: Run test to verify it fails**.
- [ ] **Step 3: Implement** act methods using `policy.evaluate`, `registry.get_job`, `resolve`, `JobLock`, `run_action`, `init_db`/`save_run`, `WorkflowEngine.run_workflow`, config/schedule DB functions, redaction + truncation before return.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 6: MCP server tool registration and in-memory client tests

**Files:**
- Modify: `spectre/mcp/server.py`
- Create: `tests/agent/test_mcp_server.py`

**Interfaces:**
- Consumes: `SpectreService` (Task 4/5), policy/redact (Tasks 2/3).
- Produces: module-level `mcp: MCPServer` exposing 21 tools: read — `spectre_status`, `spectre_health`, `spectre_actions_list`, `spectre_action_show`, `spectre_actions_verify`, `spectre_runs`, `spectre_workflows_list`, `spectre_workflow_history`, `spectre_events`, `spectre_reports_list`, `spectre_report_get`, `spectre_security_summary`, `spectre_config_show`, `spectre_config_get`, `spectre_schedule_list`, `spectre_version`; act — `spectre_action_run`, `spectre_workflow_run`, `spectre_config_set`, `spectre_schedule_add`, `spectre_schedule_remove`.
- Produces: `def main() -> None` calling `mcp.run()`.

**Steps:**
- [ ] **Step 1: Write failing tests** — in-memory client: list tools returns the 21 names; read tool `spectre_actions_list` returns jobs through the service; `spectre_health` tool annotation is `readOnlyHint=false`; unknown job via `spectre_action_run`/`spectre_action_show` returns `unknown_job` in the result.
- [ ] **Step 2: Run test to verify it fails** — FAIL on missing tool.
- [ ] **Step 3: Implement** tool functions as sync `def` handlers wrapping the service, with annotations and structured dicts.
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 7: Subprocess stdio smoke test, docs, full verification

**Files:**
- Create: `tests/agent/test_mcp_stdio.py`
- Modify: `README.md`
- Create: `docs/MCP.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `spectre.mcp.server:main`, `spectre.mcp` package.
- Produces: working stdio server that launches over subprocess via MCP client; docs for install, env vars, tool table, safety model.

**Steps:**
- [ ] **Step 1: Write failing subprocess smoke test** — launch `/home/deon/.local/share/spectre-venv/bin/spectre-mcp` (or `python -m spectre.mcp`) via `mcp.client.stdio.StdioServerParameters`/`stdio_client`, initialize, list tools, assert non-empty, close. Expected: FAIL before wiring is complete.
- [ ] **Step 2: Run test to verify it passes** after task 6.
- [ ] **Step 3: Write docs** — `README.md` MCP section (install, env vars, OpenCode snippet), `docs/MCP.md` (tool table, safety model, redaction, schedule note), `CHANGELOG.md` entry under a new `1.1.0` section.
- [ ] **Step 4: Full verification** — run:
  - `/home/deon/.local/share/spectre-venv/bin/python -m pytest tests/agent -q`
  - `/home/deon/.local/share/spectre-venv/bin/python -m ruff check spectre/mcp tests/agent/test_mcp_*.py`
  - `/home/deon/.local/share/spectre-venv/bin/python -m mypy spectre/mcp`
  - `bash tests/run_tests.sh`
- [ ] **Step 5: Install and manual smoke** — `uv pip install -e '.[mcp]'` into `/home/deon/.local/share/spectre-venv`; confirm the console script and module entry exist; commit docs.

## Self-Review

1. **Spec coverage:** each spec section maps to tasks — package/packaging (1), policy (2), redaction (3), read (4), act (5), server+tests (6), docs+verify (7).
2. **Step scan:** every step is one action with a checkable result; bodies only where signature/tests leave a choice.
3. **Type consistency:** task interfaces use the exact names from Task 2/3/4/5; Task 6 must use the same tool names.
4. **Review Focus:** listed above; each has a pinning test in its owning task.
5. **Proportion:** plan tasks reference code blocks only for tests and signatures.

## Approval

Approved via conversation 2026-11-28.
