#!/bin/bash

# Script to remove Docker-style port forwarding rules

set -e

echo "🧹 Removing port forwarding rules..."

# Get current NodePort numbers
HTTP_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "31748")
HTTPS_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || echo "31059")

# Remove DNAT rules
iptables -t nat -D PREROUTING -p tcp --dport 80 -j DNAT --to-destination 127.0.0.1:$HTTP_NODEPORT 2>/dev/null || echo "HTTP DNAT rule not found"
iptables -t nat -D PREROUTING -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:$HTTPS_NODEPORT 2>/dev/null || echo "HTTPS DNAT rule not found"

# Remove FORWARD rules  
iptables -D FORWARD -p tcp --dport $HTTP_NODEPORT -j ACCEPT 2>/dev/null || echo "HTTP FORWARD rule not found"
iptables -D FORWARD -p tcp --dport $HTTPS_NODEPORT -j ACCEPT 2>/dev/null || echo "HTTPS FORWARD rule not found"

echo "✅ Port forwarding rules removed"