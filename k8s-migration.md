# Kubernetes Migration - Learning Environment Setup

This document records the successful setup of a vanilla Kubernetes cluster using kubeadm for learning purposes.

## Overview

Successfully migrated from Docker Compose to a production-grade Kubernetes cluster to gain hands-on experience with container orchestration, networking, and cloud-native technologies.

## Infrastructure Setup

### Environment
- **Host OS**: macOS (Darwin 23.3.0, ARM64)
- **Virtualization**: Multipass VM
- **Guest OS**: Ubuntu 22.04 LTS
- **Resources**: 2 CPU cores, 4GB RAM, 20GB disk

### Architecture Components

```
┌─────────────────────┐
│   Control Plane     │
│ ┌─────────────────┐ │
│ │   API Server    │ │ ← Port 6443
│ │     (kube-      │ │
│ │   apiserver)    │ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │      etcd       │ │ ← Ports 2379-2380
│ │   (database)    │ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │   Scheduler     │ │ ← Port 10259
│ │ (kube-scheduler)│ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │   Controller    │ │ ← Port 10257
│ │    Manager      │ │
│ └─────────────────┘ │
└─────────────────────┘
         │
    ┌────▼────┐
    │ kubelet │ ← Port 10250
    └─────────┘
         │
    ┌────▼────┐
    │Container│
    │ Runtime │
    │(containerd)
    └─────────┘
```

## Installation Process

### 1. Virtual Machine Setup
```bash
# Install multipass
brew install multipass

# Create Ubuntu VM
multipass launch --name k8s-master --cpus 2 --memory 4G --disk 20G 22.04

# Verify VM
multipass list
# Result: k8s-master Running 192.168.64.2 Ubuntu 22.04 LTS
```

### 2. System Preparation
```bash
# Disable swap (required for kubelet)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### 3. Container Runtime (containerd)
```bash
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable SystemdCgroup (required for kubeadm)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Start and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 4. Kubernetes Components
```bash
# Add Kubernetes repository
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

### 5. Cluster Initialization
```bash
# Initialize cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubectl for regular user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Allow pod scheduling on control-plane (single-node setup)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**Initialization Output:**
```
Your Kubernetes control-plane has initialized successfully!

kubeadm join 192.168.64.2:6443 --token 4zboev.zy5k6cx1ou7wfkpt \
    --discovery-token-ca-cert-hash sha256:083b030d085e38de555c9cc5f4c4c63955a7f4b7a3a8e2b72aa2487cf7d47b9a
```

### 6. Network Plugin (Calico)
```bash
# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Install Calico custom resources
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O
kubectl create -f custom-resources.yaml
```

### 7. Ingress Controller (Nginx)
```bash
# Install nginx-ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml

# Wait for ingress controller to be ready
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
```

## Final Cluster Status

### Nodes
```bash
kubectl get nodes
```
```
NAME         STATUS   ROLES           AGE   VERSION
k8s-master   Ready    control-plane   55m   v1.29.15
```

### System Pods
```bash
kubectl get pods --all-namespaces
```
```
NAMESPACE          NAME                                       READY   STATUS    RESTARTS   AGE
calico-apiserver   calico-apiserver-b98cc8657-j9zmr           1/1     Running   0          7m
calico-apiserver   calico-apiserver-b98cc8657-mlhdj           1/1     Running   0          7m
calico-system      calico-kube-controllers-5444d4b9d8-25tw6   1/1     Running   0          9m
calico-system      calico-node-w9lmd                          1/1     Running   0          9m
calico-system      calico-typha-7b45d75798-r49tn              1/1     Running   0          9m
calico-system      csi-node-driver-tpzq5                      2/2     Running   0          9m
ingress-nginx      ingress-nginx-controller-845698f4f6-mff49   1/1     Running   0          1m
kube-system        coredns-76f75df574-cct2s                   1/1     Running   0          55m
kube-system        coredns-76f75df574-krvfq                   1/1     Running   0          55m
kube-system        etcd-k8s-master                            1/1     Running   0          55m
kube-system        kube-apiserver-k8s-master                  1/1     Running   0          55m
kube-system        kube-controller-manager-k8s-master         1/1     Running   0          55m
kube-system        kube-proxy-bgh4r                           1/1     Running   0          55m
kube-system        kube-scheduler-k8s-master                  1/1     Running   0          55m
tigera-operator    tigera-operator-94d7f7696-2w7hj            1/1     Running   0          10m
```

