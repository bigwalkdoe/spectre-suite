# Spectre MCP Server

A local stdio MCP server that exposes Spectre's observe and act surfaces as MCP
tools. It reuses the existing registry, dispatch runner, database, and workflow
engine; it is not a second source of truth.

## Install

```bash
uv pip install -e '.[mcp]' --python /home/deon/.local/share/spectre-venv/bin/python
```

The server runs over stdio and is launched by the client. Entry points:

- Console script: `spectre-mcp`
- Module: `python -m spectre.mcp`

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `SPECTRE_MCP_ALLOW_MUTATIONS` | off | Permit mutating jobs, workflow runs, config writes, and schedule changes. |
| `SPECTRE_MCP_ALLOW_SUDO` | off | Permit root jobs, but only when the process is already root. |
| `SPECTRE_MCP_LOG_LEVEL` | `INFO` | Logging threshold (stderr only). |
| `SPECTRE_MCP_MAX_ROWS` | `200` | Upper bound for list tools. |

`SPECTRE_CONFIG_DIR` is honored by the database layer, so tests can point the
server at a throwaway tree.

## Tools

Read tools (annotated `readOnlyHint=true` unless noted):

| Tool | Arguments | Notes |
|---|---|---|
| `spectre_status` | `agent?` | Per-agent `observe()` results; a failing agent becomes `{"error": ...}`. |
| `spectre_health` | — | `collect-metrics` + `check-thresholds`. Annotated `readOnlyHint=false` (it writes records). |
| `spectre_actions_list` | `group?, include_runs?` | Jobs with metadata and run counts. |
| `spectre_action_show` | `job` | Registry entry plus resolved path, commit, dirty flag. |
| `spectre_actions_verify` | — | Seven preflight codes, counts, blocking verdict. |
| `spectre_runs` | `limit?, job?` | Recent dispatch records. |
| `spectre_workflows_list` | — | Workflow names, descriptions, steps. |
| `spectre_workflow_history` | `limit?, workflow?` | Recent workflow runs. |
| `spectre_events` | `event_type?, limit?` | EventBus rows. |
| `spectre_reports_list` | `report_type?, limit?` | Report metadata. |
| `spectre_report_get` | `report_id` | Report metadata and content. |
| `spectre_security_summary` | — | Security exposure summary. |
| `spectre_config_show` | — | YAML settings (secret-looking keys redacted). |
| `spectre_config_get` | `key, profile?` | One database configuration value. |
| `spectre_schedule_list` | — | Tasks from both stores, labeled by source. |
| `spectre_version` | — | Spectre version, Python, platform. |

Act tools (annotated `destructiveHint=true`):

| Tool | Arguments | Notes |
|---|---|---|
| `spectre_action_run` | `job, args?, confirm?, timeout_seconds?` | Runs one registered job. |
| `spectre_workflow_run` | `name, confirm?` | Runs one workflow. |
| `spectre_config_set` | `key, value, profile?, confirm?` | Writes one database value. |
| `spectre_schedule_add` | `name, schedule, workflow, confirm?` | Records a task (see caveat). |
| `spectre_schedule_remove` | `name, confirm?` | Removes a task. |

## Safety model

- `SPECTRE_MCP_ALLOW_MUTATIONS=1` is the real authorization. Mutating jobs,
  workflow runs, config writes, and schedule changes are refused without it.
- `SPECTRE_MCP_ALLOW_SUDO=1` plus a root process is required for root jobs.
  Otherwise the tool returns the exact `sudo spectre run ...` command.
- Every act tool takes `confirm=true`. Without it the tool returns a preview and
  executes nothing. `confirm=true` is a transcript courtesy, not proof that a
  human approved: an agent can call preview and confirm in one turn. The
  environment gate is the boundary.
- Arguments are passed as an argv list; there is no shell.
- Act tools are serialized with a process-wide lock; the dispatch job lock still
  applies per job.
- Workflow runs are treated as mutating and run unprivileged. A step that needs
  root fails and is reported; the workflow holds the act lock until it finishes
  and has no deadline. Client cancellation does not stop it.

## Previews

- `spectre_action_run`: job metadata, resolved path, git commit and dirty flag,
  and which gates are open.
- `spectre_workflow_run`: name, description, steps, server user, mutation gate.
- `spectre_config_set`: key, profile, proposed value, whether the key exists.
  The current value is never echoed.
- `spectre_schedule_add`: name, schedule, workflow, whether the workflow exists.
- `spectre_schedule_remove`: name and the stored schedule/workflow if present.

## Redaction

A shared best-effort redactor runs over every result before it is returned:
private-key blocks, bearer tokens, `password`/`secret`/`api_key`/`token`
assignments, and known token prefixes (`sk-`, `ghp_`, `github_pat_`, `xox*-`).
Replacement is `[REDACTED]` and the result carries `redacted: true` when a
replacement happened. This is best-effort, not a guarantee.

Embedded text fields are truncated at 16 KiB (head and tail kept around an
elision marker). List tools cap `limit` at `SPECTRE_MCP_MAX_ROWS`.

## Schedule caveat

`spectre_schedule_add` writes the same `scheduled_tasks` database key as the
CLI and API, but the daemon only reads `schedules` from `settings.yaml`. A task
added this way is recorded intent, runnable with `spectre schedule run`, not a
live timer. The tool reports `scheduled: false` and a note. `spectre_schedule_list`
reads both stores and labels each entry's source (`database` or `settings`).

## Client example (OpenCode)

```json
{
  "mcp": {
    "spectre": {
      "type": "local",
      "command": ["/home/deon/.local/share/spectre-venv/bin/spectre-mcp"],
      "enabled": true,
      "environment": {
        "SPECTRE_MCP_ALLOW_MUTATIONS": "1"
      }
    }
  }
}
```
