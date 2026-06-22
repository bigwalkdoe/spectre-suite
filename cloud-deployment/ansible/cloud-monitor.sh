#!/bin/bash
# Cloud Monitoring Script for System Maintenance Suite
# Collects and sends metrics to cloud provider monitoring services

# Source configuration if available
if [ -f /etc/system-maintenance/cloud-config.yml ]; then
    eval $(yaml-to-bash /etc/system-maintenance/cloud-config.yml)
fi

CLOUD_PROVIDER="${cloud_provider:-aws}"
ENVIRONMENT="${environment:-production}"

# Collect system metrics
collect_metrics() {
    # CPU Usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    # Memory Usage
    MEMORY_USAGE=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
    
    # Disk Usage
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    # Network I/O
    NETWORK_IN=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
    NETWORK_OUT=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')
    
    # Docker status
    DOCKER_CONTAINERS=$(docker ps --format "{{.Names}}" | wc -l)
    DOCKER_RUNNING=$(docker ps --format "{{.Names}}" | wc -l)
    
    # Backup status
    BACKUP_STATUS=$(systemctl is-active backup.timer)
    
    # Security status
    FAIL2BAN_STATUS=$(systemctl is-active fail2ban)
    
    # System load
    LOAD_1MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    LOAD_5MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//')
    LOAD_15MIN=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $3}')
    
    # Timestamp
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "CPU:$CPU_USAGE,MEM:$MEMORY_USAGE,DISK:$DISK_USAGE,NET_IN:$NETWORK_IN,NET_OUT:$NETWORK_OUT,DOCKER:$DOCKER_CONTAINERS,BACKUP:$BACKUP_STATUS,SECURITY:$FAIL2BAN_STATUS,LOAD1:$LOAD_1MIN,LOAD5:$LOAD_5MIN,LOAD15:$LOAD_15MIN,TIME:$TIMESTAMP"
}

# Send metrics to AWS CloudWatch
send_to_cloudwatch() {
    local metrics=$1
    
    if command -v aws >/dev/null 2>&1; then
        INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
        
        # Parse metrics
        CPU=$(echo $metrics | cut -d',' -f1 | cut -d':' -f2)
        MEM=$(echo $metrics | cut -d',' -f2 | cut -d':' -f2)
        DISK=$(echo $metrics | cut -d',' -f3 | cut -d':' -f2)
        NET_IN=$(echo $metrics | cut -d',' -f4 | cut -d':' -f2)
        NET_OUT=$(echo $metrics | cut -d',' -f5 | cut -d':' -f2)
        
        # Send to CloudWatch
        aws cloudwatch put-metric-data \
            --namespace SystemMaintenance \
            --metric-name CPUUsage \
            --value $CPU \
            --dimensions InstanceId=$INSTANCE_ID,Environment=$ENVIRONMENT \
            --unit Percent 2>/dev/null
        
        aws cloudwatch put-metric-data \
            --namespace SystemMaintenance \
            --metric-name MemoryUsage \
            --value $MEM \
            --dimensions InstanceId=$INSTANCE_ID,Environment=$ENVIRONMENT \
            --unit Percent 2>/dev/null
        
        aws cloudwatch put-metric-data \
            --namespace SystemMaintenance \
            --metric-name DiskUsage \
            --value $DISK \
            --dimensions InstanceId=$INSTANCE_ID,Environment=$ENVIRONMENT \
            --unit Percent 2>/dev/null
        
        aws cloudwatch put-metric-data \
            --namespace SystemMaintenance \
            --metric-name NetworkInBytes \
            --value $NET_IN \
            --dimensions InstanceId=$INSTANCE_ID,Environment=$ENVIRONMENT \
            --unit Bytes 2>/dev/null
        
        aws cloudwatch put-metric-data \
            --namespace SystemMaintenance \
            --metric-name NetworkOutBytes \
            --value $NET_OUT \
            --dimensions InstanceId=$INSTANCE_ID,Environment=$ENVIRONMENT \
            --unit Bytes 2>/dev/null
    fi
}

# Send metrics to Azure Monitor
send_to_azure_monitor() {
    local metrics=$1
    
    if command -v az >/dev/null 2>&1; then
        # Azure Monitor integration would require additional setup
        echo "Azure Monitor integration requires additional configuration"
    fi
}

