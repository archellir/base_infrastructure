#!/bin/bash

# Kubernetes Infrastructure Cleanup Script
# Completely removes all infrastructure and persistent data for fresh deployment

set -e

echo "🧹 Starting complete infrastructure cleanup..."
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "   - All Kubernetes resources in base-infra namespace"
echo "   - All PersistentVolumes and data"
echo "   - All application data in /root/containers/"
echo ""
if [[ "$1" == "--ingress" || "$1" == "-i" ]]; then
    REPLY="y"
    echo "🧹 Proceeding with cleanup (via argument)..."
else
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cleanup cancelled"
        exit 1
    fi
fi

# Step 1: Delete all Kubernetes resources
echo "🗑️  Deleting Kubernetes resources..."
kubectl delete namespace base-infra --ignore-not-found=true
kubectl delete pv --all --ignore-not-found=true

# Clean up cert-manager resources
echo "🔐 Cleaning up SSL certificates and cert-manager..."
kubectl delete clusterissuer letsencrypt-prod --ignore-not-found=true || true
kubectl delete namespace cert-manager --ignore-not-found=true || true

# Clean up ingress controller
echo "🔀 Cleaning up ingress controller..."
kubectl delete namespace ingress-nginx --ignore-not-found=true || true

# Clean up Docker-style iptables bypass rules
echo "🔧 Removing iptables bypass rules..."
iptables -D INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "DOCKER-STYLE-HTTP-BYPASS" 2>/dev/null || true
iptables -D INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "DOCKER-STYLE-HTTPS-BYPASS" 2>/dev/null || true
echo "✅ iptables bypass rules removed"

# Wait for namespace to be fully deleted
echo "⏳ Waiting for namespace cleanup..."
kubectl wait --for=delete namespace/base-infra --timeout=60s 2>/dev/null || true

# Step 2: Clean up persistent storage directories (force complete removal)
echo "💾 Cleaning up persistent storage..."
rm -rf /root/containers/postgresql-k8s-data
rm -rf /root/containers/gitea-k8s-data
rm -rf /root/containers/memos-k8s-data
rm -rf /root/containers/filestash-k8s
rm -rf /root/containers/uptime-kuma-k8s-data

# Step 3: Recreate fresh directories with proper ownership
echo "📁 Creating fresh storage directories..."
mkdir -p /root/containers/postgresql-k8s-data
mkdir -p /root/containers/gitea-k8s-data
mkdir -p /root/containers/memos-k8s-data
mkdir -p /root/containers/filestash-k8s/data
mkdir -p /root/containers/filestash-k8s/config
mkdir -p /root/containers/uptime-kuma-k8s-data
echo "  ⚠️  All services will reinitialize with fresh data"

# Set proper ownership for containers  
chown -R 1000:1000 /root/containers/postgresql-k8s-data
chown -R 1000:1000 /root/containers/gitea-k8s-data
chown -R 1000:1000 /root/containers/memos-k8s-data
chown -R 1000:1000 /root/containers/filestash-k8s
chown -R 1000:1000 /root/containers/uptime-kuma-k8s-data

# Step 4: Verify cleanup
echo ""
echo "✅ Cleanup complete! Verification:"
echo ""
echo "Kubernetes resources:"
kubectl get namespace base-infra 2>/dev/null || echo "✓ Namespace deleted"
kubectl get pv 2>/dev/null || echo "✓ No PersistentVolumes found"
echo ""
echo "Storage directories:"
ls -la /root/containers/ | grep k8s

echo ""
echo "🎉 Infrastructure completely cleaned!"
echo "📦 Ready for fresh deployment with: ./deploy.sh"