"""Dispatch verify: recognize migrated `spectre run` scheduler forms."""

from spectre.dispatch.verify import HostInventory, _scheduler_findings


def _legacy_details(findings):
    return [f.detail for f in findings if f.code == "legacy-path"]


def test_python_module_dispatcher_form_is_not_legacy_path(tmp_path):
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


def test_spectre_binary_dispatcher_form_is_not_legacy_path(tmp_path):
    inventory = HostInventory(
        cron_entries=[("*/5 * * * *", "/usr/local/bin/spectre run maintenance/system-health-check")],
        unit_exec_starts=[],
    )
    assert _legacy_details(_scheduler_findings(inventory)) == []
