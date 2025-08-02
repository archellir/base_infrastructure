#!/bin/bash

# K8s WebUI Deployment Script
# This script deploys the K8s WebUI to the Kubernetes cluster

set -e

echo "🚀 Deploying K8s WebUI to Kubernetes cluster..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
    exit 1
fi

print_status "Connected to Kubernetes cluster"

# Apply namespace and RBAC first
print_status "Creating namespace and RBAC..."
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml

# Apply secrets and configuration
print_status "Creating secrets and configuration..."
kubectl apply -f secrets.yaml

# Deploy database and cache
print_status "Deploying PostgreSQL database..."
kubectl apply -f postgres.yaml

print_status "Deploying Redis cache..."
kubectl apply -f redis.yaml

# Wait for PostgreSQL to be ready
print_status "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=k8s-webui-postgres -n k8s-webui --timeout=300s

print_status "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=k8s-webui-redis -n k8s-webui --timeout=180s

# Deploy application services
print_status "Deploying backend API..."
kubectl apply -f backend-deployment.yaml

print_status "Deploying frontend..."
kubectl apply -f frontend-deployment.yaml

# Wait for deployments to be ready
print_status "Waiting for backend to be ready..."
kubectl wait --for=condition=available deployment/k8s-webui-backend -n k8s-webui --timeout=300s

print_status "Waiting for frontend to be ready..."
kubectl wait --for=condition=available deployment/k8s-webui-frontend -n k8s-webui --timeout=300s

# Apply ingress
print_status "Creating ingress..."
kubectl apply -f ingress.yaml

# Show deployment status
echo ""
print_status "Deployment completed successfully! 🎉"
echo ""
echo "📊 Deployment Status:"
kubectl get pods -n k8s-webui
echo ""
kubectl get services -n k8s-webui
echo ""
kubectl get ingress -n k8s-webui
echo ""

print_status "K8s WebUI should be available at: https://k8s.arcbjorn.com"
print_warning "Default credentials: admin / admin (please change in production)"

echo ""
echo "🔍 To check logs:"
echo "  Backend:  kubectl logs -f deployment/k8s-webui-backend -n k8s-webui"
echo "  Frontend: kubectl logs -f deployment/k8s-webui-frontend -n k8s-webui"
echo ""
echo "🗑️  To remove:"
echo "  kubectl delete namespace k8s-webui"