# Send metrics to GCP Stackdriver
send_to_stackdriver() {
    local metrics=$1
    
    if command -v gcloud >/dev/null 2>&1; then
        # GCP Stackdriver integration would require additional setup
        echo "Stackdriver integration requires additional configuration"
    fi
}

# Send metrics to Prometheus Pushgateway (if configured)
send_to_prometheus() {
    local metrics=$1
    
    PROMETHEUS_PUSHGATEWAY="${prometheus_pushgateway_url:-localhost:9091}"
    
    if curl -s http://$PROMETHEUS_PUSHGATEWAY/-/healthy >/dev/null 2>&1; then
        # Parse and format metrics for Prometheus
        CPU=$(echo $metrics | cut -d',' -f1 | cut -d':' -f2)
        MEM=$(echo $metrics | cut -d',' -f2 | cut -d':' -f2)
        DISK=$(echo $metrics | cut -d',' -f3 | cut -d':' -f2)
        
        cat <<EOF | curl --data-binary @- http://$PROMETHEUS_PUSHGATEWAY/metrics/job/cloud-monitor/instance/$(hostname)
system_maintenance_cpu_usage $CPU
system_maintenance_memory_usage $MEM
system_maintenance_disk_usage $DISK
EOF
    fi
}

# Log metrics locally
log_metrics() {
    local metrics=$1
    local log_file="/var/log/cloud-monitoring/metrics.log"
    
    mkdir -p /var/log/cloud-monitoring
    echo "$metrics" >> $log_file
    
    # Rotate log if too large
    if [ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file") -gt 10485760 ]; then
        mv $log_file ${log_file}.old
        echo "$metrics" > $log_file
    fi
}

# Health check endpoint
health_check() {
    local health_file="/var/www/html/health.json"
    
    local metrics=$(collect_metrics)
    local CPU=$(echo $metrics | cut -d',' -f1 | cut -d':' -f2)
    local MEM=$(echo $metrics | cut -d',' -f2 | cut -d':' -f2)
    local DISK=$(echo $metrics | cut -d',' -f3 | cut -d':' -f2)
    
    # Determine overall health
    local overall_health="healthy"
    if (( $(echo "$CPU > 90" | bc -l) )) || (( $(echo "$MEM > 90" | bc -l) )) || (( $(echo "$DISK > 90" | bc -l) )); then
        overall_health="unhealthy"
    elif (( $(echo "$CPU > 80" | bc -l) )) || (( $(echo "$MEM > 80" | bc -l) )) || (( $(echo "$DISK > 80" | bc -l) )); then
        overall_health="warning"
    fi
    
    cat > $health_file <<EOF
{
    "status": "$overall_health",
    "environment": "$ENVIRONMENT",
    "hostname": "$(hostname)",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "metrics": {
        "cpu_usage": $CPU,
        "memory_usage": $MEM,
        "disk_usage": $DISK,
        "docker_containers": $(echo $metrics | cut -d',' -f6 | cut -d':' -f2),
        "backup_status": "$(echo $metrics | cut -d',' -f7 | cut -d':' -f2)",
        "security_status": "$(echo $metrics | cut -d',' -f8 | cut -d':' -f2)",
        "load_1min": $(echo $metrics | cut -d',' -f9 | cut -d':' -f2),
        "load_5min": $(echo $metrics | cut -d',' -f10 | cut -d':' -f2),
        "load_15min": $(echo $metrics | cut -d',' -f11 | cut -d':' -f2)
    }
}
EOF
}

# Main execution
main() {
    local metrics=$(collect_metrics)
    
    # Log metrics locally
    log_metrics "$metrics"
    
    # Send to cloud provider based on configuration
    case $CLOUD_PROVIDER in
        aws)
            send_to_cloudwatch "$metrics"
            ;;
        azure)
            send_to_azure_monitor "$metrics"
            ;;
        gcp)
            send_to_stackdriver "$metrics"
            ;;
        *)
            echo "Unknown cloud provider: $CLOUD_PROVIDER"
            ;;
    esac
    
    # Send to Prometheus if configured
    send_to_prometheus "$metrics"
    
    # Update health check endpoint
    health_check
    
    echo "Cloud monitoring completed: $metrics"
}

# Execute main function
main
