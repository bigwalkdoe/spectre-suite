#!/bin/bash
# Spectre Security Baseline — SBOM Generation (suite-canonical, additive)
# Generates SBOMs (CycloneDX/SPDX) and dependency list with suite path defaults.
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
LOG_DIR="${SECURITY_BASELINE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
REPORT_ROOT="${SECURITY_BASELINE_REPORT_DIR:-$LOG_DIR/reports}"
mkdir -p "$LOG_DIR" "$REPORT_ROOT"

DATE=$(date +%Y%m%d_%H%M%S)
SBOM_DIR="$REPORT_ROOT/sbom-$DATE"
mkdir -p "$SBOM_DIR"
SCAN_TARGET="${SECURITY_SBOM_TARGET:-$SUITE_ROOT}"

echo "=== SBOM Generation - $DATE ===" | tee "$LOG_DIR/sbom-generation.log"
echo "Target: $SCAN_TARGET" | tee -a "$LOG_DIR/sbom-generation.log"
echo "Output: $SBOM_DIR" | tee -a "$LOG_DIR/sbom-generation.log"

SBOM_SOURCE_EXIT=1; SPDX_EXIT=1; IMAGE_SBOM_EXIT=1; IMAGE_SPDX_EXIT=1
if command -v trivy >/dev/null 2>&1; then
  echo "--- Generating Source SBOM (CycloneDX) ---" | tee -a "$LOG_DIR/sbom-generation.log"
  trivy fs --format cyclonedx --output "$SBOM_DIR/sbom-source.cdx.json" "$SCAN_TARGET" 2>&1 | tee -a "$LOG_DIR/sbom-generation.log" && SBOM_SOURCE_EXIT=0 || SBOM_SOURCE_EXIT=${PIPESTATUS[0]:-$?}
  echo "--- Generating Source SBOM (SPDX) ---" | tee -a "$LOG_DIR/sbom-generation.log"
  trivy fs --format spdx-json --output "$SBOM_DIR/sbom-source.spdx.json" "$SCAN_TARGET" 2>&1 | tee -a "$LOG_DIR/sbom-generation.log" && SPDX_EXIT=0 || SPDX_EXIT=${PIPESTATUS[0]:-$?}
  if [ -n "${IMAGE_NAME:-}" ]; then
    SAFE_IMAGE=$(printf '%s' "$IMAGE_NAME" | tr '/:@' '___')
    echo "--- Generating Image SBOM for $IMAGE_NAME ---" | tee -a "$LOG_DIR/sbom-generation.log"
    trivy image --format cyclonedx --output "$SBOM_DIR/sbom-image-$SAFE_IMAGE.cdx.json" "$IMAGE_NAME" 2>&1 | tee -a "$LOG_DIR/sbom-generation.log" && IMAGE_SBOM_EXIT=0 || IMAGE_SBOM_EXIT=$?
    trivy image --format spdx-json --output "$SBOM_DIR/sbom-image-$SAFE_IMAGE.spdx.json" "$IMAGE_NAME" 2>&1 | tee -a "$LOG_DIR/sbom-generation.log" && IMAGE_SPDX_EXIT=0 || IMAGE_SPDX_EXIT=$?
  fi
  echo "--- Generating Dependency List ---" | tee -a "$LOG_DIR/sbom-generation.log"
  trivy fs --format json "$SCAN_TARGET" 2>/dev/null | jq -r '.Results[]?.Packages[]? | "\(.Name)\t\(.Version)\t\(.License // "unknown")\t\(.Type)"' 2>/dev/null | sort -u > "$SBOM_DIR/dependencies.txt" || true
else
  echo "Trivy not available; SBOM generation skipped" | tee -a "$LOG_DIR/sbom-generation.log"
fi

echo "" | tee -a "$LOG_DIR/sbom-generation.log"
echo "=== SBOM Generation Summary ===" | tee -a "$LOG_DIR/sbom-generation.log"
echo "Source CycloneDX: $([ ${SBOM_SOURCE_EXIT:-1} -eq 0 ] && echo SUCCESS || echo FAILED/SKIPPED)" | tee -a "$LOG_DIR/sbom-generation.log"
echo "Source SPDX: $([ ${SPDX_EXIT:-1} -eq 0 ] && echo SUCCESS || echo FAILED/SKIPPED)" | tee -a "$LOG_DIR/sbom-generation.log"
[ -n "${IMAGE_NAME:-}" ] && echo "Image CycloneDX: $([ ${IMAGE_SBOM_EXIT:-1} -eq 0 ] && echo SUCCESS || echo FAILED/SKIPPED)" | tee -a "$LOG_DIR/sbom-generation.log"
[ -n "${IMAGE_NAME:-}" ] && echo "Image SPDX: $([ ${IMAGE_SPDX_EXIT:-1} -eq 0 ] && echo SUCCESS || echo FAILED/SKIPPED)" | tee -a "$LOG_DIR/sbom-generation.log"
echo "Output directory: $SBOM_DIR" | tee -a "$LOG_DIR/sbom-generation.log"
ln -sfn "$SBOM_DIR" "$REPORT_ROOT/sbom-latest" 2>/dev/null || true
# Exit 0 for "completed attempt" to preserve baseline-runner semantics; evidence shows per-format status.
exit 0
