#!/bin/bash

# Kubernetes Infrastructure Cleanup Script
# Completely removes all infrastructure and persistent data for fresh deployment

set -e

echo "🧹 Starting infrastructure cleanup..."
echo ""

# Parse arguments for non-interactive behavior
REMOVE_DATA=""     # empty = ask user, true/false = use flag value
REMOVE_INGRESS=""  # empty = ask user, true/false = use flag value
AUTO_CONFIRM=false

for arg in "$@"; do
    case $arg in
        --data|-d)
            REMOVE_DATA=true
            ;;
        --no-data)
            REMOVE_DATA=false
            ;;
        --ingress|-i)
            REMOVE_INGRESS=true
            ;;
        --no-ingress)
            REMOVE_INGRESS=false
            ;;
        --all|-a)
            AUTO_CONFIRM=true
            ;;
    esac
done

echo "ℹ️  This will remove:"
echo "   - All Kubernetes resources in base-infra namespace"
echo ""

if [[ "$AUTO_CONFIRM" == true ]]; then
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

# Ask about ingress removal (unless specified via flag)
if [[ "$REMOVE_INGRESS" == "" ]]; then
    echo ""
    read -p "Also remove ingress controller and SSL certificates? (y/N): " -n 1 -r INGRESS_REPLY
    echo
    if [[ $INGRESS_REPLY =~ ^[Yy]$ ]]; then
        REMOVE_INGRESS=true
        echo "⚠️  Will also remove ingress and SSL certificates"
    else
        REMOVE_INGRESS=false
        echo "✅ Ingress and SSL certificates will be preserved"
    fi
elif [[ "$REMOVE_INGRESS" == true ]]; then
    echo "⚠️  Will also remove ingress and SSL certificates (--ingress flag provided)"
else
    echo "✅ Ingress and SSL certificates will be preserved (--no-ingress flag provided)"
fi

# Ask about data removal (unless specified via flag)
if [[ "$REMOVE_DATA" == "" ]]; then
    echo ""
    read -p "Also remove PersistentVolumes and application data? (y/N): " -n 1 -r DATA_REPLY
    echo
    if [[ $DATA_REPLY =~ ^[Yy]$ ]]; then
        REMOVE_DATA=true
        echo "⚠️  Will also remove all data"
    else
        REMOVE_DATA=false
        echo "✅ Data will be preserved"
    fi
elif [[ "$REMOVE_DATA" == true ]]; then
    echo "⚠️  Will also remove all data (--data flag provided)"
else
    echo "✅ Data will be preserved (--no-data flag provided)"
fi

# Step 1: Delete all Kubernetes resources
echo "🗑️  Deleting Kubernetes resources..."
kubectl delete namespace base-infra --ignore-not-found=true

if [[ "$REMOVE_DATA" == true ]]; then
    echo "🗑️  Deleting PersistentVolumes..."
    kubectl delete pv --all --ignore-not-found=true
else
    echo "✅ Preserving PersistentVolumes"
fi

# Clean up ingress resources conditionally
if [[ "$REMOVE_INGRESS" == true ]]; then
    echo "🔐 Cleaning up SSL certificates and cert-manager..."
    kubectl delete clusterissuer letsencrypt-prod --ignore-not-found=true || true
    kubectl delete namespace cert-manager --ignore-not-found=true || true

    echo "🔀 Cleaning up ingress controller..."
    kubectl delete namespace ingress-nginx --ignore-not-found=true || true

    echo "🔧 Cleaning up admission webhooks..."
    kubectl delete validatingwebhookconfigurations ingress-nginx-admission --ignore-not-found=true || true
    kubectl delete mutatingwebhookconfigurations ingress-nginx-admission --ignore-not-found=true || true

    echo "🔧 Removing iptables bypass rules..."
    iptables -D INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "DOCKER-STYLE-HTTP-BYPASS" 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "DOCKER-STYLE-HTTPS-BYPASS" 2>/dev/null || true
    echo "✅ iptables bypass rules removed"
else
    echo "✅ Preserving ingress controller and SSL certificates"
fi

# Wait for namespace to be fully deleted
echo "⏳ Waiting for namespace cleanup..."
kubectl wait --for=delete namespace/base-infra --timeout=60s 2>/dev/null || true

# Step 2: Handle persistent storage based on REMOVE_DATA flag
if [[ "$REMOVE_DATA" == true ]]; then
    echo "💾 Cleaning up persistent storage..."
    rm -rf /root/containers/postgresql-k8s-data
    rm -rf /root/containers/gitea-k8s-data
    rm -rf /root/containers/gitea-runner-k8s-data
    rm -rf /root/containers/memos-k8s-data
    rm -rf /root/containers/filestash-k8s
    rm -rf /root/containers/uptime-kuma-k8s-data
    
    echo "📁 Creating fresh storage directories..."
    mkdir -p /root/containers/postgresql-k8s-data
    mkdir -p /root/containers/gitea-k8s-data
    mkdir -p /root/containers/gitea-runner-k8s-data
    mkdir -p /root/containers/memos-k8s-data
    mkdir -p /root/containers/filestash-k8s/data
    mkdir -p /root/containers/filestash-k8s/config
    mkdir -p /root/containers/uptime-kuma-k8s-data
    echo "  ⚠️  All services will reinitialize with fresh data"
    
    # Set proper ownership for containers  
    chown -R 1000:1000 /root/containers/postgresql-k8s-data
    chown -R 1000:1000 /root/containers/gitea-k8s-data
    chown -R 1000:1000 /root/containers/gitea-runner-k8s-data
    chown -R 1000:1000 /root/containers/memos-k8s-data
    chown -R 1000:1000 /root/containers/filestash-k8s
    chown -R 1000:1000 /root/containers/uptime-kuma-k8s-data
else
    echo "✅ Preserving application data in /root/containers/"
fi

# Step 4: Verify cleanup
echo ""
echo "✅ Cleanup complete! Verification:"
echo ""
echo "Kubernetes resources:"
kubectl get namespace base-infra 2>/dev/null || echo "✓ Namespace deleted"
if [[ "$REMOVE_DATA" == true ]]; then
    kubectl get pv 2>/dev/null || echo "✓ PersistentVolumes removed"
    echo ""
    echo "Storage directories:"
    ls -la /root/containers/ | grep k8s
else
    echo "✓ PersistentVolumes preserved"
    echo ""
    echo "Storage directories (preserved):"
    ls -la /root/containers/ | grep k8s || echo "  (No k8s directories found)"
fi

echo ""
echo "🎉 Infrastructure cleanup complete!"
echo "📦 Ready for deployment with: ./deploy.sh"