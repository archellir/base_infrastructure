#!/bin/bash

# Kubernetes Infrastructure Deployment Script
# Deploys base infrastructure services in proper dependency order

set -e

# Start background keepalive to prevent SSH timeout
keepalive_job() {
    while true; do
        sleep 30
        kubectl get nodes --no-headers >/dev/null 2>&1 || true
    done
} 
keepalive_job &
KEEPALIVE_PID=$!

# Cleanup function to kill keepalive on exit
cleanup() {
    kill $KEEPALIVE_PID 2>/dev/null || true
}
trap cleanup EXIT

# Progress tracking
TOTAL_STEPS=8
CURRENT_STEP=0

progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo "[$CURRENT_STEP/$TOTAL_STEPS] $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

wait_for_condition() {
    echo "⏳ $1"
    local timeout=300  # 5 minutes
    local count=0
    while [ $count -lt $timeout ]; do
        if eval "$2"; then
            echo ""
            echo "✅ Ready!"
            return 0
        fi
        # Progress indicator with time
        local minutes=$((count / 60))
        local seconds=$((count % 60))
        printf "\r⏳ Waiting... ${minutes}m ${seconds}s "
        
        # SSH keepalive - send a simple command every 30 seconds
        if [ $((count % 30)) -eq 0 ] && [ $count -gt 0 ]; then
            kubectl get nodes --no-headers >/dev/null 2>&1
            printf "[keepalive]"
        fi
        
        sleep 1
        count=$((count + 1))
    done
    echo ""
    echo "⚠️  Timeout after ${timeout} seconds, continuing anyway..."
    return 1
}

echo "🚀 Starting Kubernetes infrastructure deployment..."
echo "   Total steps: $TOTAL_STEPS"
echo ""

# Step 1: Create namespace
progress "📦 Creating namespace"
kubectl apply -f k8s/namespace/namespace.yaml
wait_for_condition "Waiting for namespace to be active" "kubectl get namespace base-infrastructure -o jsonpath='{.status.phase}' 2>/dev/null | grep -q 'Active'" || true

# Step 2: Apply secrets and configmaps
progress "🔑 Creating secrets and configmaps"
kubectl apply -f k8s/namespace/secrets.yaml
kubectl apply -f k8s/namespace/configmap.yaml

# Step 3: Create storage resources
progress "💾 Setting up storage"
kubectl apply -f k8s/storage/

# Step 4: Deploy PostgreSQL database (core dependency)
progress "🗄️  Deploying PostgreSQL database"
kubectl apply -f k8s/postgresql/
wait_for_condition "Waiting for PostgreSQL to be ready" "kubectl get pods -l app=postgresql -n base-infrastructure -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q 'Running'" || true

# Step 5: Deploy application services
progress "🌐 Deploying application services"
kubectl apply -f k8s/gitea/
kubectl apply -f k8s/umami/
kubectl apply -f k8s/memos/
kubectl apply -f k8s/filestash/
kubectl apply -f k8s/uptime-kuma/

# Step 6: Deploy static sites
progress "📄 Deploying static sites"
kubectl apply -f k8s/static-sites/

# Step 7: Ask about ingress deployment
progress "🔀 Configuring ingress routing"
read -p "Deploy ingress routing? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔐 Installing cert-manager for SSL certificates..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
    wait_for_condition "Waiting for cert-manager to be ready" "kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q 'Running'" || true
    
    echo "🔐 Creating Let's Encrypt ClusterIssuer..."
    kubectl apply -f k8s/cert-manager/
    
    echo "🔀 Setting up ingress routing with SSL..."
    kubectl apply -f k8s/ingress/
    
    echo "🔀 Setting up port forwarding (80/443 → NodePort)..."
    kubectl apply -f k8s/port-forward/
    wait_for_condition "Waiting for port forwarder to be ready" "kubectl get pods -l app=port-forwarder -n base-infrastructure -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q 'Running'" || true
    
    echo "🔐 SSL certificates will be automatically provisioned by Let's Encrypt"
else
    echo "⏭️  Skipping ingress deployment"
fi

# Step 8: Show deployment status
progress "✅ Deployment complete! Checking status"
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