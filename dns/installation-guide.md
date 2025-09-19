# DNS Fix Installation Guide

## Target System Locations

### 1. Netplan Configuration
**File:** `/etc/netplan/99-dns-fix.yaml`
**Purpose:** Override cloud-init DNS settings with single IPv4 DNS server
**Permissions:** `600` (root only)

```bash
sudo cp 99-dns-fix.yaml /etc/netplan/
sudo chmod 600 /etc/netplan/99-dns-fix.yaml
sudo netplan apply
```

### 2. SystemD Resolved Configuration
**File:** `/etc/systemd/resolved.conf.d/dns-fix.conf`
**Purpose:** Force systemd-resolved to use only one DNS server
**Permissions:** `644`

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d/
sudo cp dns-fix.conf /etc/systemd/resolved.conf.d/
sudo systemctl restart systemd-resolved
```

### 3. Cloud-Init Disable
**File:** `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`
**Purpose:** Prevent cloud-init from overriding network configuration
**Permissions:** `644`

```bash
sudo cp 99-disable-network-config.cfg /etc/cloud/cloud.cfg.d/
```

### 4. Tailscale DNS Disable
**Commands:** See `tailscale-commands.txt`
**Purpose:** Disable Tailscale DNS management to eliminate reverse DNS zones

```bash
sudo tailscale set --accept-dns=false
```

### 5. Kubernetes Component Restart
**Purpose:** Apply DNS changes to existing pods

```bash
sudo systemctl restart kubelet
kubectl rollout restart daemonset/calico-node -n calico-system
kubectl rollout restart deployment/calico-typha -n calico-system
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout restart daemonset/node-exporter -n monitoring
```

## Verification Steps

1. Check DNS server count:
```bash
resolvectl status | grep -A 5 "Global"
cat /run/systemd/resolve/resolv.conf
```

2. Check for DNS warnings:
```bash
kubectl get events -A --field-selector reason=DNSConfigForming --no-headers | wc -l
```

3. Test DNS resolution:
```bash
nslookup google.com
kubectl exec deployment/gitea -n base-infra -- nslookup postgresql
```

4. Run health check:
```bash
./scripts/healthcheck.sh
```

## Expected Results
- Single DNS server: `185.12.64.1`
- No DNS warnings for new pods
- Functional DNS resolution
- Tailscale connectivity maintained without DNS management