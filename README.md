# base_infrastructure

Infrastructure for base server

First step:

1. Start Caddy & Portainer with with `docker_compose.yml` in `/caddy`
2. Start other services using `docker_compose.yml` 1 by 1


#### TO BE DEPRECATED: PORTAINER COOMUNITY EDITION REMOVED FUNCTIONALITY

#### For postgreSQL multiple databases scripts:

```sh
chmod +x scripts/create-multiple-postgresql-databases.sh
```

#### For [pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html#mapped-files-and-directories):

```sh
sudo chown -R 5050:5050 <host_directory>
```

#### Database backup & restore:

Backup:

```sh
docker exec -t <postgres-container-id> pg_dumpall -c -U <user> > dump_`date +%d-%m-%Y"_"%H_%M_%S`.sql
```

Restore:

```sh
cat <dump_name>.sql | docker exec -i <postgres-container-id> psql -U <user>
```

#### Example of connection:

```sh
# host = container_name
postgres://username:password@container_name:port/db_name
```

---

## Kubernetes Setup (Learning Environment)

### Architecture Overview

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

### Setup Instructions

#### For macOS (Development/Learning)

**Prerequisites:**
- Homebrew installed
- 8GB+ RAM recommended
- 20GB+ free disk space

**Step 1: Install Multipass**
```sh
# Install multipass for lightweight Ubuntu VMs
brew install multipass

# Create Ubuntu VM with sufficient resources
multipass launch --name k8s-master --cpus 2 --memory 4G --disk 20G 22.04

# Shell into the VM
multipass shell k8s-master
```

**Step 2: Inside the VM, follow Linux instructions below**

#### For Linux (Local Development)

**System Requirements:**
- Arch Linux / Ubuntu 20.04+ / CentOS 8+ / RHEL 8+
- 2GB+ RAM, 2+ CPU cores
- Swap disabled
- Unique hostname and MAC address

##### Arch Linux Setup

**Step 1: Prepare System**
```sh
# Disable swap (required for kubelet)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set required sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

**Step 2: Install Container Runtime (containerd)**
```sh
# Install containerd
sudo pacman -S containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml

# Enable SystemdCgroup (required for kubeadm)
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Start and enable containerd
sudo systemctl start containerd
sudo systemctl enable containerd
```

**Step 3: Install Kubernetes Components**
```sh
# Install from AUR (using yay or paru)
yay -S kubeadm-bin kubelet-bin kubectl-bin

# Or build manually from AUR
git clone https://aur.archlinux.org/kubeadm-bin.git
cd kubeadm-bin && makepkg -si
cd .. && git clone https://aur.archlinux.org/kubelet-bin.git
cd kubelet-bin && makepkg -si
cd .. && git clone https://aur.archlinux.org/kubectl-bin.git
cd kubectl-bin && makepkg -si

# Enable kubelet
sudo systemctl enable kubelet
```

##### Ubuntu/Debian Setup

**Step 1: Prepare System** (same as Arch)

**Step 2: Install Container Runtime (containerd)**
```sh
# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Configure containerd (same as Arch)
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

**Step 3: Install Kubernetes Components**
```sh
# Add Kubernetes apt repository
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet, kubeadm, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable kubelet
```

#### Common Steps (All Distributions)

**Step 4: Initialize Kubernetes Cluster**
```sh
# Initialize cluster (single-node setup)
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# Set up kubectl for regular user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Allow pods to be scheduled on control-plane node (single-node setup)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

**Step 5: Install Network Plugin (Calico)**
```sh
# Install Calico operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Download and apply custom resource for Calico
curl https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml -O
kubectl create -f custom-resources.yaml
```

**Step 6: Install Ingress Controller (Nginx)**
```sh
# Install nginx-ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
```

**Step 7: Verify Installation**
```sh
# Check all pods are running
kubectl get pods --all-namespaces

# Check nodes are ready
kubectl get nodes

# Verify Calico is working
kubectl get pods -n calico-system
```

### Next Steps

Once Kubernetes is running, you can deploy the infrastructure services using the manifests in the `k8s/` directory:

```sh
# Deploy all services
kubectl apply -f k8s/
```
