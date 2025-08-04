# Kubernetes Setup Documentation

## Infrastructure Overview

- **Server**: Ubuntu Linux (Intel 4-CPU, 16GB RAM) 
- **Kubernetes**: v1.29.15 (single-node cluster via kubeadm)
- **Container Runtime**: containerd
- **Network Plugin**: Calico CNI  
- **Ingress**: nginx-ingress

## Installation Commands

### 1. System Preparation
```bash
# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### 2. Install containerd
```bash
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
```

### 3. Install Kubernetes
```bash
# Add repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install components
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

### 4. Initialize Cluster
```bash
# Initialize cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Configure kubectl
export KUBECONFIG=/etc/kubernetes/admin.conf
echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> ~/.bashrc

# Allow pod scheduling on control plane
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### 5. Install Network Plugin (Calico)
```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O
kubectl create -f custom-resources.yaml
```

### 6. Install Ingress Controller
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
```

## Verification Commands

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods --all-namespaces

# Check services
kubectl get svc --all-namespaces
```

---
*Setup completed on August 4, 2025*