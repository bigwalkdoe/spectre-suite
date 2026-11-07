#!/usr/bin/env bash
# Opt-in check: Path C isolation invariants (additive; no CI/gate changes).
# Verifies core data.security[k].deny aggregation gates remain green and that
# core spectre/policies/*.rego does not define kubernetes/versions aggregation
# packages (k8s admission/versions are isolated report slices).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
POLICY_DIR="spectre/policies"

echo "== opa check (core) =="
opa check "$POLICY_DIR"

echo "== core aggregation (must remain 38/0) =="
empty="$(mktemp)"
printf '{}' > "$empty"
trap 'rm -f "$empty"' EXIT
empty_n="$(opa eval --format raw --data "$POLICY_DIR" --input "$empty" '[m | data.security[k].deny[m]]' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
base_n="$(opa eval --format raw --data "$POLICY_DIR" --input "$POLICY_DIR/baseline.json" '[m | data.security[k].deny[m]]' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
echo "empty_input_denials=$empty_n baseline_denials=$base_n"
test "$empty_n" -ge 38
test "$base_n" -eq 0

echo "== isolation: no kubernetes/opa-versions packages in the top-level core policy tree =="
if grep -InE '^package[[:space:]]+(kubernetes\.|opa\.versions)' "$POLICY_DIR"/*.rego; then
  echo "FAIL: kubernetes/versions packages found in top-level core spectre/policies aggregation tree" >&2
  exit 1
fi

echo "== isolation: vendored k8s slice is present and outside security.* =="
K8S_DIR="$POLICY_DIR/k8s"
test -f "$K8S_DIR/kubernetes-admission.rego"
grep -qE '^package[[:space:]]+kubernetes\.admission' "$K8S_DIR/kubernetes-admission.rego"
if grep -qE '^package[[:space:]]+security\.' "$K8S_DIR"/*.rego; then
  echo "FAIL: vendored k8s slice defines a security.* package (would risk aggregation)" >&2
  exit 1
fi
test -f "$K8S_DIR/versions/index.json"
test -f "$K8S_DIR/versions/kubernetes-admission/v0.1.0/metadata.json"

echo "== contract mapping present =="
test -f "$POLICY_DIR/contract/mapping.v1.json"
python3 -m json.tool "$POLICY_DIR/contract/mapping.v1.json" >/dev/null

echo "OK: core gates green; k8s/versions isolated from data.security[k].deny (opt-in check)."
