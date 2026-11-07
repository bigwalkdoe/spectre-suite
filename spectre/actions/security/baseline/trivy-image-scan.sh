#!/bin/bash
# Spectre Security Baseline — Trivy Docker Image Scan (suite-canonical, additive)
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

LOG_DIR="${SECURITY_BASELINE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
mkdir -p "$LOG_DIR"

IMAGE_NAME="${1:-${IMAGE_NAME:-}}"
if [ -z "$IMAGE_NAME" ]; then
  echo "Usage: $0 <image_name> (or set IMAGE_NAME)" >&2
  exit 1
fi
command -v trivy >/dev/null 2>&1 || { echo "Trivy not installed" >&2; exit 1; }

DATE=$(date +%Y%m%d_%H%M%S)
SAFE_IMAGE=$(printf '%s' "$IMAGE_NAME" | tr '/:@' '___')
LOG_FILE="$LOG_DIR/trivy-image-$SAFE_IMAGE-$DATE.log"
SARIF_FILE="$LOG_DIR/trivy-image-$SAFE_IMAGE-$DATE.sarif"

echo "=== Trivy Image Scan - $DATE ===" | tee "$LOG_FILE"
echo "Scanning image: $IMAGE_NAME" | tee -a "$LOG_FILE"

echo "--- Vulnerability Scan ---" | tee -a "$LOG_FILE"
trivy image --severity CRITICAL,HIGH,MEDIUM --ignore-unfixed --format table "$IMAGE_NAME" 2>&1 | tee -a "$LOG_FILE"; VULN_EXIT=${PIPESTATUS[0]}
echo "--- Misconfiguration Scan ---" | tee -a "$LOG_FILE"
trivy image --scanners misconfig --format table "$IMAGE_NAME" 2>&1 | tee -a "$LOG_FILE"; MISCONFIG_EXIT=${PIPESTATUS[0]}
echo "--- Secret Scan ---" | tee -a "$LOG_FILE"
trivy image --scanners secret --format table "$IMAGE_NAME" 2>&1 | tee -a "$LOG_FILE"; SECRET_EXIT=${PIPESTATUS[0]}
echo "--- Generating SARIF Report ---" | tee -a "$LOG_FILE"
trivy image --severity CRITICAL,HIGH --format sarif --output "$SARIF_FILE" "$IMAGE_NAME" 2>&1 | tee -a "$LOG_FILE"; SARIF_EXIT=${PIPESTATUS[0]}

echo "=== Scan Summary ===" | tee -a "$LOG_FILE"
echo "Vulnerability: $([ $VULN_EXIT -eq 0 ] && echo PASSED || echo "FAILED ($VULN_EXIT)")" | tee -a "$LOG_FILE"
echo "Misconfiguration: $([ $MISCONFIG_EXIT -eq 0 ] && echo PASSED || echo "FAILED ($MISCONFIG_EXIT)")" | tee -a "$LOG_FILE"
echo "Secret: $([ $SECRET_EXIT -eq 0 ] && echo PASSED || echo "FAILED ($SECRET_EXIT)")" | tee -a "$LOG_FILE"
echo "SARIF: $([ $SARIF_EXIT -eq 0 ] && echo "$SARIF_FILE" || echo Failed)" | tee -a "$LOG_FILE"

[ $VULN_EXIT -eq 0 ] && [ $MISCONFIG_EXIT -eq 0 ] && [ $SECRET_EXIT -eq 0 ]
