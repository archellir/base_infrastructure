#!/bin/bash

set -e

echo "🚀 Deploying Prometheus monitoring stack..."

# Deploy monitoring namespace and RBAC
echo "📁 Creating monitoring namespace and RBAC..."
kubectl apply -f namespace.yaml

# Deploy Prometheus configuration
echo "⚙️  Deploying Prometheus configuration..."
kubectl apply -f prometheus-config.yaml

# Deploy Prometheus server
echo "📊 Deploying Prometheus server..."
kubectl apply -f prometheus-deployment.yaml

# Deploy Node Exporter
echo "🖥️  Deploying Node Exporter..."
kubectl apply -f node-exporter.yaml

# Deploy kube-state-metrics
echo "📈 Deploying kube-state-metrics..."
kubectl apply -f kube-state-metrics.yaml

# Deploy custom storage exporter
echo "💾 Deploying storage metrics exporter..."
kubectl apply -f storage-exporter.yaml

echo "⏳ Waiting for deployments to be ready..."

# Wait for Prometheus to be ready
echo "   Waiting for Prometheus..."
kubectl wait --for=condition=Available deployment/prometheus -n monitoring --timeout=300s

# Wait for kube-state-metrics to be ready
echo "   Waiting for kube-state-metrics..."
kubectl wait --for=condition=Available deployment/kube-state-metrics -n monitoring --timeout=300s

# Wait for node-exporter DaemonSet to be ready
echo "   Waiting for node-exporter..."
kubectl rollout status daemonset/node-exporter -n monitoring --timeout=300s

# Wait for storage-exporter DaemonSet to be ready
echo "   Waiting for storage-exporter..."
kubectl rollout status daemonset/storage-exporter -n monitoring --timeout=300s

echo "✅ Prometheus monitoring stack deployed successfully!"

echo ""
echo "📋 Deployed components:"
echo "   • Prometheus server (scraping metrics)"
echo "   • Node Exporter (node-level metrics)"
echo "   • kube-state-metrics (Kubernetes object metrics)"
echo "   • Storage Exporter (storage I/O metrics)"
echo ""

echo "🔍 Checking deployment status..."
kubectl get all -n monitoring

echo ""
echo "🌐 To access Prometheus UI:"
echo "   kubectl port-forward -n monitoring svc/prometheus-service 9090:9090"
echo "   Then visit: http://localhost:9090"
echo ""

echo "📊 Available metrics endpoints:"
echo "   • Node metrics: http://node-ip:9100/metrics"
echo "   • Kube-state metrics: http://kube-state-metrics:8080/metrics"
echo "   • Storage metrics: http://storage-exporter:9101/metrics"
echo "   • Prometheus: http://prometheus-service:9090"
echo ""

echo "✨ Backend will automatically connect to Prometheus at:"
echo "   http://prometheus-service.monitoring.svc.cluster.local:9090"