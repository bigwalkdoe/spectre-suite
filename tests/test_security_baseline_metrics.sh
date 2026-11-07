#!/bin/bash
# Verifies spectre_security_baseline_* exporter semantics (never conflated):
# never-run/unknown, stale, and evidence-derived phase states.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPORTER="$ROOT/spectre/monitoring/exporters/security-baseline-metrics-exporter.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
metric() { grep -E "^$1(\{| )" "$2" | head -1 | awk '{print $2}'; }

# 1) No evidence anywhere -> never_run=1, unknown=1, stale=0, last_run=0
EMPTY_HOME="$TMP/emptyhome"
OUT="$TMP/out1"; mkdir -p "$OUT"
HOME="$EMPTY_HOME" XDG_STATE_HOME="$EMPTY_HOME/.state" \
  SPECTRE_SECURITY_ROOT="$TMP/no-security-repo" SECURITY_BASELINE_COMPAT_LOG_DIR="$TMP/no-compat" \
  "$EXPORTER" "$OUT" >/dev/null 2>&1
[ "$(metric 'spectre_security_baseline_never_run' "$OUT/security_baseline_metrics.prom")" = "1" ] || fail "expected never_run=1"
[ "$(metric 'spectre_security_baseline_unknown' "$OUT/security_baseline_metrics.prom")" = "1" ] || fail "expected unknown=1"
[ "$(metric 'spectre_security_baseline_stale' "$OUT/security_baseline_metrics.prom")" = "0" ] || fail "never-run must not be stale"
[ "$(metric 'spectre_security_baseline_last_run_timestamp_seconds' "$OUT/security_baseline_metrics.prom")" = "0" ] || fail "never-run last_run must be 0"
[ "$(metric 'spectre_security_baseline_opa_compat_report_ok' "$OUT/security_baseline_metrics.prom")" = "-1" ] || fail "expected opa_compat_report_ok=-1 when never run"
pass "never-run/unknown emits explicit state (no fabricated timestamp)"

# 2) Fresh evidence with clear pass/fail markers
LOGD="$TMP/suite-logs"; mkdir -p "$LOGD"
cat > "$LOGD/baseline.log" <<'EOF'
[baseline] Phase 1a: OPA check (suite policies)
OPA check: OK
Phase 1b: OPA policy tests (compat)
OPA compat: SKIPPED (set SECURITY_OPA_COMPAT=1 for Option A adapter report; suite-native OPA gate remains canonical)
Phase 2: security hardening
Hardening: COMPLETED
Phase 9: drift detection
Drift detection: NO DRIFT
EOF
printf 'ok\n' > "$LOGD/opa-check.log"
printf 'ALL TESTS PASSED\n' > "$LOGD/opa-tests.log"
touch "$LOGD/baseline.log" "$LOGD/opa-check.log" "$LOGD/opa-tests.log"
OUT2="$TMP/out2"; mkdir -p "$OUT2"
HOME="$EMPTY_HOME" XDG_STATE_HOME="$EMPTY_HOME/.state" SECURITY_BASELINE_LOG_DIR="$LOGD" \
  SPECTRE_SECURITY_ROOT="$TMP/no-security-repo" SECURITY_BASELINE_COMPAT_LOG_DIR="$TMP/no-compat" \
  SPECTRE_SECURITY_BASELINE_STALE_SECONDS=999999 "$EXPORTER" "$OUT2" >/dev/null 2>&1
[ "$(metric 'spectre_security_baseline_never_run' "$OUT2/security_baseline_metrics.prom")" = "0" ] || fail "expected evidence present"
[ "$(metric 'spectre_security_baseline_stale' "$OUT2/security_baseline_metrics.prom")" = "0" ] || fail "fresh evidence must not be stale"
[ "$(metric 'spectre_security_baseline_opa_check_ok' "$OUT2/security_baseline_metrics.prom")" = "1" ] || fail "expected opa_check_ok=1"
[ "$(metric 'spectre_security_baseline_hardening_ok' "$OUT2/security_baseline_metrics.prom")" = "1" ] || fail "expected hardening_ok=1"
[ "$(metric 'spectre_security_baseline_drift_detected' "$OUT2/security_baseline_metrics.prom")" = "0" ] || fail "expected no drift"
[ "$(metric 'spectre_security_baseline_opa_compat_report_ok' "$OUT2/security_baseline_metrics.prom")" = "-1" ] || fail "expected opa_compat_report_ok=-1 when skipped"
pass "fresh evidence reports pass/no-drift states"

