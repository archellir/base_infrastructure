#!/bin/bash

# Kubernetes Infrastructure Deployment Script
# Deploys base infrastructure services in proper dependency order

set -e

echo "🚀 Starting Kubernetes infrastructure deployment..."

# Step 1: Create namespace and wait for it to be ready
echo "📦 Creating namespace..."
kubectl apply -f k8s/namespace/
kubectl wait --for=condition=Active namespace/base-infrastructure --timeout=30s

# Step 2: Create storage resources
echo "💾 Setting up storage..."
kubectl apply -f k8s/storage/

# Step 3: Deploy PostgreSQL database (core dependency)
echo "🗄️  Deploying PostgreSQL database..."
kubectl apply -f k8s/postgresql/

# Step 4: Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql -n base-infrastructure --timeout=300s

# Step 5: Deploy application services
echo "🌐 Deploying application services..."
kubectl apply -f k8s/gitea/
kubectl apply -f k8s/umami/
kubectl apply -f k8s/memos/
kubectl apply -f k8s/filestash/
kubectl apply -f k8s/uptime-kuma/

# Step 6: Deploy static sites
echo "📄 Deploying static sites..."
kubectl apply -f k8s/static-sites/

# Step 7: Ask about ingress deployment
echo ""
read -p "🔀 Deploy ingress routing? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔀 Setting up ingress routing..."
    kubectl apply -f k8s/ingress/
else
    echo "⏭️  Skipping ingress deployment"
fi

# Step 8: Show deployment status
echo ""
echo "✅ Deployment complete! Checking status..."
echo ""
echo "Pods:"
kubectl get pods -n base-infrastructure
echo ""
echo "Services:"
kubectl get services -n base-infrastructure
echo ""
echo "PersistentVolumeClaims:"
kubectl get pvc -n base-infrastructure

echo ""
echo "🎉 Infrastructure deployment finished!"
echo "📊 Use 'kubectl get pods -n base-infrastructure' to monitor pod status"
echo "🔍 Use 'kubectl logs -f deployment/<service-name> -n base-infrastructure' to view logs"
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "To enable ingress routing later:"
    echo "kubectl apply -f k8s/ingress/"
fi