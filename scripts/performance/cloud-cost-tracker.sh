#!/bin/bash
# Track cloud resource costs
set -euo pipefail

REPORT_DIR="/home/deon/scripts/performance/reports"
mkdir -p "$REPORT_DIR"
DATE=$(date +%Y%m%d)

echo "=== Cloud Cost Report - $DATE ===" > "$REPORT_DIR/cost-report-$DATE.md"

# AWS Cost (if AWS CLI configured)
if command -v aws >/dev/null 2>&1; then
    echo "## AWS Costs" >> "$REPORT_DIR/cost-report-$DATE.md"
    aws ce get-cost-and-usage \
        --time-period "Start=$(date -d "-30 days" +%Y-%m-%d),End=$(date +%Y-%m-%d)" \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --output text 2>/dev/null >> "$REPORT_DIR/cost-report-$DATE.md" || \
        echo "AWS cost data not available (configure aws CLI)" >> "$REPORT_DIR/cost-report-$DATE.md"
fi

# Docker resource costs (estimated)
echo "" >> "$REPORT_DIR/cost-report-$DATE.md"
echo "## Docker Resource Usage" >> "$REPORT_DIR/cost-report-$DATE.md"
docker stats --no-stream 2>/dev/null >> "$REPORT_DIR/cost-report-$DATE.md" || true

# Disk usage by service
echo "" >> "$REPORT_DIR/cost-report-$DATE.md"
echo "## Disk Usage by Directory" >> "$REPORT_DIR/cost-report-$DATE.md"
du -sh /home/deon/scripts/ /home/deon/projects/ /backups/ /var/log/ 2>/dev/null >> "$REPORT_DIR/cost-report-$DATE.md"

echo "Cost report: $REPORT_DIR/cost-report-$DATE.md"
