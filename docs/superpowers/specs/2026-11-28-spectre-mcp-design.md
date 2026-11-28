# Spectre MCP Server — Design

**Date:** 2026-11-28
**Status:** Draft for approval
**Scope:** A local MCP server that exposes Spectre's existing observe and act
surfaces to MCP clients.

## Intent

Spectre already has three operator surfaces: the `spectre` CLI, the FastAPI REST
API on `127.0.0.1:8106`, and the static web dashboard. An MCP client (OpenCode,
Claude Desktop, or another agent) currently has to shell out to the CLI and parse
Rich tables to see system state, and has no structured way to run a registered
job. This design adds a fourth surface: a local stdio MCP server that reuses the
existing registry, dispatch runner, database, and workflow engine rather than
reimplementing them.

The server is for one host and one operator. It is not a remote control plane.

## Goals

- Expose Spectre's read surfaces as MCP tools: status, health, registry, runs,
  workflows, events, reports, security summary, configuration, schedule, version.
- Expose the act surfaces with explicit gates: run one registered job, run one
  workflow, write a configuration value, add or remove a scheduled task.
- Reuse `spectre.dispatch` for execution so locks, timeouts, provenance, and
  output bounds behave exactly as they do for the CLI.
- Never corrupt the MCP stdio protocol, and never block the server's event loop.
- Be testable without a subprocess, with one subprocess smoke test to prove the
  stdio transport is clean.

## Non-goals

- HTTP/SSE transport, OAuth, multi-host fan-out, or remote access in v1.
- Running a whole job group (the CLI has `run_group`; this server starts with one
  job per call).
- New maintenance capabilities that Spectre does not already have.
- Changes to the REST API, dashboard, or systemd units.
- Replacing the CLI or the API.

## Anti-goals

- A second source of truth for job metadata. The registry is authoritative.
- An agent silently running a mutating or root action. Every act is gated and
  visible in the tool result.
- Any library `print()` reaching stdout. Stdout is the protocol channel.
- Long-running work on the event-loop thread.

## Constraints

- The package must install into the existing venv at
  `/home/deon/.local/share/spectre-venv` (Python 3.12).
- The MCP Python SDK is `mcp>=2.3,<3`. In v2, synchronous tool functions run in
  worker threads via `anyio.to_thread.run_sync()`, so blocking library calls are
  safe but may run concurrently.
- SQLite is configured with WAL and a busy timeout, so concurrent reads are safe;
  act tools will still be serialized.
- The dispatch runner returns a bounded `Envelope` (64 KiB per stream) and never
  raises for a failed action. A failed run is a normal result.
- The server process is not root when launched by a desktop MCP client. Root
  jobs must be refused rather than half-attempted.
- `spectre.dispatch.resolve` refuses actions outside the actions root and
  requires the action file to be executable. The MCP server inherits that.
- Workflows are a different execution path from registry jobs. They run agent
  actions in-process as the server's user, with no sudo escalation and no
  per-step `mutates` metadata.

## Approaches considered

**A. In-process Python MCP server (chosen).** New `spectre/mcp/` package using
the official SDK. Read tools call the library directly; act tools use
`resolve` → `JobLock` → `run_action` → `save_run`. Full registry metadata, real
lock and provenance semantics, no REST dependency. Cost: heavy imports, and the
server must keep stdout clean.

**B. HTTP proxy to the REST API.** Reuses the API key and process isolation, but
the API has no registry, action, or job-execution endpoints today. Building them
first enlarges the API's security surface and makes the MCP useless when the API
is down. Rejected for v1.

**C. CLI subprocess wrapper.** Simple isolation, but only `spectre status` emits
JSON; every other command emits Rich tables. Parsing them is brittle, and we
would end up adding `--json` to a dozen commands. Rejected.

## Design

### Package layout

```
spectre/mcp/__init__.py
spectre/mcp/server.py      # MCPServer instance, tool registration, main()
spectre/mcp/service.py     # data access and dispatch orchestration
spectre/mcp/policy.py      # environment gates and confirm/preview decisions
spectre/mcp/redact.py      # shared best-effort secret redaction
```

`server.py` contains no business logic. Each `@mcp.tool()` function validates
arguments, delegates to a `SpectreService` method, and returns the result dict.
`service.py` owns serialization and calls the existing modules. `policy.py` and
`redact.py` are small, independently testable modules so the safety rules are not
buried in tool bodies.

