# Machine Learning Anomaly Detection

The System Maintenance Suite includes machine learning-based anomaly detection to identify unusual patterns in system metrics and potential security threats.

## Overview

The ML anomaly detection system uses multiple algorithms to detect anomalies in real-time:
- **Isolation Forest**: Ensemble-based anomaly detection
- **One-Class SVM**: Support vector machine for novelty detection
- **Statistical Analysis**: Z-score based anomaly detection
- **Ensemble Methods**: Combines multiple detectors for improved accuracy

## Features

### Real-time Monitoring
- Continuous monitoring of system metrics
- Multi-algorithm anomaly detection
- Ensemble voting for robust detection
- Automatic model retraining

### Supported Metrics
- **CPU Usage**: CPU utilization, load averages, process counts
- **Memory Usage**: Memory utilization, available memory
- **Disk Usage**: Disk utilization, I/O metrics
- **Network Metrics**: Traffic volume, packet counts
- **Process Metrics**: Process counts, resource-intensive processes

### Detection Methods

#### Isolation Forest
- Based on random forest algorithm
- Effective for high-dimensional data
- Fast detection speed
- Good for large datasets

#### One-Class SVM
- Kernel-based anomaly detection
- Effective for complex patterns
- Good for non-linear relationships
- Requires more computational resources

#### Statistical Analysis
- Z-score based detection
- Simple and interpretable
- Fast computation
- Good baseline method

#### Ensemble Methods
- Combines multiple detectors
- Majority voting for decisions
- Reduced false positives
- Improved detection accuracy

## Installation

### Automated Setup

```bash
cd scripts/ml-anomaly
./setup_ml_anomaly.sh
```

### Manual Setup

```bash
# Install Python dependencies
pip install -r scripts/ml-anomaly/requirements.txt

# Create directories
sudo mkdir -p /var/log/ml-anomaly
sudo mkdir -p /var/lib/ml-anomaly/models
sudo mkdir -p /var/lib/ml-anomaly/metrics

# Set permissions
sudo chown -R $USER:$USER /var/log/ml-anomaly
sudo mkdir -p /var/lib/ml-anomaly
```

## Usage

### Training Models

```bash
# Train with 100 samples (default)
python3 scripts/ml-anomaly/anomaly_detector.py --mode train

# Train with custom number of samples
python3 scripts/ml-anomaly/anomaly_detector.py --mode train --training-samples 200

# Train specific detector
python3 scripts/ml-anomaly/anomaly_detector.py --mode train --detector isolation_forest
```

### Anomaly Detection

```bash
# Single detection check
python3 scripts/ml-anomaly/anomaly_detector.py --mode detect

# Use specific detector
python3 scripts/ml-anomaly/anomaly_detector.py --mode detect --detector statistical

# Continuous monitoring
python3 scripts/ml-anomaly/anomaly_detector.py --mode continuous
```

### Systemd Services

```bash
# Start continuous monitoring
sudo systemctl start ml-anomaly-detection

# Enable at boot
sudo systemctl enable ml-anomaly-detection

# View logs
sudo journalctl -u ml-anomaly-detection -f

# Run manual detection
sudo systemctl start ml-anomaly-detect

# Trigger model training
sudo systemctl start ml-anomaly-training

# View Prometheus metrics
curl http://localhost:8090/metrics
```

## Configuration

### Model Parameters

Edit `scripts/ml-anomaly/anomaly_detector.py` to adjust parameters:

#### Isolation Forest
```python
self.contamination = 0.1  # Expected proportion of outliers (0.1 = 10%)
self.n_estimators = 100   # Number of trees in the forest
```

#### One-Class SVM
```python
self.nu = 0.1  # Upper bound on fraction of outliers (0.1 = 10%)
self.kernel = 'rbf'  # Kernel function
```

#### Statistical Detection
```python
self.z_threshold = 3.0  # Z-score threshold for anomalies
```

### Monitoring Intervals

Adjust collection frequency in continuous mode:
```python
time.sleep(60)  # Check every 60 seconds
```

### Training Schedule

