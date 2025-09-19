#!/bin/bash

# Server Health Check Command for Kubernetes Infrastructure
# Performs comprehensive security and health audit

echo "🔍 Starting Infrastructure Health Check..."
echo "=================================================="

# Check system processes for anomalies
echo "📊 Checking system processes..."
echo "Top CPU processes:"
ps aux --sort=-%cpu | head -10 | awk 'NR==1{print $0} NR>1{printf "%-8s %6s %6s %s\n", $1, $3, $4, $11}'

echo -e "\nTop memory processes:"
ps aux --sort=-%mem | head -10 | awk 'NR==1{print $0} NR>1{printf "%-8s %6s %6s %s\n", $1, $3, $4, $11}'

# Check system resources
echo -e "\n💾 System Resources:"
echo "Uptime: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
free -h | grep -E "^Mem:|^Swap:"
df -h / | tail -1 | awk '{printf "Disk: %s used of %s (%s full)\n", $3, $2, $5}'

# Check failed systemd services
echo -e "\n🚨 Failed Services:"
failed_services=$(systemctl --failed --no-legend | wc -l)
if [ "$failed_services" -eq 0 ]; then
    echo "✅ No failed services"
else
    echo "⚠️  $failed_services failed services found:"
    systemctl --failed --no-legend
fi

# Check Kubernetes cluster health
echo -e "\n☸️  Kubernetes Cluster Status:"
kubectl get nodes --no-headers | awk '{printf "Node: %s - %s\n", $1, $2}'

# Check for pods in error states
echo -e "\nPod Health:"
error_pods=$(kubectl get pods -A | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff|Pending|Failed)" | wc -l)
if [ "$error_pods" -eq 0 ]; then
    echo "✅ All pods running normally"
else
    echo "⚠️  $error_pods pods in error states:"
    kubectl get pods -A | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff|Pending|Failed)"
fi

# Check pod restart counts (adjusted thresholds for K8s environment)
echo -e "\nExcessive restart counts:"
# Use higher threshold (>20) and exclude known network components that restart during updates
excessive_restarts=$(kubectl get pods -A --no-headers | awk '$5 > 20 && $2 !~ /calico|coredns|kube-proxy/ {print}' | wc -l)
if [ "$excessive_restarts" -eq 0 ]; then
    echo "✅ No pods with excessive restarts"
else
    echo "⚠️  Pods with excessive restart counts:"
    kubectl get pods -A --no-headers | awk '$5 > 20 && $2 !~ /calico|coredns|kube-proxy/ {printf "%-15s %-30s %s restarts\n", $1, $2, $5}'
fi

# Show restart summary for info (not flagged as issue)
echo -e "\nRestart summary (informational):"
kubectl get pods -A --no-headers | awk '$5 > 5 {printf "%-15s %-30s %s restarts\n", $1, $2, $5}' | head -5

# Check recent Kubernetes events for warnings/errors (filter out common non-issues)
echo -e "\n📋 Recent K8s Events (warnings/errors):"
# Exclude DNSConfigForming warnings which are common and non-critical
recent_issues=$(kubectl get events -A --field-selector type!=Normal --no-headers 2>/dev/null | grep -v "DNSConfigForming" | wc -l)
if [ "$recent_issues" -eq 0 ]; then
    echo "✅ No critical warnings or errors"
else
    echo "⚠️  Critical issues found:"
    kubectl get events -A --field-selector type!=Normal --no-headers 2>/dev/null | grep -v "DNSConfigForming" | tail -5
fi

# Show DNS warnings separately as informational
dns_warnings=$(kubectl get events -A --field-selector type!=Normal --no-headers 2>/dev/null | grep "DNSConfigForming" | wc -l)
if [ "$dns_warnings" -gt 0 ]; then
    echo -e "\nDNS configuration warnings (informational): $dns_warnings"
fi

# Check network security
echo -e "\n🔒 Security Status:"
echo "Active SSH sessions:"
who | wc -l | awk '{print $1 " active sessions"}'

echo -e "\nRecent logins (last 5):"
last -5 | head -5

# Check listening ports for unexpected services
echo -e "\n🌐 Network Ports:"
echo "External listening ports:"
ss -tulnp | grep -E ":80 |:443 |:22 |:6443 " | awk '{print $1, $5}' | sort -u

# Check for suspicious processes (improved detection, exclude K8s components)
echo -e "\n🔍 Process Analysis:"
# Look for actual suspicious network tools, exclude containerd-shim and K8s components
suspicious_procs=$(ps aux | grep -E "\b(nc|netcat|ncat|socat)\b" | grep -v -E "(containerd|kube-|calico|grep)" | wc -l)
if [ "$suspicious_procs" -eq 0 ]; then
    echo "✅ No suspicious network processes detected"
else
    echo "⚠️  Suspicious processes found:"
    ps aux | grep -E "\b(nc|netcat|ncat|socat)\b" | grep -v -E "(containerd|kube-|calico|grep)"
fi

# Check for unusual network connections (exclude known K8s and service ports)
echo -e "\nUnusual network connections:"
unusual_conns=$(ss -tulnp | grep -v -E ":(22|53|80|443|2379|2380|6443|8080|8181|9090|9100|10250|10254|10256)\b" | grep -v "127.0.0.1" | grep LISTEN | wc -l)
if [ "$unusual_conns" -eq 0 ]; then
    echo "✅ No unusual listening ports detected"
else
    echo "⚠️  Unusual ports listening:"
    ss -tulnp | grep -v -E ":(22|53|80|443|2379|2380|6443|8080|8181|9090|9100|10250|10254|10256)\b" | grep -v "127.0.0.1" | grep LISTEN | head -5
fi

# Summary
echo -e "\n🎯 Health Check Summary:"
echo "=================================================="
total_issues=$((failed_services + error_pods + excessive_restarts + recent_issues + suspicious_procs + unusual_conns))

if [ "$total_issues" -eq 0 ]; then
    echo "✅ SYSTEM HEALTHY - No anomalies detected"
    echo "   • All services running normally"
    echo "   • No failed pods or excessive restarts"
    echo "   • No unusual network connections"
    echo "   • No recent K8s warnings/errors"
    echo "   • No suspicious processes"
else
    echo "⚠️  ISSUES DETECTED - Review items marked above"
    echo "   • Failed services: $failed_services"
    echo "   • Error pods: $error_pods"
    echo "   • Excessive restart pods: $excessive_restarts"
    echo "   • Recent K8s issues: $recent_issues"
    echo "   • Suspicious processes: $suspicious_procs"
    echo "   • Unusual network connections: $unusual_conns"
fi

echo -e "\n🕐 Check completed at $(date)"