Confirmed SDK facts for 2.3.0:

- `from mcp.server import MCPServer` (also `from mcp.server.mcpserver import MCPServer`).
- `from mcp.types import ToolAnnotations`.
- `from mcp.server.mcpserver.exceptions import ToolError`.
- `from mcp import Client`; `Client(mcp)` connects in memory for tests.
- `MCPServer.run()` defaults to the stdio transport.

### Packaging

- Add an optional extra: `mcp = ["mcp>=2.3,<3"]`.
- Add the console script: `spectre-mcp = "spectre.mcp.server:main"`.
- The wheel already packages `spectre/`, so `spectre/mcp/` is included.
- Install for this host with `uv pip install -e '.[mcp]'` into
  `/home/deon/.local/share/spectre-venv`.

The extra keeps the MCP SDK out of installations that do not use it. The console
script is always installed; if the extra is missing it exits with a clear message
telling the operator to install `spectre[mcp]`. `install.sh` is unchanged; its
`pip install "$REPO_ROOT"` path installs the script but not the extra, and the
clear error is the intended behavior until the installer grows an opt-in flag.

### Runtime configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `SPECTRE_MCP_ALLOW_MUTATIONS` | unset (off) | Permit jobs with `mutates=true`, workflow runs, config writes, and schedule changes. |
| `SPECTRE_MCP_ALLOW_SUDO` | unset (off) | Permit `sudo=true` jobs, but only when the process is already root. |
| `SPECTRE_MCP_LOG_LEVEL` | `INFO` | Logging threshold; logs go to stderr. |
| `SPECTRE_MCP_MAX_ROWS` | `200` | Upper bound for list tools that accept a `limit`. |

`SPECTRE_CONFIG_DIR` is honored by `spectre.memory.db` and lets tests point the
server at a throwaway tree.

Transport is stdio only in v1: `mcp.run()` with the default transport. Logging is
configured with `logging.StreamHandler(sys.stderr)`. No module may call `print`.

### Safety model

Every act tool takes `confirm: bool = False`. The behavior is:

1. **No `confirm`:** return a preview and execute nothing.
2. **`confirm=true`, but the action mutates and mutations are not enabled:**
   return `status="refused"` with the environment variable to set.
3. **`confirm=true`, job needs root, but the process is not root:** return
   `status="refused"` with the exact `sudo spectre run ...` command.
4. **`confirm=true`, job needs root, process is root, but
   `SPECTRE_MCP_ALLOW_SUDO` is off:** return `status="refused"`.
5. **All gates open:** acquire the act lock, take the job lock, resolve, run, save
   the run record, and return the envelope.

**The environment gate is the authorization; the preview is a courtesy.** The
operator authorizes mutating capability once, when launching the server with
`SPECTRE_MCP_ALLOW_MUTATIONS=1`. `confirm=true` makes the two-step shape visible
in the transcript, but it does not prove a human saw the preview — an agent can
call preview and confirm in one turn. A nonce would prove two calls and nothing
more, and MCP elicitation would depend on client support. Neither is in v1. The
docs say this plainly so the env var is not mistaken for a prompt.

Workflow runs are treated as mutating regardless of their steps, because a
workflow is a composite that can change the host. `config_set` and the schedule
tools are treated as mutating for the same reason.

Workflows are **not** root-gated: they have no static privilege metadata, the
CLI runs them unprivileged, and escalating a composite would mean deciding how a
privileged process is authenticated inside a maintenance tool. A workflow step
that needs root fails as that agent's action fails; the workflow reports the
step result and the overall status. The preview says the workflow will run as the
server's user.

Act tools are serialized with a process-wide `threading.Lock`. Two concurrent MCP
requests must not dispatch two jobs at once; the job lock protects the same job,
but the act lock protects the host. Read tools remain concurrent.

Arguments for an action are passed as an argv list to `run_action`; there is no
shell. The MCP client cannot inject a command through a string.

### Previews

