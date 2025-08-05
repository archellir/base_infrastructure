# SSH Access Guide

Quick guide for accessing and managing the Kubernetes infrastructure via SSH.

## Server Access

```bash
# Connect to server
ssh root@your-server-ip

# Or with key
ssh -i ~/.ssh/your-key root@your-server-ip
```

## Essential Commands

**Check Infrastructure:**
```bash
# Kubernetes cluster status
kubectl get nodes
kubectl get pods -n base-infrastructure
kubectl get services -n base-infrastructure

# Check service logs
kubectl logs -f deployment/gitea -n base-infrastructure
```

**Port Forwarding for Testing:**
```bash
# Forward services to test locally
kubectl port-forward svc/gitea 4000:3000 -n base-infrastructure &
kubectl port-forward svc/umami 4001:3000 -n base-infrastructure &
kubectl port-forward svc/memos 5230:5230 -n base-infrastructure &

# Stop all port forwards
pkill -f "kubectl port-forward"
```

**SSH Tunneling (from local machine):**
```bash
# Create tunnels to access services locally
ssh -L 4000:localhost:4000 -L 4001:localhost:4001 -L 5230:localhost:5230 root@your-server-ip

# Then access:
# http://localhost:4000 (Gitea)
# http://localhost:4001 (Umami)  
# http://localhost:5230 (Memos)
```

## Quick Troubleshooting

```bash
# Restart a failing service
kubectl rollout restart deployment/service-name -n base-infrastructure

# Check disk space
df -h

# Check system resources  
free -h
top
```

## File Locations

- **Kubernetes configs**: `/root/base_infrastructure/k8s/`
- **Persistent storage**: `/root/containers/`
- **Kubernetes admin config**: `/etc/kubernetes/admin.conf`