## Functionality Verification

### Test Deployment
```bash
# Create test nginx deployment
kubectl create deployment nginx-test --image=nginx
kubectl expose deployment nginx-test --port=80 --type=NodePort

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=nginx-test --timeout=60s

# Test service (NodePort assigned: 31675)
curl -s localhost:31675 | head -n 5
```

**Result:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
```

✅ **Test successful - cluster fully operational**

## Key Learning Outcomes

### Technical Skills Gained
1. **kubeadm Installation**: Understanding vanilla Kubernetes setup process
2. **Container Runtime**: containerd configuration and SystemdCgroup setup
3. **Networking**: Calico CNI implementation and pod network CIDR configuration
4. **Ingress**: Nginx ingress controller for HTTP/HTTPS routing
5. **kubectl**: Basic cluster management and troubleshooting commands

### Architecture Understanding
1. **Control Plane Components**: API Server, etcd, Scheduler, Controller Manager roles
2. **Node Components**: kubelet, kube-proxy, container runtime interaction
3. **Add-ons**: CoreDNS, CNI plugins, ingress controllers as cluster extensions
4. **Pod Networking**: How Calico provides pod-to-pod communication across nodes

### Troubleshooting Experience
1. **Node NotReady**: Resolved by installing CNI plugin (expected behavior)
2. **CoreDNS Pending**: Resolved after Calico installation (expected behavior)
3. **SystemdCgroup**: Required configuration for kubelet compatibility
4. **Single-node Taint**: Removed control-plane taint for pod scheduling

## Next Steps

### Infrastructure Services Migration
Now ready to convert Docker Compose services to Kubernetes manifests:

1. **PostgreSQL**: StatefulSet with persistent volumes
2. **Gitea**: Deployment with ingress and persistent storage
3. **Umami**: Deployment with database connection
4. **Memos**: Deployment with volume mounts
5. **FileBrowser**: Deployment with persistent volumes
6. **Uptime Kuma**: Deployment with monitoring configuration
7. **pgAdmin**: Deployment with database access
8. **Dozzle**: DaemonSet for container log access

### Learning Path
1. **Resource Management**: Deployments, Services, ConfigMaps, Secrets
2. **Storage**: PersistentVolumes, PersistentVolumeClaims, StorageClasses
3. **Networking**: Ingress rules, NetworkPolicies, Service types
4. **Security**: RBAC, Pod Security Standards, Network Policies
5. **Monitoring**: Metrics, logging, health checks

## Cluster Access

### VM Management
```bash
# Access VM
multipass shell k8s-master

# VM operations
multipass stop k8s-master
multipass start k8s-master
multipass delete k8s-master
```

### Cluster Information
```bash
# Cluster details
kubectl cluster-info
kubectl get componentstatuses
kubectl get nodes -o wide

# Namespace overview
kubectl get namespaces
kubectl get all --all-namespaces
```

## Success Metrics

✅ **Complete vanilla Kubernetes setup using kubeadm**  
✅ **Production-grade components**: containerd, Calico, Nginx ingress  
✅ **Single-node cluster ready for application workloads**  
✅ **Network policies support** via Calico CNI  
✅ **HTTP/HTTPS ingress** routing capability  
✅ **Verified functionality** with successful test deployment  

**Total setup time**: ~1 hour  
**Learning value**: Maximum (deep understanding of K8s components)  
**Production relevance**: High (skills transferable to managed K8s services)  

---

*Migration completed successfully on August 1, 2025*