# 3) Stale evidence + drift/failure markers
OLD="$TMP/old-logs"; mkdir -p "$OLD"
cat > "$OLD/baseline.log" <<'EOF'
OPA check reported issues
Hardening: FAILED
WARNING: Drift detected
Gitleaks: findings/issues
EOF
touch -d '10 days ago' "$OLD/baseline.log" 2>/dev/null || touch "$OLD/baseline.log"
OUT3="$TMP/out3"; mkdir -p "$OUT3"
HOME="$EMPTY_HOME" XDG_STATE_HOME="$EMPTY_HOME/.state" SECURITY_BASELINE_LOG_DIR="$OLD" \
  SPECTRE_SECURITY_ROOT="$TMP/no-security-repo" SECURITY_BASELINE_COMPAT_LOG_DIR="$TMP/no-compat" \
  SPECTRE_SECURITY_BASELINE_STALE_SECONDS=60 "$EXPORTER" "$OUT3" >/dev/null 2>&1
[ "$(metric 'spectre_security_baseline_never_run' "$OUT3/security_baseline_metrics.prom")" = "0" ] || fail "evidence exists"
[ "$(metric 'spectre_security_baseline_stale' "$OUT3/security_baseline_metrics.prom")" = "1" ] || fail "old evidence must be stale"
[ "$(metric 'spectre_security_baseline_opa_check_ok' "$OUT3/security_baseline_metrics.prom")" = "0" ] || fail "expected opa_check failure"
[ "$(metric 'spectre_security_baseline_hardening_ok' "$OUT3/security_baseline_metrics.prom")" = "0" ] || fail "expected hardening failure"
[ "$(metric 'spectre_security_baseline_drift_detected' "$OUT3/security_baseline_metrics.prom")" = "1" ] || fail "expected drift detected"
[ "$(metric 'spectre_security_baseline_gitleaks_ok' "$OUT3/security_baseline_metrics.prom")" = "0" ] || fail "expected gitleaks findings/failure"
pass "stale evidence and failures are explicit (stale != clean)"

# 4) SECURITY_OPA_COMPAT Option A report semantics (report-ran, NOT "no denials")
COMPAT="$TMP/compat-logs"; mkdir -p "$COMPAT"
cat > "$COMPAT/baseline.log" <<'EOF'
OPA check: OK
OPA compat report: COMPLETED (see /tmp/opa-compat-report.log)
DETAILS="hardening=0 opa_tests=0 opa_compat=0,on trivy_fs=0 wazuh=0 aide=0 gitleaks=0 image=0 sbom=0 drift=0 run_id=x log_dir=x"
EOF
touch "$COMPAT/baseline.log"
OUT4="$TMP/out4"; mkdir -p "$OUT4"
HOME="$EMPTY_HOME" XDG_STATE_HOME="$EMPTY_HOME/.state" SECURITY_BASELINE_LOG_DIR="$COMPAT" \
  SPECTRE_SECURITY_ROOT="$TMP/no-security-repo" SECURITY_BASELINE_COMPAT_LOG_DIR="$TMP/no-compat" \
  SPECTRE_SECURITY_BASELINE_STALE_SECONDS=999999 "$EXPORTER" "$OUT4" >/dev/null 2>&1
[ "$(metric 'spectre_security_baseline_opa_compat_report_ok' "$OUT4/security_baseline_metrics.prom")" = "1" ] || fail "expected opa_compat_report_ok=1 (report produced; denials irrelevant)"

cat > "$COMPAT/baseline.log" <<'EOF'
OPA check: OK
OPA compat report: issues (exit 2); see /tmp/opa-compat-report.log
DETAILS="hardening=0 opa_tests=0 opa_compat=2,on trivy_fs=0 wazuh=0 aide=0 gitleaks=0 image=0 sbom=0 drift=0 run_id=x log_dir=x"
EOF
touch "$COMPAT/baseline.log"
OUT5="$TMP/out5"; mkdir -p "$OUT5"
HOME="$EMPTY_HOME" XDG_STATE_HOME="$EMPTY_HOME/.state" SECURITY_BASELINE_LOG_DIR="$COMPAT" \
  SPECTRE_SECURITY_ROOT="$TMP/no-security-repo" SECURITY_BASELINE_COMPAT_LOG_DIR="$TMP/no-compat" \
  SPECTRE_SECURITY_BASELINE_STALE_SECONDS=999999 "$EXPORTER" "$OUT5" >/dev/null 2>&1
[ "$(metric 'spectre_security_baseline_opa_compat_report_ok' "$OUT5/security_baseline_metrics.prom")" = "0" ] || fail "expected opa_compat_report_ok=0 (helper/exec issues)"
pass "opa_compat_report_ok is report-ran semantics (1 produced, 0 issues, -1 off; denials do not affect)"

echo "All security baseline metrics tests passed."