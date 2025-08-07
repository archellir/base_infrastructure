#!/bin/bash

# Port forwarding script that replicates Docker's networking approach
# Uses DNAT + FORWARD rules to bypass firewall restrictions

set -e

echo "🔀 Setting up Docker-style port forwarding for Kubernetes..."

# Get NodePort numbers dynamically
HTTP_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo "📋 Detected NodePorts: HTTP=$HTTP_NODEPORT, HTTPS=$HTTPS_NODEPORT"

# Get node IP for DNAT rules
NODE_IP=$(hostname -I | awk '{print $1}')

# Check if rules already exist to avoid duplicates
if ! iptables -t nat -C PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NODE_IP:$HTTP_NODEPORT 2>/dev/null; then
    echo "🔀 Adding DNAT rule: 80 → $NODE_IP:$HTTP_NODEPORT"
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $NODE_IP:$HTTP_NODEPORT
fi

if ! iptables -t nat -C PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NODE_IP:$HTTPS_NODEPORT 2>/dev/null; then
    echo "🔀 Adding DNAT rule: 443 → $NODE_IP:$HTTPS_NODEPORT"
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $NODE_IP:$HTTPS_NODEPORT
fi

# Add OUTPUT chain rules for localhost traffic
if ! iptables -t nat -C OUTPUT -p tcp --dport 80 -j DNAT --to-destination $NODE_IP:$HTTP_NODEPORT 2>/dev/null; then
    echo "🔀 Adding OUTPUT DNAT rule: localhost:80 → $NODE_IP:$HTTP_NODEPORT"
    iptables -t nat -A OUTPUT -p tcp --dport 80 -j DNAT --to-destination $NODE_IP:$HTTP_NODEPORT
fi

if ! iptables -t nat -C OUTPUT -p tcp --dport 443 -j DNAT --to-destination $NODE_IP:$HTTPS_NODEPORT 2>/dev/null; then
    echo "🔀 Adding OUTPUT DNAT rule: localhost:443 → $NODE_IP:$HTTPS_NODEPORT"
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination $NODE_IP:$HTTPS_NODEPORT
fi

if ! iptables -C FORWARD -p tcp --dport $HTTP_NODEPORT -j ACCEPT 2>/dev/null; then
    echo "✅ Adding FORWARD rule for port $HTTP_NODEPORT"
    iptables -A FORWARD -p tcp --dport $HTTP_NODEPORT -j ACCEPT
fi

if ! iptables -C FORWARD -p tcp --dport $HTTPS_NODEPORT -j ACCEPT 2>/dev/null; then
    echo "✅ Adding FORWARD rule for port $HTTPS_NODEPORT"
    iptables -A FORWARD -p tcp --dport $HTTPS_NODEPORT -j ACCEPT
fi

echo ""
echo "✅ Port forwarding setup complete!"
echo "🔀 External port 80 → NodePort $HTTP_NODEPORT (HTTP)"
echo "🔀 External port 443 → NodePort $HTTPS_NODEPORT (HTTPS)"
echo ""
echo "Test with: curl http://git.arcbjorn.com"