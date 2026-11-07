#!/bin/bash
# Spectre Security Baseline Metrics Exporter (textfile)
#
# Emits canonical spectre_security_baseline_* metrics from baseline pipeline
# evidence (suite baseline runner logs and/or spectre-security logs) with
# explicit never-run/unknown/stale semantics. Distinct from spectre_agent_*
# runtime agent availability/findings.
set -uo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
OUTPUT_DIR="${1:-$_REPO_ROOT/prometheus/business-metrics}"
OUT="$OUTPUT_DIR/security_baseline_metrics.prom"
TMP="$OUTPUT_DIR/.security_baseline_metrics.prom.$$"

SUITE_LOG_DIR="${SECURITY_BASELINE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
SEC_ROOT="${SPECTRE_SECURITY_ROOT:-~//dev/github/spectre-security}"
SEC_LOG_DIR="${SECURITY_BASELINE_COMPAT_LOG_DIR:-$SEC_ROOT/security/logs}"
STALE_SECONDS="${SPECTRE_SECURITY_BASELINE_STALE_SECONDS:-172800}" # 48h

mkdir -p "$OUTPUT_DIR"
now=$(date +%s)

emit() { printf '%s\n' "$@" >> "$TMP"; }
gauge_help() { emit "# HELP $1 $2" "# TYPE $1 gauge"; }

# status: 1 ok/pass/clean, 0 fail/issues/drift, -1 unknown/skipped
phase_status() {
  local log="$1" pattern_ok="$2" pattern_bad="$3"
  [ -f "$log" ] || { echo -1; return; }
  if [ -n "$pattern_bad" ] && grep -Eq "$pattern_bad" "$log" 2>/dev/null; then echo 0; return; fi
  if [ -n "$pattern_ok" ] && grep -Eq "$pattern_ok" "$log" 2>/dev/null; then echo 1; return; fi
  echo -1
}

latest_mtime() {
  local best=0 f
  for f in "$@"; do
    [ -e "$f" ] || continue
    local m
    m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    [ "$m" -gt "$best" ] && best=$m
  done
  echo "$best"
}

source_kind="none"
last_run=0
unknown=1
never_run=1

suite_log="$SUITE_LOG_DIR/baseline.log"
sec_log="$SEC_LOG_DIR/baseline.log"
suite_m=$(latest_mtime "$suite_log" "$SUITE_LOG_DIR/opa-check.log" "$SUITE_LOG_DIR/drift.log")
sec_m=$(latest_mtime "$sec_log" "$SEC_LOG_DIR/opa-tests.log" "$SEC_LOG_DIR/drift-detection.log")

if [ "$suite_m" -gt 0 ] && [ "$sec_m" -gt 0 ]; then source_kind="mixed"; last_run=$suite_m; [ "$sec_m" -gt "$last_run" ] && last_run=$sec_m; fi
if [ "$suite_m" -gt 0 ] && [ "$sec_m" -le 0 ]; then source_kind="suite"; last_run=$suite_m; fi
if [ "$sec_m" -gt 0 ] && [ "$suite_m" -le 0 ]; then source_kind="spectre_security"; last_run=$sec_m; fi

if [ "$last_run" -gt 0 ]; then never_run=0; unknown=0; fi
age=0; stale=0
if [ "$last_run" -gt 0 ]; then age=$((now - last_run)); [ "$age" -gt "$STALE_SECONDS" ] && stale=1; fi

# Choose primary evidence dir for phase parsing (prefer suite when mixed).
LOGD="$SEC_LOG_DIR"; [ "$source_kind" = "suite" ] || [ "$source_kind" = "mixed" ] && LOGD="$SUITE_LOG_DIR"
BLOG="$LOGD/baseline.log"; [ ! -f "$BLOG" ] && BLOG="$suite_log"; [ ! -f "$BLOG" ] && BLOG="$sec_log"

# Phase statuses (best-effort from logs; -1 when unknown/skipped).
opa_check=$(phase_status "$LOGD/opa-check.log" "check.*(OK|passed|PASS)|^$|OPA check: OK" "ERROR|fail|FAIL|violation")
# suite baseline logs "OPA check: OK"; empty/success patterns are tricky - also inspect baseline.log
if [ -f "$BLOG" ] && grep -q "OPA check: OK" "$BLOG" 2>/dev/null; then opa_check=1; fi
if [ -f "$BLOG" ] && grep -q "OPA check reported issues" "$BLOG" 2>/dev/null; then opa_check=0; fi

