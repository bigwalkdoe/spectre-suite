"""Dispatch verify: recognize migrated `spectre run` scheduler forms."""

from pathlib import Path

from spectre.dispatch.verify import HostInventory, _scheduler_findings


def _legacy_details(findings):
    return [f.detail for f in findings if f.code == "legacy-path"]


def test_python_module_dispatcher_form_is_not_legacy_path():
    """`python3 -m spectre.cli.main run <job>` is a migrated dispatch form.

    Repo-managed/user systemd units often invoke the checkout this way; the
    verifier must not misclassify the job id as an unresolved script path.
    """
    inventory = HostInventory(
        cron_entries=[],
        unit_exec_starts=[
            (
                "spectre-security-baseline-metrics.service",
                "ExecStart=/usr/bin/python3 -m spectre.cli.main run prometheus/security-baseline-metrics-exporter",
            )
        ],
    )
    assert _legacy_details(_scheduler_findings(inventory)) == []


def test_spectre_cli_module_dispatcher_form_is_not_legacy_path():
    inventory = HostInventory(
        cron_entries=[],
        unit_exec_starts=[("u.service", "ExecStart=/usr/bin/python3 -m spectre.cli run backups/backup-all")],
    )
    assert _legacy_details(_scheduler_findings(inventory)) == []


def test_spectre_binary_dispatcher_form_is_not_legacy_path():
    inventory = HostInventory(
        cron_entries=[("*/5 * * * *", "/usr/local/bin/spectre run maintenance/system-health-check")],
        unit_exec_starts=[],
    )
    assert _legacy_details(_scheduler_findings(inventory)) == []


def test_migrated_dispatch_skips_only_job_arg_and_still_flags_other_spectre_paths():
    """Only the dispatched job argument is skipped; other visible Spectre-owned
    script paths in the same command remain legacy references.
    """
    repo = Path(__file__).resolve().parents[3]
    legacy = repo / "spectre" / "actions" / "backups" / "legacy-example.sh"
    inventory = HostInventory(
        cron_entries=[],
        unit_exec_starts=[
            (
                "wrapper.service",
                f"ExecStart=/usr/bin/python3 -m spectre.cli.main run backups/backup-all -- {legacy}",
            )
        ],
    )
    details = _legacy_details(_scheduler_findings(inventory))
    assert len(details) == 1
    assert "wrapper.service" in details[0]
    assert "legacy-example.sh" in details[0]


def test_actual_legacy_spectre_script_path_is_still_reported():
    repo = Path(__file__).resolve().parents[3]
    legacy = repo / "spectre" / "monitoring" / "exporters" / "security-baseline-metrics-exporter.sh"
    inventory = HostInventory([], [("x.service", f"ExecStart={legacy}")])
    details = _legacy_details(_scheduler_findings(inventory))
    assert len(details) == 1
    assert "security-baseline-metrics-exporter.sh" in details[0]