| Tool | Preview fields |
| --- | --- |
| `spectre_action_run` | Job metadata (`name`, `group`, `summary`, `sudo`, `mutates`, `timeout`, `concurrency`, `schedule_hint`), resolved path, git commit, dirty flag, and which gates are open. |
| `spectre_workflow_run` | Workflow name, description, steps as `{agent, action}`, the server user, and whether the mutation gate is open. |
| `spectre_config_set` | Key, profile, proposed value, whether the key currently exists, and the mutation gate. The current value is **not** echoed. |
| `spectre_schedule_add` | Name, schedule, workflow, whether the workflow exists, and the mutation gate. |
| `spectre_schedule_remove` | Name, the stored schedule and workflow if the task exists, and the mutation gate. |

### Error and result model

All tools return a JSON object. Expected outcomes are values, not exceptions:

- Success: `{"ok": true, ...}`.
- Policy refusal: `{"ok": false, "status": "confirmation_required" | "refused", "reason": "..."}`.
- Unknown job or workflow: `{"ok": false, "status": "unknown_job" | "unknown_workflow", ...}`.
- Invalid input: `{"ok": false, "status": "invalid_argument", "reason": "..."}`.

Unexpected exceptions are logged with a traceback to stderr and re-raised so the
SDK reports an internal error; they are not disguised as a normal result.
`ToolError` is reserved for argument validation the SDK should report as a tool
error.

### Result bounds and redaction

Every text field that can be large is bounded before it leaves the service:

- `spectre_runs`: `stdout_tail` and `stderr_tail` are truncated with
  `spectre.dispatch.envelope.truncate_output(text, 16384)` (head and tail kept
  around an elision marker).
- `spectre_report_get`: `content` is truncated the same way.
- `spectre_workflow_history`: step details are truncated the same way.
- `spectre_events`: `data_json` is parsed when possible and truncated when not.
- List tools clamp `limit` to `[1, SPECTRE_MCP_MAX_ROWS]`.

A shared redactor (`redact.py`) runs over every string in every result before it
is returned. It is conservative and pattern-based:

- `-----BEGIN ... PRIVATE KEY-----` blocks.
- `Authorization: Bearer <token>` and bare `Bearer <token>`.
- Assignments of `password`, `passwd`, `secret`, `api_key`, `apikey`,
  `access_token`, `auth_token`, or `token` to a quoted or unquoted value.
- Long `sk-`/`ghp_`/`github_pat_`/`xox[baprs]-` style tokens.

Replacement is `[REDACTED]`. When anything is replaced, the top-level result
carries `"redacted": true`. This is best-effort, not a guarantee; the docs say so.
Redaction is applied after truncation so a secret cannot be split across the
boundary and survive, and before serialization so it covers nested dicts and
lists.

### Tool surface

Read tools:

| Tool | Arguments | Returns |
| --- | --- | --- |
| `spectre_status` | `agent: str \| None = None` | Per-agent `observe()` results; errors captured per agent. |
| `spectre_health` | none | `collect-metrics` and `check-thresholds` results from the monitoring agent. |
| `spectre_actions_list` | `group: str \| None = None`, `include_runs: bool = True` | Jobs with `name`, `group`, `summary`, `sudo`, `mutates`, `timeout`, `concurrency`, `schedule_hint`, and run count. |
| `spectre_action_show` | `job: str` | Registry entry plus resolved path, git commit, and dirty flag. |
| `spectre_actions_verify` | none | Findings, per-code counts, blocking verdict, and unreadable sources. |
| `spectre_runs` | `limit: int = 20`, `job: str \| None = None` | Recent dispatch records. |
| `spectre_workflows_list` | none | Workflow names, descriptions, and steps. |
| `spectre_workflow_history` | `limit: int = 20`, `workflow: str \| None = None` | Workflow run records. |
| `spectre_events` | `event_type: str \| None = None`, `limit: int = 20` | Event log rows. |
| `spectre_reports_list` | `report_type: str \| None = None`, `limit: int = 20` | Report metadata. |
| `spectre_report_get` | `report_id: int` | Report metadata and content. |
| `spectre_security_summary` | none | The same summary the API serves. |
| `spectre_config_show` | none | YAML settings with secret-looking fields redacted. |
| `spectre_config_get` | `key: str`, `profile: str = "default"` | One database configuration value. |
| `spectre_schedule_list` | none | Tasks from both stores, labeled by source. |
| `spectre_version` | none | Spectre version, Python version, platform. |

Act tools:

