#!/bin/bash
# Setup script for ML-based anomaly detection

# Source distribution detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$PROJECT_ROOT/detect-distribution.sh"

# Initialize distribution settings
detect_distribution
set_package_manager

echo "Setting up ML-based Anomaly Detection for $DISTRO_NAME..."

# Install Python dependencies
echo "Installing Python dependencies..."
$PKG_INSTALL python3 python3-pip python3-venv

# Create virtual environment
echo "Creating Python virtual environment..."
cd "$SCRIPT_DIR"
python3 -m venv venv
source venv/bin/activate

# Install Python packages
echo "Installing ML libraries..."
pip install --upgrade pip
pip install numpy pandas scikit-learn scipy matplotlib seaborn joblib prometheus-client

# Create necessary directories
echo "Creating directories for ML anomaly detection..."
sudo mkdir -p /var/log/ml-anomaly
sudo mkdir -p /var/lib/ml-anomaly/models
sudo mkdir -p /var/lib/ml-anomaly/metrics

# Set permissions
sudo chown -R $USER:$USER /var/log/ml-anomaly
sudo chown -R $USER:$USER /var/lib/ml-anomaly

# Create systemd service
echo "Creating systemd service for continuous anomaly detection..."
sudo bash -c 'cat > /etc/systemd/system/ml-anomaly-detection.service << "EOF"
[Unit]
Description=ML-based Anomaly Detection
After=network.target docker.service

[Service]
Type=simple
User='$USER'
WorkingDirectory='$SCRIPT_DIR'
Environment="PATH='$SCRIPT_DIR/venv/bin'"
ExecStart='$SCRIPT_DIR/venv/bin/python $SCRIPT_DIR/anomaly_detector.py --mode continuous'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF'

# Create training service
sudo bash -c 'cat > /etc/systemd/system/ml-anomaly-training.service << "EOF"
[Unit]
Description=ML Anomaly Detection Training
Description=Train anomaly detection models

[Service]
Type=oneshot
User='$USER'
WorkingDirectory='$SCRIPT_DIR'
Environment="PATH='$SCRIPT_DIR/venv/bin'"
ExecStart='$SCRIPT_DIR/venv/bin/python $SCRIPT_DIR/anomaly_detector.py --mode train --training-samples 100'

[Install]
WantedBy=multi-user.target
EOF'

# Create training timer (run weekly)
sudo bash -c 'cat > /etc/systemd/system/ml-anomaly-training.timer << "EOF"
[Unit]
Description=Weekly ML Anomaly Detection Model Training

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF'

# Create detection service (manual trigger)
sudo bash -c 'cat > /etc/systemd/system/ml-anomaly-detect.service << "EOF"
[Unit]
Description=ML Anomaly Detection (Single Check)
Description=Perform single anomaly detection check

[Service]
Type=oneshot
User='$USER'
WorkingDirectory='$SCRIPT_DIR'
Environment="PATH='$SCRIPT_DIR/venv/bin'"
ExecStart='$SCRIPT_DIR/venv/bin/python $SCRIPT_DIR/anomaly_detector.py --mode detect'

[Install]
WantedBy=multi-user.target
EOF'

# Reload systemd
sudo systemctl daemon-reload

# Enable continuous detection
echo "Enabling continuous anomaly detection..."
sudo systemctl enable ml-anomaly-detection.service

# Enable weekly training
echo "Enabling weekly model training..."
sudo systemctl enable ml-anomaly-training.timer
sudo systemctl start ml-anomaly-training.timer

# Create Prometheus exporter for ML metrics
echo "Creating Prometheus exporter for ML metrics..."
cat > "$SCRIPT_DIR/ml_metrics_exporter.py" << 'EOF'
#!/usr/bin/env python3
"""
Prometheus exporter for ML anomaly detection metrics
"""

from prometheus_client import start_http_server, Gauge, Counter
import json
import time
import os
from datetime import datetime

# Define metrics
ANOMALY_DETECTIONS = Counter('ml_anomaly_detections_total', 'Total number of anomaly detections')
ANOMALY_SCORES = Gauge('ml_anomaly_latest_score', 'Latest anomaly score')
MODEL_TRAINING_TIME = Gauge('ml_model_training_duration_seconds', 'Duration of model training')
MODEL_ACCURACY = Gauge('ml_model_accuracy', 'Model accuracy metric')
SYSTEM_METRICS = Gauge('ml_system_metric', 'Current system metric', ['metric_name'])

def export_ml_metrics():
    """Export ML metrics to Prometheus"""
    metrics_file = '/var/log/ml-anomaly/latest_detection.json'
    
    if os.path.exists(metrics_file):
        with open(metrics_file, 'r') as f:
            data = json.load(f)
        
        if data.get('is_anomaly'):
            ANOMALY_DETECTIONS.inc()
        
        if 'anomaly_score' in data:
            ANOMALY_SCORES.set(data['anomaly_score'])
        
        # Export individual metrics if available
        if 'individual_results' in data:
            for detector_name, result in data['individual_results'].items():
                if result and 'anomaly_score' in result:
                    SYSTEM_METRICS.labels(metric_name=f'{detector_name}_score').set(result['anomaly_score'])

def main():
    """Main exporter function"""
    start_http_server(8090)
    print("ML metrics exporter started on port 8090")
    
    while True:
        export_ml_metrics()
        time.sleep(60)

if __name__ == '__main__':
    main()
EOF

chmod +x "$SCRIPT_DIR/ml_metrics_exporter.py"

# Create systemd service for metrics exporter
sudo bash -c 'cat > /etc/systemd/system/ml-metrics-exporter.service << "EOF"
[Unit]
Description=ML Anomaly Detection Metrics Exporter
After=network.target

[Service]
Type=simple
User='$USER'
WorkingDirectory='$SCRIPT_DIR'
Environment="PATH='$SCRIPT_DIR/venv/bin'"
ExecStart='$SCRIPT_DIR/venv/bin/python $SCRIPT_DIR/ml_metrics_exporter.py'
Restart=always

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl daemon-reload
sudo systemctl enable ml-metrics-exporter.service

echo ""
echo "🤖 ML-based Anomaly Detection setup completed!"
echo ""
echo "📁 Installation directories:"
echo "  - Scripts: $SCRIPT_DIR"
echo "  - Logs: /var/log/ml-anomaly"
echo "  - Models: /var/lib/ml-anomaly/models"
echo "  - Metrics: /var/lib/ml-anomaly/metrics"
echo ""
echo "🚀 Services:"
echo "  - ml-anomaly-detection.service: Continuous monitoring"
echo "  - ml-anomaly-training.timer: Weekly model training"
echo "  - ml-metrics-exporter.service: Prometheus metrics on port 8090"
echo ""
echo "📝 Commands:"
echo "  - Start continuous monitoring: sudo systemctl start ml-anomaly-detection"
echo "  - Run single detection: sudo systemctl start ml-anomaly-detect"
echo "  - Train models manually: sudo systemctl start ml-anomaly-training"
echo "  - View logs: sudo journalctl -u ml-anomaly-detection -f"
echo "  - View metrics: curl http://localhost:8090/metrics"
echo ""
echo "⚠️  Important:"
echo "  - Models need at least 10 training samples for initial training"
echo "  - Training happens automatically weekly, or manually via service"
echo "  - Continuous monitoring starts after initial training"
echo "  - Tune anomaly thresholds based on your system behavior"
