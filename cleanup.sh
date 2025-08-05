#!/bin/bash

# Kubernetes Infrastructure Cleanup Script
# Completely removes all infrastructure and persistent data for fresh deployment

set -e

echo "🧹 Starting complete infrastructure cleanup..."
echo ""
echo "⚠️  WARNING: This will permanently delete:"
echo "   - All Kubernetes resources in base-infrastructure namespace"
echo "   - All PersistentVolumes and data"
echo "   - All application data in /root/containers/"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 1
fi

# Step 1: Delete all Kubernetes resources
echo "🗑️  Deleting Kubernetes resources..."
kubectl delete namespace base-infrastructure --ignore-not-found=true
kubectl delete pv --all --ignore-not-found=true

# Wait for namespace to be fully deleted
echo "⏳ Waiting for namespace cleanup..."
kubectl wait --for=delete namespace/base-infrastructure --timeout=60s 2>/dev/null || true

# Step 2: Clean up persistent storage directories
echo "💾 Cleaning up persistent storage..."
rm -rf /root/containers/postgresql-data-k8s
rm -rf /root/containers/gitea-data-k8s
rm -rf /root/containers/memos-data-k8s
rm -rf /root/containers/filestash-data-k8s
rm -rf /root/containers/filestash-config-k8s
rm -rf /root/containers/uptime-kuma-data-k8s

# Step 3: Recreate fresh directories with proper ownership
echo "📁 Creating fresh storage directories..."
mkdir -p /root/containers/postgresql-data-k8s
mkdir -p /root/containers/gitea-data-k8s
mkdir -p /root/containers/memos-data-k8s
mkdir -p /root/containers/filestash-data-k8s
mkdir -p /root/containers/filestash-config-k8s
mkdir -p /root/containers/uptime-kuma-data-k8s

# Set proper ownership for containers
chown -R 1000:1000 /root/containers/postgresql-data-k8s
chown -R 1000:1000 /root/containers/gitea-data-k8s
chown -R 1000:1000 /root/containers/memos-data-k8s
chown -R 1000:1000 /root/containers/filestash-data-k8s
chown -R 1000:1000 /root/containers/filestash-config-k8s
chown -R 1000:1000 /root/containers/uptime-kuma-data-k8s

# Step 4: Verify cleanup
echo ""
echo "✅ Cleanup complete! Verification:"
echo ""
echo "Kubernetes resources:"
kubectl get namespace base-infrastructure 2>/dev/null || echo "✓ Namespace deleted"
kubectl get pv 2>/dev/null || echo "✓ No PersistentVolumes found"
echo ""
echo "Storage directories:"
ls -la /root/containers/ | grep k8s

echo ""
echo "🎉 Infrastructure completely cleaned!"
echo "📦 Ready for fresh deployment with: ./deploy.sh"