| Tool | Arguments | Notes |
| --- | --- | --- |
| `spectre_action_run` | `job: str`, `args: list[str] = []`, `confirm: bool = False`, `timeout_seconds: int \| None = None` | `timeout_seconds` is clamped to `job.timeout`; default is `job.timeout`. |
| `spectre_workflow_run` | `name: str`, `confirm: bool = False` | Mutating gate; no deadline in v1. |
| `spectre_config_set` | `key: str`, `value: str`, `profile: str = "default"`, `confirm: bool = False` | Mutating gate. |
| `spectre_schedule_add` | `name: str`, `schedule: str`, `workflow: str`, `confirm: bool = False` | Validates that the workflow exists. Mutating gate. |
| `spectre_schedule_remove` | `name: str`, `confirm: bool = False` | Mutating gate. |

Tool names are prefixed with `spectre_` so they read unambiguously in a client
that aggregates several servers.

Annotations:

- Read tools: `readOnlyHint=true`, except `spectre_health`, which writes
  `MaintenanceRecord` rows through the monitoring agent and is therefore
  annotated `readOnlyHint=false`. It is not mutation-gated because it does not
  change host state.
- Act tools: `destructiveHint=true` for `spectre_action_run` and
  `spectre_workflow_run`; `idempotentHint=true` for the config and schedule
  writers where the same input yields the same stored state.

### Execution path for `spectre_action_run`

1. Look up the job in `spectre.dispatch.registry`; return `unknown_job` on
   `KeyError`.
2. `resolve(job)`; return `status="error"` with the dispatch error if the action
   is missing, non-executable, or outside the actions root.
3. Apply the policy gates from `policy.py`. Return a preview or refusal as
   described above.
4. Acquire the act lock.
5. Open `JobLock(job)`; on `LockUnavailable`, return `status="locked"` with the
   holder's pid and start time.
6. Call `run_action(resolved, args, trigger="mcp", timeout=timeout)`.
7. `init_db()` and `save_run(envelope)`.
8. Return `job`, `status`, `exit_code`, `duration_ms`, `resolved_path`,
   `git_commit`, `git_dirty`, `stdout_tail`, `stderr_tail`, and `payload`.

`trigger="mcp"` makes MCP-dispatched runs distinguishable from CLI, cron, and
systemd runs in the provenance record.

### Read-tool semantics

- `spectre_status` does **not** build a `WorkflowEngine`. The engine's constructor
  initializes all eight agents, and the AI agent makes a 3-second Ollama HTTP
  call. The service calls `_register_default_factories()` and instantiates only
  the requested agent (or each agent in turn for an all-agent call) from
  `_AGENT_FACTORIES`, then calls `initialize()` and `observe()`. A failing agent
  becomes `{"error": "..."}` rather than failing the whole call.
- `spectre_health` instantiates only the monitoring agent the same way and runs
  `collect-metrics` and `check-thresholds`.
- `spectre_actions_list` reads the registry and, when `include_runs` is true,
  `record_growth()`. A missing or unreadable run store yields `null` counts, not
  an error.
- `spectre_actions_verify` calls `read_host_inventory()` and `verify()`, then
  reports the same seven codes and blocking/advisory split as the CLI.
- `spectre_schedule_list` reads the database `scheduled_tasks` key (CLI/API
  source) and the `schedules` list from `load_settings()` (daemon source), and
  labels each entry with its source. The two stores are not merged or
  deduplicated.
- `spectre_schedule_add` and `spectre_schedule_remove` operate on the database
  key, matching the CLI and API. Their results include
  `"scheduled": false` and a note that the daemon does not consume this key; the
  task is recorded intent, runnable with `spectre schedule run`, not a timer.
  This is stated in the tool result and the docs rather than silently reporting
  success.
- `spectre_config_show` returns the YAML settings; `spectre_config_get` reads one
  database value. They are different stores and the docs say so.
- Datetimes are ISO-8601 strings; enums are their lowercase values; ORM rows are
  converted field by field, never `dict(row)`.

### Concurrency and threading

Sync tools run in worker threads. The service uses no thread-local state. The
database engine is already `check_same_thread=False` with WAL. The only shared
mutable state is the act lock and a module-level lock that guards one-time agent
factory registration. `WorkflowEngine` is created lazily only for workflow tools,
under that lock.

### Testing