Modify systemd timer for training frequency:
```bash
sudo systemctl edit ml-anomaly-training.timer
# Change OnCalendar=weekly to desired frequency
```

## Integration

### Prometheus Integration

The system includes a Prometheus metrics exporter:

```bash
# Metrics available at http://localhost:8090/metrics
# Metrics include:
# - ml_anomaly_detections_total
# - ml_anomaly_latest_score
# - ml_model_training_duration_seconds
# - ml_system_metric{metric_name}
```

### Grafana Dashboard

Add to existing Grafana dashboard:
- Query: `ml_anomaly_detections_total`
- Alert on threshold: Rate of detections
- Visualize trends over time

### Alert Integration

Configure alerts in Prometheus:
```yaml
- alert: HighAnomalyRate
  expr: rate(ml_anomaly_detections_total[5m]) > 0.1
  for: 10m
  annotations:
    summary: "High anomaly detection rate"
```

## Performance Considerations

### Resource Usage
- **CPU**: Minimal for statistical methods, moderate for ML methods
- **Memory**: Depends on training data size
- **Storage**: Models ~10MB, metrics accumulate over time

### Optimization Tips
1. **Sampling Rate**: Adjust based on system capacity
2. **Training Data**: Keep training dataset manageable
3. **Model Complexity**: Use simpler models for resource-constrained systems
4. **Detection Frequency**: Balance between responsiveness and resource usage

### Scaling
- **Single System**: Current implementation suitable for individual servers
- **Multi-Server**: Deploy detector on each server or central monitoring server
- **Cloud**: Use auto-scaling for detection services

## Troubleshooting

### Insufficient Training Data
**Problem**: Model not trained due to lack of data
**Solution**: 
```bash
# Collect more training samples
python3 anomaly_detector.py --mode train --training-samples 200
```

### High False Positive Rate
**Problem**: Too many false anomalies detected
**Solution**: Adjust contamination parameter or z_threshold
```python
self.contamination = 0.05  # Reduce from 0.1
self.z_threshold = 4.0  # Increase from 3.0
```

### Model Performance Degradation
**Problem**: Detection accuracy decreases over time
**Solution**: Retrain model with fresh data
```bash
sudo systemctl start ml-anomaly-training
```

### Memory Issues
**Problem**: High memory usage during training
**Solution**: Reduce training samples or use simpler models
```python
--training-samples 50  # Reduce from default 100
--detector statistical  # Use simpler method
```

## Advanced Features

### Custom Detectors

Add custom anomaly detection algorithms:

```python
class CustomDetector(AnomalyDetector):
    def __init__(self):
        super().__init__('custom_detector')
    
    def train(self, metrics_list):
        # Custom training logic
        pass
    
    def detect_anomalies(self, metrics):
        # Custom detection logic
        pass
```

### Feature Engineering

Add custom features to metrics collection:

```python
def collect_custom_metrics(self):
    # Add custom metrics
    return {
        'custom_metric_1': value1,
        'custom_metric_2': value2
    }
```

### Alert Integration

Integrate with alerting systems:

```python
if result.get('is_anomaly'):
    send_alert(result)
    log_to_security_system(result)
```

## Best Practices

### Data Quality
1. **Consistent Collection**: Maintain consistent metric collection intervals
2. **Data Cleaning**: Handle missing or corrupted data properly
3. **Normalization**: Scale features appropriately for ML algorithms
4. **Feature Selection**: Use relevant metrics for detection

### Model Management
1. **Regular Retraining**: Retrain models periodically with fresh data
2. **Version Control**: Keep track of model versions and performance
3. **A/B Testing**: Test new models alongside existing ones
4. **Performance Monitoring**: Track model performance over time

### Operational Excellence
1. **Monitoring**: Monitor the anomaly detection system itself
2. **Alerting**: Set up appropriate alert thresholds
3. **Documentation**: Document model parameters and performance
4. **Testing**: Test detection accuracy with known anomalies

## Security Considerations

### Data Privacy
- **Sensitive Metrics**: Avoid collecting sensitive information
- **Data Retention**: Implement appropriate data retention policies
- **Access Control**: Restrict access to anomaly detection data