opa_tests=$(phase_status "$LOGD/opa-tests.log" "ALL (OPA )?TESTS PASSED|ALL PASSED" "FAIL|FAILED|❌")
if [ -f "$BLOG" ] && grep -q "OPA .*tests: PASSED\|OPA policy tests: ALL PASSED" "$BLOG" 2>/dev/null; then opa_tests=1; fi
if [ -f "$BLOG" ] && grep -q "OPA .*tests: FAILED\|OPA policy tests FAILED" "$BLOG" 2>/dev/null; then opa_tests=0; fi

hardening=$(phase_status "$LOGD/hardening.log" "COMPLETED|completed successfully|Hardening: COMPLETED" "FAILED|failed|Hardening: FAILED")
if [ -f "$BLOG" ] && grep -q "Hardening: COMPLETED" "$BLOG" 2>/dev/null; then hardening=1; fi
if [ -f "$BLOG" ] && grep -q "Hardening: FAILED" "$BLOG" 2>/dev/null; then hardening=0; fi

# Drift: 0 = no drift (positive evidence), 1 = drift detected, -1 = unknown/skipped.
drift=-1
drift_files=()
for _df in "$LOGD/drift.log" "$LOGD/drift-detection.log" "$BLOG"; do [ -f "$_df" ] && drift_files+=("$_df"); done
if [ ${#drift_files[@]} -gt 0 ] && grep -Eq "Phase 9: drift|[Dd]rift detect|NO DRIFT|WARNING: Drift detected" "${drift_files[@]}" 2>/dev/null; then
  if grep -Eq "NO DRIFT|No drift detected|Drift detection: NO DRIFT" "${drift_files[@]}" 2>/dev/null; then
    drift=0
  elif grep -Eh "WARNING: Drift detected|[Dd]rift detected" "${drift_files[@]}" 2>/dev/null | grep -Ev "NO DRIFT|No drift detected" | grep -q .; then
    drift=1
  fi
fi

sbom=$(phase_status "$LOGD/sbom.log" "SBOM generation: COMPLETED|COMPLETED" "WARNING: SBOM generation|FAILED")
if [ -f "$BLOG" ] && grep -q "SBOM.*COMPLETED\|Phase 8: SBOM" "$BLOG" 2>/dev/null && ! grep -q "SBOM.*issues\|SBOM generation had issues" "$BLOG" 2>/dev/null; then [ "$sbom" = -1 ] && sbom=1; fi
if [ -f "$BLOG" ] && grep -q "SBOM generation had issues\|SBOM.*FAILED" "$BLOG" 2>/dev/null; then sbom=0; fi

trivy_fs=$(phase_status "$LOGD/trivy-fs.log" "" "CRITICAL|HIGH|exit [1-9]|Trivy FS: issues")
if [ -f "$BLOG" ] && grep -q "Trivy FS: COMPLETED" "$BLOG" 2>/dev/null; then trivy_fs=1; fi
if [ -f "$BLOG" ] && grep -q "Trivy FS: issues" "$BLOG" 2>/dev/null; then trivy_fs=0; fi
# absence of log but phase ran without explicit completion: leave -1/unknown rather than guess

gitleaks=$(phase_status "$LOGD/gitleaks.log" "no leaks found|leaks found: 0|Gitleaks: no findings" "leaks found: [1-9]|Gitleaks: findings|potential secrets")
if [ -f "$BLOG" ] && grep -q "Gitleaks: no findings\|Gitleaks scan: No secrets found" "$BLOG" 2>/dev/null; then gitleaks=1; fi
if [ -f "$BLOG" ] && grep -q "Gitleaks: findings\|potential secrets" "$BLOG" 2>/dev/null; then gitleaks=0; fi

aide=$(phase_status "$LOGD/aide.log" "AIDE.*ok|no differences|integrity check passed" "AIDE found differences|FAILED|WARNING")
wazuh=$(phase_status "$LOGD/wazuh.log" "active|running|connected" "not running|inactive|failed|not installed")
trivy_image=$(phase_status "$LOGD/trivy-image.log" "PASSED|Trivy image scan: PASSED" "FAILED|Trivy image scan FAILED")
if [ -f "$BLOG" ] && grep -q "IMAGE_NAME not set; skipping image scan\|Skipping Trivy image scan" "$BLOG" 2>/dev/null; then trivy_image=-1; fi

: > "$TMP"
emit "# Spectre security baseline pipeline metrics (evidence-based; distinct from spectre_agent_* runtime)."
emit "# source=$source_kind never_run=$never_run unknown=$unknown stale=$stale age_seconds=$age"
gauge_help spectre_security_baseline_exporter_up "1 if the security baseline metrics exporter produced output"
emit "spectre_security_baseline_exporter_up{source=\"$source_kind\"} 1"
gauge_help spectre_security_baseline_last_run_timestamp_seconds "Unix timestamp of last known baseline evidence; 0 when never run/unknown"
emit "spectre_security_baseline_last_run_timestamp_seconds{source=\"$source_kind\"} $last_run"
gauge_help spectre_security_baseline_never_run "1 if no baseline evidence was found"
emit "spectre_security_baseline_never_run{source=\"$source_kind\"} $never_run"
gauge_help spectre_security_baseline_unknown "1 if baseline state cannot be determined from evidence"
emit "spectre_security_baseline_unknown{source=\"$source_kind\"} $unknown"
gauge_help spectre_security_baseline_evidence_age_seconds "Seconds since last known baseline evidence; 0 when never run/unknown"
emit "spectre_security_baseline_evidence_age_seconds{source=\"$source_kind\"} $age"
gauge_help spectre_security_baseline_stale "1 if baseline evidence is older than configured freshness window"
emit "spectre_security_baseline_stale{source=\"$source_kind\"} $stale"

gauge_help spectre_security_baseline_opa_check_ok "1 pass, 0 fail/issues, -1 unknown/skipped (suite-native OPA check)"
emit "spectre_security_baseline_opa_check_ok{source=\"$source_kind\"} $opa_check"
gauge_help spectre_security_baseline_opa_tests_ok "1 pass, 0 fail, -1 unknown/skipped (compat policy tests)"
emit "spectre_security_baseline_opa_tests_ok{source=\"$source_kind\"} $opa_tests"
gauge_help spectre_security_baseline_hardening_ok "1 ok, 0 fail, -1 unknown/skipped"
emit "spectre_security_baseline_hardening_ok{source=\"$source_kind\"} $hardening"
gauge_help spectre_security_baseline_drift_detected "1 drift detected, 0 no drift (positive evidence), -1 unknown/skipped"
emit "spectre_security_baseline_drift_detected{source=\"$source_kind\"} $drift"
gauge_help spectre_security_baseline_sbom_ok "1 ok, 0 fail/issues, -1 unknown/skipped"
emit "spectre_security_baseline_sbom_ok{source=\"$source_kind\"} $sbom"
gauge_help spectre_security_baseline_trivy_fs_ok "1 ok, 0 issues/fail, -1 unknown/skipped"
emit "spectre_security_baseline_trivy_fs_ok{source=\"$source_kind\"} $trivy_fs"
gauge_help spectre_security_baseline_gitleaks_ok "1 clean/no findings, 0 findings/issues, -1 unknown/skipped"
emit "spectre_security_baseline_gitleaks_ok{source=\"$source_kind\"} $gitleaks"
gauge_help spectre_security_baseline_aide_ok "1 ok, 0 fail, -1 unknown/skipped"
emit "spectre_security_baseline_aide_ok{source=\"$source_kind\"} $aide"
gauge_help spectre_security_baseline_wazuh_ok "1 ok/active, 0 not ok, -1 unknown/skipped"
emit "spectre_security_baseline_wazuh_ok{source=\"$source_kind\"} $wazuh"
gauge_help spectre_security_baseline_trivy_image_ok "1 ok, 0 fail, -1 unknown/not configured"
emit "spectre_security_baseline_trivy_image_ok{source=\"$source_kind\"} $trivy_image"

mv "$TMP" "$OUT"
echo "wrote $OUT (source=$source_kind never_run=$never_run stale=$stale)" >&2
