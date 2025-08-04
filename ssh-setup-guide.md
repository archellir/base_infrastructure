# SSH Migration Setup Guide

This guide covers setting up the migration process when connecting to your server via SSH.

## Architecture Overview

Based on your k8s-migration.md, you have:
- **Host Server**: macOS with Docker Compose services
- **K8s Cluster**: Running in Multipass VM (Ubuntu 22.04)
- **Access Method**: SSH connection to host server

## Setup Options

### Option 1: Run Migration from SSH Session (Recommended)

This approach runs the migration script directly on your server via SSH.

#### Prerequisites on Server:
```bash
# 1. Install kubectl (if not already installed)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# 2. Configure kubectl to access your K8s cluster
# Copy kubeconfig from Multipass VM
multipass exec k8s-master -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/config

# 3. Update kubeconfig server IP to VM IP (find VM IP first)
VM_IP=$(multipass info k8s-master | grep IPv4 | awk '{print $2}')
sed -i "s/127.0.0.1:6443/$VM_IP:6443/g" ~/.kube/config

# 4. Test kubectl access
kubectl cluster-info
kubectl get nodes
```

#### SSH Connection Setup:
```bash
# From your local machine, connect with port forwarding for testing
ssh -L 6443:localhost:6443 -L 3000:localhost:3000 -L 3001:localhost:3001 user@your-server

# Or without port forwarding for basic access
ssh user@your-server
```

### Option 2: Run Migration Inside Multipass VM

Run the migration directly inside the K8s VM where kubectl is already configured.

```bash
# SSH to your server first
ssh user@your-server

# Enter the Multipass VM
multipass shell k8s-master

# Inside VM: Clone/copy your infrastructure repo
git clone <your-repo> /home/ubuntu/base_infrastructure
# OR copy files from host:
# multipass transfer /path/to/base_infrastructure k8s-master:/home/ubuntu/

# Inside VM: Run migration
cd /home/ubuntu/base_infrastructure
chmod +x migration-commands.sh
./migration-commands.sh help
```

## Key Considerations for SSH Migration

### 1. Volume Access
The Docker volumes are on your **host server** at `/root/containers/`, but kubectl accesses the **Multipass VM**. The migration script handles this by:

- Creating backups on the host server (where Docker volumes exist)
- Copying backups to K8s pods (which run in the VM)
- Extracting data inside the pods

### 2. Network Access
- **Docker Compose services**: Run on host server
- **Kubernetes services**: Run in Multipass VM  
- **Port forwarding**: May be needed for testing services

### 3. File Transfer
When running from SSH, files need to move:
```
Host Server (/root/containers/) → Backup Files → K8s Pods (in VM)
```

## Pre-Migration SSH Checklist

Run these commands to verify your SSH setup:

```bash
# 1. SSH to your server
ssh user@your-server

# 2. Check if you're in SSH session
echo "SSH_CLIENT: $SSH_CLIENT"
echo "SSH_TTY: $SSH_TTY"

# 3. Check Multipass VM status
multipass list

# 4. Check kubectl access
kubectl cluster-info
kubectl get nodes

# 5. Check Docker access (for backups)
docker ps

# 6. Check base infrastructure directory
ls -la base_infrastructure/
cd base_infrastructure && ls -la k8s/

# 7. Run migration script environment check
./migration-commands.sh help
```

## Modified Migration Workflow for SSH

### Phase 0: Backup (Host Server)
```bash
# This runs on host server where Docker volumes exist
./migration-commands.sh phase0
```

### Phase 1-6: K8s Operations (Multipass VM via kubectl)
```bash
# These run via kubectl commands that connect to Multipass VM
./migration-commands.sh phase1  # Setup K8s infrastructure
./migration-commands.sh phase2  # Deploy PostgreSQL in VM
./migration-commands.sh phase3  # Copy backup files to VM pods
./migration-commands.sh phase4  # Deploy services in VM
./migration-commands.sh phase5  # Setup ingress in VM
./migration-commands.sh phase6  # Verify services in VM
```

### Phase 7: Cleanup (Host Server)
```bash
# This stops Docker Compose services on host server
./migration-commands.sh phase7
```

## Testing Access via SSH

### Port Forward for Testing
```bash
# From your SSH session, forward ports for testing
kubectl port-forward -n base-infrastructure svc/gitea 3000:3000 &
kubectl port-forward -n base-infrastructure svc/umami 3001:3000 &

# Then from another SSH terminal or with SSH tunnel:
curl http://localhost:3000  # Test Gitea
curl http://localhost:3001  # Test Umami
```

### SSH Tunnel for Browser Access
```bash
# From your local machine, create SSH tunnel
ssh -L 3000:VM_IP:30000 -L 3001:VM_IP:30001 user@your-server

# Where VM_IP is your Multipass VM IP
# And 30000, 30001 are NodePort services (if configured)
```

## Troubleshooting SSH Issues

### kubectl Connection Issues
```bash
# Check if kubectl can reach K8s API server
kubectl cluster-info

# If connection fails, verify:
# 1. Multipass VM is running
multipass list

# 2. VM IP is correct in kubeconfig
grep server ~/.kube/config

# 3. Port 6443 is accessible
telnet <VM_IP> 6443
```

### Docker Volume Access Issues
```bash
# Check if Docker volumes exist and are accessible
sudo ls -la /root/containers/
sudo ls -la /root/containers/postgresql/data/

# Check Docker daemon is running
docker ps
```

### File Transfer Issues
```bash
# Check if kubectl cp works
kubectl get pods -n base-infrastructure
kubectl cp --help

# Test file transfer to pod
echo "test" > /tmp/test.txt
kubectl cp /tmp/test.txt base-infrastructure/postgresql-0:/tmp/
kubectl exec -n base-infrastructure postgresql-0 -- ls -la /tmp/
```

## Migration Success Verification over SSH

After migration completes, verify everything works:

```bash
# 1. All K8s pods running
kubectl get pods -n base-infrastructure

# 2. Services accessible via port-forward
kubectl port-forward -n base-infrastructure svc/gitea 3000:3000 &
curl http://localhost:3000

# 3. Database connectivity
kubectl exec -n base-infrastructure postgresql-0 -- psql -U postgres -c '\l'

# 4. Ingress working (if external IP configured)
kubectl get ingress -n base-infrastructure
```

## Summary

The migration **will work over SSH** with the updated script. The key points:

✅ **Script detects SSH environment** and provides appropriate guidance  
✅ **Backup phase** works on host server where Docker volumes exist  
✅ **K8s operations** work via kubectl connecting to Multipass VM  
✅ **Data transfer** handled via kubectl cp to move backups into pods  
✅ **Testing** possible via port-forward and SSH tunnels  

Choose **Option 1** (SSH to host server) for the easiest setup, or **Option 2** (inside Multipass VM) if you prefer direct access to the K8s cluster.