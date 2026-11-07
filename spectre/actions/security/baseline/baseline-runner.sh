#!/bin/bash
# Spectre Suite — Security Baseline Runner (additive, canonical entrypoint)
# Absorbs spectre-security baseline-runner phases into suite dispatch with
# suite path/env conventions, evidence logging, and compatibility fallbacks.
#
# Preserves evidence quality intent: logs phase results and tool outputs.
# Non-destructive/additive: does not modify spectre-security or existing jobs.
set -euo pipefail

# Systemd/minimal environments may lack HOME.
: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
ACTIONS_SECURITY="$SUITE_ROOT/spectre/actions/security"
POLICY_DIR="${SPECTRE_POLICY_DIR:-$SUITE_ROOT/spectre/policies}"
SPECTRE_SECURITY_ROOT="${SPECTRE_SECURITY_ROOT:-/home/deon/dev/github/spectre-security}"
LOG_DIR="${SECURITY_BASELINE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/baseline.log"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [baseline][$RUN_ID] $*" | tee -a "$LOG_FILE"; }
warn() { log "WARNING: $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a helper: suite baseline dir, then suite actions/security, then optional spectre-security compat.
resolve_helper() {
  local name="$1"
  if [ -x "$SCRIPT_DIR/$name" ]; then echo "$SCRIPT_DIR/$name"; return 0; fi
  if [ -x "$ACTIONS_SECURITY/$name" ]; then echo "$ACTIONS_SECURITY/$name"; return 0; fi
  if [ -n "${SPECTRE_SECURITY_ROOT:-}" ] && [ -x "$SPECTRE_SECURITY_ROOT/security/$name" ]; then
    echo "$SPECTRE_SECURITY_ROOT/security/$name"; return 0
  fi
  return 1
}

log "Starting Spectre security baseline (suite-canonical, additive)."
log "SUITE_ROOT=$SUITE_ROOT POLICY_DIR=$POLICY_DIR LOG_DIR=$LOG_DIR"

OPA_TEST_EXIT=0
OPA_COMPAT_EXIT=0
HARDENING_EXIT=0
TRIVY_FS_EXIT=0
WAZUH_EXIT=0
AIDE_EXIT=0
GITLEAKS_EXIT=0
IMAGE_SCAN_EXIT=0
SBOM_EXIT=0
DRIFT_EXIT=0

# 1. OPA — suite-native check (preserves suite CI semantics) + optional compat tests.
OPA_CMD="${OPA_CMD:-opa}"
if [ -x "${HOME}/.local/bin/opa" ]; then OPA_CMD="${HOME}/.local/bin/opa"; fi
if "$OPA_CMD" version >/dev/null 2>&1; then
  log "Phase 1a: OPA check (suite policies: $POLICY_DIR)"
  if "$OPA_CMD" check "$POLICY_DIR" 2>&1 | tee "$LOG_DIR/opa-check.log"; then
    log "OPA check: OK"
  else
    warn "OPA check reported issues (see $LOG_DIR/opa-check.log)"
  fi
  log "Phase 1b: OPA compat (Option A, report-only when SECURITY_OPA_COMPAT=1)"
  if [ "${SECURITY_OPA_COMPAT:-0}" = "1" ]; then
    if helper=$(resolve_helper "opa-compat-report.sh"); then
      log "OPA compat report (Option A adapter -> canonical suite policies, report-only):"
      if "$helper" 2>&1 | tee "$LOG_DIR/opa-compat-report.log"; then
        log "OPA compat report: COMPLETED (see $LOG_DIR/opa-compat-report.log)"
      else
        OPA_COMPAT_EXIT=$?; warn "OPA compat report: issues (exit $OPA_COMPAT_EXIT); see $LOG_DIR/opa-compat-report.log"
      fi
    else
      log "OPA compat report helper not found (opa-compat-report.sh); skipping"
    fi
    if helper=$(resolve_helper "test-opa-policies.sh"); then
      if OPA_CMD="$OPA_CMD" "$helper" 2>&1 | tee "$LOG_DIR/opa-tests.log"; then
        log "OPA legacy compat tests: PASSED"
      else
        OPA_TEST_EXIT=$?; warn "OPA legacy compat tests: FAILED (exit $OPA_TEST_EXIT)"
      fi
    else
      log "OPA legacy compat tests: SKIPPED (no test-opa-policies.sh contract helper; suite-native OPA gate remains canonical)"
    fi
  else
    log "OPA compat: SKIPPED (set SECURITY_OPA_COMPAT=1 for Option A adapter report; suite-native OPA gate remains canonical)"
  fi
else
  warn "OPA not available; skipping OPA phases"
fi

# 2. Security hardening (canonical suite implementation).
log "Phase 2: security hardening"
HARDENING="$ACTIONS_SECURITY/run-security-hardening.sh"
if [ -x "$HARDENING" ]; then
  if "$HARDENING" 2>&1 | tee "$LOG_DIR/hardening.log"; then
    log "Hardening: COMPLETED"
  else
    HARDENING_EXIT=$?; warn "Hardening: FAILED (exit $HARDENING_EXIT)"
  fi
else
  warn "run-security-hardening.sh not found at $HARDENING"
fi

# 3. Trivy filesystem scan.
log "Phase 3: Trivy filesystem scan"
SCAN_DIR="${SECURITY_SCAN_DIR:-$SUITE_ROOT}"
if have trivy; then
  if timeout "${SECURITY_TRIVY_TIMEOUT:-300}" trivy fs "$SCAN_DIR" --quiet 2>&1 | tee "$LOG_DIR/trivy-fs.log"; then
    log "Trivy FS: COMPLETED"
  else
    TRIVY_FS_EXIT=$?; warn "Trivy FS: issues/failed (exit $TRIVY_FS_EXIT)"
  fi
else
  log "Trivy not installed; skipping filesystem scan"
fi

# 4. Wazuh status.
log "Phase 4: Wazuh status"
if helper=$(resolve_helper "check-wazuh-status.sh"); then
  "$helper" 2>&1 | tee "$LOG_DIR/wazuh.log" || WAZUH_EXIT=$?
else
  log "Wazuh status helper not found; skipping"
fi

# 5. AIDE/file integrity.
log "Phase 5: file integrity (AIDE)"
if helper=$(resolve_helper "check-file-integrity-local.sh"); then
  "$helper" 2>&1 | tee "$LOG_DIR/aide.log" || AIDE_EXIT=$?
else
  log "AIDE helper not found; skipping"
fi

# 6. Gitleaks.
log "Phase 6: Gitleaks secret scan"
GITLEAKS_CMD="${GITLEAKS_CMD:-gitleaks}"
[ -x "${HOME}/go/bin/gitleaks" ] && GITLEAKS_CMD="${HOME}/go/bin/gitleaks"
if have "$GITLEAKS_CMD" || [ -x "$GITLEAKS_CMD" ]; then
  GITLEAKS_CFG="${SECURITY_GITLEAKS_CONFIG:-$SUITE_ROOT/.gitleaks.toml}"
  GITLEAKS_ARGS=(detect --source "$SCAN_DIR" --no-banner --no-git)
  [ -f "$GITLEAKS_CFG" ] && GITLEAKS_ARGS+=(--config "$GITLEAKS_CFG")
  if "$GITLEAKS_CMD" "${GITLEAKS_ARGS[@]}" 2>&1 | tee "$LOG_DIR/gitleaks.log"; then
    log "Gitleaks: no findings reported"
  else
    GITLEAKS_EXIT=$?; warn "Gitleaks: findings/issues (exit $GITLEAKS_EXIT)"
  fi
else
  log "Gitleaks not installed; skipping"
fi

# 7. Optional Trivy image scan.
log "Phase 7: Trivy image scan"
if [ -n "${IMAGE_NAME:-}" ]; then
  if helper=$(resolve_helper "trivy-image-scan.sh"); then
    "$helper" "$IMAGE_NAME" 2>&1 | tee "$LOG_DIR/trivy-image.log" || IMAGE_SCAN_EXIT=$?
  else
    warn "IMAGE_NAME set but trivy-image-scan.sh not found"
  fi
else
  log "IMAGE_NAME not set; skipping image scan"
fi

# 8. SBOM.
log "Phase 8: SBOM generation"
if helper=$(resolve_helper "generate-sbom.sh"); then
  "$helper" 2>&1 | tee "$LOG_DIR/sbom.log" || SBOM_EXIT=$?
else
  log "generate-sbom.sh not found; skipping"
fi

# 9. Drift detection.
log "Phase 9: drift detection"
if helper=$(resolve_helper "drift-detection.sh"); then
  "$helper" 2>&1 | tee "$LOG_DIR/drift.log" || DRIFT_EXIT=$?
else
  log "drift-detection.sh not found; skipping"
fi

# 10. Alerting (optional).
log "Phase 10: alerting"
ALERT_LEVEL="info"
ALERT_MSG="Spectre suite security baseline completed"
if [ "${DRIFT_EXIT}" -ne 0 ] || [ "${OPA_TEST_EXIT}" -ne 0 ] || [ "${GITLEAKS_EXIT}" -ne 0 ] || [ "${IMAGE_SCAN_EXIT}" -ne 0 ] || [ "${SBOM_EXIT}" -ne 0 ] || [ "${HARDENING_EXIT}" -ne 0 ]; then
  ALERT_LEVEL="warning"
  ALERT_MSG="Spectre suite security baseline completed with warnings/failures"
fi
DETAILS="hardening=$HARDENING_EXIT opa_tests=$OPA_TEST_EXIT opa_compat=${OPA_COMPAT_EXIT}$( [ \"${SECURITY_OPA_COMPAT:-0}\" = \"1\" ] && printf ',on' || printf ',off' ) trivy_fs=$TRIVY_FS_EXIT wazuh=$WAZUH_EXIT aide=$AIDE_EXIT gitleaks=$GITLEAKS_EXIT image=$IMAGE_SCAN_EXIT sbom=$SBOM_EXIT drift=$DRIFT_EXIT run_id=$RUN_ID log_dir=$LOG_DIR"
if helper=$(resolve_helper "alerting.sh"); then
  "$helper" "$ALERT_LEVEL" "$ALERT_MSG" "$DETAILS" 2>&1 | tee -a "$LOG_DIR/alerting.log" || warn "alerting helper failed"
else
  log "Alerting helper not found; summary: $ALERT_LEVEL $ALERT_MSG ($DETAILS)"
fi

log "Baseline run complete. $DETAILS"
# Additive v1: report status via logs/provenance; do not hard-fail on optional phase warnings.
exit 0
