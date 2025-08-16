#!/bin/bash

# Monitoring Stack Verification Script
# Verifies that all monitoring components are functioning and collecting metrics

set -e

echo "🔍 Verifying Prometheus monitoring stack..."
echo ""

# Check if monitoring namespace exists
echo "📁 Checking monitoring namespace..."
if kubectl get namespace monitoring >/dev/null 2>&1; then
    echo "✅ Monitoring namespace exists"
else
    echo "❌ Monitoring namespace not found"
    exit 1
fi

# Check pod status
echo ""
echo "🔍 Checking pod status..."
kubectl get pods -n monitoring

# Function to check if pods are running
check_pods_running() {
    local deployment=$1
    local namespace=$2
    
    echo "Checking $deployment..."
    if kubectl get pods -n $namespace -l app=$deployment -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q 'Running'; then
        echo "✅ $deployment is running"
        return 0
    else
        echo "❌ $deployment is not running"
        return 1
    fi
}

# Check each component
echo ""
echo "🔍 Verifying component status..."
check_pods_running "prometheus" "monitoring"
check_pods_running "kube-state-metrics" "monitoring"

# Check DaemonSets
echo "Checking DaemonSets..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
NODEEXPORTER_COUNT=$(kubectl get pods -n monitoring -l app=node-exporter --no-headers | grep Running | wc -l)
STORAGEEXPORTER_COUNT=$(kubectl get pods -n monitoring -l app=storage-exporter --no-headers | grep Running | wc -l)

if [ "$NODEEXPORTER_COUNT" -eq "$NODE_COUNT" ]; then
    echo "✅ Node Exporter running on all $NODE_COUNT nodes"
else
    echo "❌ Node Exporter: expected $NODE_COUNT, got $NODEEXPORTER_COUNT"
fi

if [ "$STORAGEEXPORTER_COUNT" -eq "$NODE_COUNT" ]; then
    echo "✅ Storage Exporter running on all $NODE_COUNT nodes"
else
    echo "❌ Storage Exporter: expected $NODE_COUNT, got $STORAGEEXPORTER_COUNT"
fi

# Check if Prometheus is accessible
echo ""
echo "🔍 Testing Prometheus API accessibility..."
if kubectl exec -n monitoring deployment/prometheus -- wget -q --spider http://localhost:9090/-/healthy; then
    echo "✅ Prometheus health endpoint responding"
else
    echo "❌ Prometheus health endpoint not responding"
    exit 1
fi

# Test metrics collection
echo ""
echo "🔍 Verifying metrics collection..."

# Test if Prometheus can scrape itself
PROMETHEUS_UP=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"prometheus\"}" 2>/dev/null | grep -o '"value":\["[^"]*","[^"]*"\]' | grep -o '"1"' || echo "")
if [ "$PROMETHEUS_UP" = '"1"' ]; then
    echo "✅ Prometheus self-monitoring working"
else
    echo "❌ Prometheus self-monitoring failed"
fi

# Test node exporter metrics
NODE_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"kubernetes-node-exporter\"}" 2>/dev/null | grep -c '"1"' || echo "0")
if [ "$NODE_METRICS" -gt 0 ]; then
    echo "✅ Node Exporter metrics available ($NODE_METRICS targets)"
else
    echo "❌ Node Exporter metrics not available"
fi

# Test kube-state-metrics
KUBE_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"kube-state-metrics\"}" 2>/dev/null | grep -c '"1"' || echo "0")
if [ "$KUBE_METRICS" -gt 0 ]; then
    echo "✅ kube-state-metrics available"
else
    echo "❌ kube-state-metrics not available"
fi

# Test storage exporter metrics
STORAGE_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=up{job=\"storage-exporter\"}" 2>/dev/null | grep -c '"1"' || echo "0")
if [ "$STORAGE_METRICS" -gt 0 ]; then
    echo "✅ Storage Exporter metrics available ($STORAGE_METRICS targets)"
else
    echo "❌ Storage Exporter metrics not available"
fi

# Test specific metrics that denshimon uses
echo ""
echo "🔍 Testing key metrics for denshimon integration..."

# CPU metrics
CPU_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=node_cpu_seconds_total" 2>/dev/null | grep -c '"__name__":"node_cpu_seconds_total"' || echo "0")
if [ "$CPU_METRICS" -gt 0 ]; then
    echo "✅ CPU metrics available"
else
    echo "❌ CPU metrics not available"
fi

# Memory metrics
MEMORY_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=node_memory_MemTotal_bytes" 2>/dev/null | grep -c '"__name__":"node_memory_MemTotal_bytes"' || echo "0")
if [ "$MEMORY_METRICS" -gt 0 ]; then
    echo "✅ Memory metrics available"
else
    echo "❌ Memory metrics not available"
fi

# Network metrics
NETWORK_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=container_network_receive_bytes_total" 2>/dev/null | grep -c '"__name__":"container_network_receive_bytes_total"' || echo "0")
if [ "$NETWORK_METRICS" -gt 0 ]; then
    echo "✅ Network metrics available"
else
    echo "❌ Network metrics not available"
fi

# Storage metrics (custom exporter)
STORAGE_CUSTOM_METRICS=$(kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=storage_volume_read_iops" 2>/dev/null | grep -c '"__name__":"storage_volume_read_iops"' || echo "0")
if [ "$STORAGE_CUSTOM_METRICS" -gt 0 ]; then
    echo "✅ Custom storage metrics available"
else
    echo "❌ Custom storage metrics not available"
fi

echo ""
echo "🔍 Checking Prometheus targets..."
# Get target status
kubectl exec -n monitoring deployment/prometheus -- wget -qO- "http://localhost:9090/api/v1/targets" 2>/dev/null | grep -o '"health":"[^"]*"' | sort | uniq -c

echo ""
echo "📊 Service endpoints for denshimon integration:"
echo "   Prometheus API: http://prometheus-service.monitoring.svc.cluster.local:9090"
echo "   Health check: http://prometheus-service.monitoring.svc.cluster.local:9090/-/healthy"
echo "   Metrics query: http://prometheus-service.monitoring.svc.cluster.local:9090/api/v1/query"
echo "   Range query: http://prometheus-service.monitoring.svc.cluster.local:9090/api/v1/query_range"

echo ""
echo "✅ Monitoring stack verification complete!"
echo "🔗 denshimon backend can now connect to get real metrics data"