### Model Security
- **Model Storage**: Secure storage of trained models
- **Adversarial Attacks**: Monitor for potential adversarial inputs
- **Explainability**: Provide explanations for anomaly detections

### Integration Security
- **API Security**: Secure Prometheus metrics endpoint
- **Authentication**: Implement authentication for web interfaces
- **Audit Logging**: Log all anomaly detection activities

## Automated Remediation (Free Local LLM)

Detection is only half the story. The suite can automatically diagnose an
anomaly and propose (or safely apply) a remediation plan using a **free,
open-weight model running locally via Ollama** — no API keys, no cost, no data
leaving the host.

### Architecture

```
anomaly_detector.py  --(latest_detection.json)-->  run_ml_pipeline.sh
                                                    |
                                                    v
                                            ml_fix_engine.py
                                                    |
                                          +---------+---------+
                                          |                   |
                                     Ollama (local)     safety validator
                                     llama3.2 / mistral       |
                                                          v
                                              report | apply | dry-run
                                                  +----------> Alertmanager
```

`ml_fix_engine.py` sends the anomaly report plus recent metrics context to the
LLM, which returns a JSON plan (`diagnosis`, `severity`, `remediation_steps`).
Every `command` in the plan is validated before it can run:

- **Deny-list**: `rm -rf /`, `mkfs`, `dd if=`, `chmod -R 777 /`, `curl|bash`,
  `wget|bash`, `reboot`, `shutdown`, and similar destructive tokens.
- **Allow-list**: only `systemctl restart/reload <known service>`,
  `docker restart/start <known container>`, `logrotate`, `journalctl`, safe
  `find /tmp` cleanup, `truncate -s 0`, etc.

Anything not explicitly allowed is dropped and flagged `needs human review`.

### Modes

| Mode | Behavior |
|------|----------|
| `report` (default) | Write `remediation_<ts>.json`, optionally POST to Alertmanager. No commands run. |
| `dry-run` | Print the plan and the exact commands that *would* run. |
| `apply` | Execute only the allow-listed, low-risk commands automatically. |

### Setup

```bash
# Install ML stack + pull a free local model
bash scripts/ml-anomaly/setup_ml_anomaly.sh

# Run the full pipeline once (detect -> diagnose -> report)
sudo systemctl start ml-anomaly-fix

# Or interactively
ML_FIX_MODE=dry-run  bash scripts/ml-anomaly/run_ml_pipeline.sh
ML_FIX_MODE=apply    bash scripts/ml-anomaly/run_ml_pipeline.sh
```

### Configuration (environment variables)

| Variable | Default | Purpose |
|----------|---------|---------|
| `ML_FIX_PROVIDER` | `ollama` | `ollama` or `openai-compatible` |
| `ML_FIX_MODEL` | `llama3.2` | Model name to use |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama endpoint |
| `ML_FIX_API_BASE` | `http://localhost:8080/v1` | OpenAI-compatible endpoint |
| `ML_FIX_WEBHOOK` | _(empty)_ | Alertmanager webhook URL |
| `ML_FIX_MODE` | `report` | `report` \| `dry-run` \| `apply` |

> Safety: `apply` mode only runs commands on the allow-list. Review the
> generated `remediation_*.json` reports before enabling `apply` in production.

## Future Enhancements

- [ ] Deep learning models (Autoencoders, LSTMs)
- [ ] Real-time feature streaming
- [ ] Distributed anomaly detection
- [ ] Automated alert correlation
- [ ] Integration with SIEM systems
- [ ] Explainable AI for anomaly explanations
- [ ] Transfer learning for new environments
- [ ] Cloud-native deployment support

## Contributing

When contributing to the ML anomaly detection system:
1. Test with various system configurations
2. Validate detection accuracy
3. Document new algorithms or features
4. Update performance benchmarks
5. Ensure backward compatibility

---

**Note**: ML-based anomaly detection requires sufficient training data and tuning. Start with conservative thresholds and adjust based on your specific system behavior and requirements.