`tests/agent/test_mcp.py`, guarded by `pytest.importorskip("mcp")` so the suite
still runs without the optional extra.

In-memory tests with `mcp.Client(mcp)`:

- The expected tool names are registered.
- `spectre_actions_list` returns 90 jobs and the registry metadata.
- `spectre_action_show` returns a resolved path for a known job and
  `unknown_job` for a typo.
- `spectre_action_run` without `confirm` returns `confirmation_required` and
  does not call the runner (monkeypatched).
- A mutating job with `confirm=true` and no env gate returns `refused`.
- A read-only job with `confirm=true` calls a monkeypatched `run_action` and
  returns the envelope fields.
- `spectre_workflow_run`, `spectre_config_set`, and the schedule tools enforce
  the mutating gate.
- `config_set` → `config_get` and `schedule_add` → `schedule_list` →
  `schedule_remove` round-trip against the test database; `schedule_add` reports
  `scheduled: false`.
- `spectre_status` with a monkeypatched factory does not instantiate unrelated
  agents.
- The redactor replaces a private key, a bearer token, and a `password=`
  assignment in a nested result and sets `redacted: true`.
- Run/report text over the bound is truncated with the elision marker.
- `spectre_version` returns a version string.

Subprocess smoke test:

- Launch the server with stdio transport, initialize a client, list tools, and
  close. This proves no library output leaks onto stdout.

Existing gates:

- `pytest tests/agent` passes.
- `ruff check` and `mypy` pass on the new package.
- `bash tests/run_tests.sh` still passes.
- Manual: register the server in OpenCode and call `spectre_status`,
  `spectre_actions_list`, and a confirmed read-only job.

### Documentation and install

- Add an "MCP server" section to `README.md` with the install command, the env
  vars, and an OpenCode `mcp` configuration snippet.
- Add `docs/MCP.md` with the tool table, safety model, redaction limits, and
  client examples.
- No systemd unit: a stdio server is launched by the client, not by the user
  session.
- Bump the project version to `1.1.0` and add a `CHANGELOG.md` entry.

## Risks

- **Long jobs and workflows versus client timeouts.** A job may run for up to
  `job.timeout` (1800 s by default). A workflow has no deadline at all: the
  engine runs it synchronously, holds the act lock until it finishes, and a
  client cancellation does not stop it. If the client times out, the work still
  completes and is recorded, but the client does not see the result. The action
  preview returns the job timeout; the workflow preview lists every step. A
  future iteration can add background runs and a `spectre_run_status` tool.
- **stdout pollution.** Any `print` in Spectre or a dependency would corrupt the
  protocol. The subprocess smoke test is the guard. If a dependency proves noisy,
  the fix is to route that library's logging to stderr, not to wrap stdout.
- **Redaction is best-effort.** A secret that does not match the patterns reaches
  the client. The docs state this and the result carries `redacted` only when a
  replacement happened.
- **SDK churn.** `mcp` 2.x is young. Pin `<3` and keep the SDK usage confined to
  `server.py`.
- **Heavy imports.** `spectre.api` and the workflow engine pull FastAPI and agent
  modules. Import them lazily inside the service methods so a client that only
  lists the registry starts quickly.

## What is left to the builder

- Measure `spectre_status` latency with direct agent instantiation; add a
  per-agent timeout if an `observe()` implementation is slow.
- Decide whether `spectre_group_run` belongs in the first iteration.
- Decide whether the optional extra or a core dependency is the better install
  experience after trying the editable install.
- Choose the exact redaction regexes and test fixtures.

## Review decisions

- **Act authorization:** env gate plus preview; no nonce, no elicitation in v1.
- **Redaction:** best-effort shared redactor over every result.
- **Schedule tools:** mirror the CLI/API database key and report
  `scheduled: false` with the daemon limitation.
- **Workflow privilege:** unprivileged, ungated by sudo, partial failure
  reported.
- **Health annotation:** not read-only because it writes records; not mutation
  gated because it does not change host state.
- **Result bounds:** 16 KiB per embedded text field, row limits capped.
- **Previews:** specified for all five act tools; `config_set` does not echo the
  old value.
- **Status:** direct agent instantiation, not `WorkflowEngine`.
- **Verify codes:** seven, matching `verify.ALL_CODES`.

## Approval

Approved by: _pending_
