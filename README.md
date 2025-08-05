# Base Infrastructure

Self-hosted services infrastructure deployed on Kubernetes with persistent storage and ingress routing.

## Services

- **PostgreSQL** - Shared database with multiple database support
- **Gitea** - Git hosting service (git.arcbjorn.com)
- **Umami** - Analytics platform (analytics.arcbjorn.com)
- **Memos** - Note-taking application (memos.arcbjorn.com)
- **Filestash** - File management interface (server.arcbjorn.com)
- **Uptime Kuma** - Uptime monitoring (uptime.arcbjorn.com)

## Architecture

### Request Flow
```
Internet → Ingress → Services → Pods → Containers
```

### Control Plane
```
┌─────────────────────────────────────────────────────────────────────────┐
│                       Kubernetes Control Plane                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │ kube-api    │  │    etcd     │  │ kube-sched  │  │ controller  │     │
│  │ server      │  │ (cluster    │  │ uler        │  │ manager     │     │
│  │ :6443       │  │ state DB)   │  │ :10259      │  │ :10257      │     │
│  │ REST API    │  │ key-value   │  │ pod assign  │  │ reconcile   │     │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Worker Node
```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Worker Node                                   │
│                                                                         │
│ Management Tools:                                                       │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                        │
│ │   kubectl   │ │   kubeadm   │ │ containerd  │                        │
│ │ CLI client  │ │ bootstrap   │ │ runtime     │                        │
│ └─────────────┘ └─────────────┘ └─────────────┘                        │
│                                                                         │
│ Node Components:                                                        │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐                        │
│ │   kubelet   │ │ kube-proxy  │ │   CoreDNS   │                        │
│ │ :10250      │ │ networking  │ │ DNS: 53     │                        │
│ │ node agent  │ │ load bal.   │ │ discovery   │                        │
│ └─────────────┘ └─────────────┘ └─────────────┘                        │
│                                                                         │
│ Network Layer:                                                          │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────────────────────────┐    │
│ │ Calico CNI  │ │ Tigera      │ │     Ingress Controller          │    │
│ │ Pod Network │ │ Operator    │ │     (nginx-ingress)             │    │
│ │192.168.0.0/ │ │ CNI mgmt    │ │     NodePort :31748/:31059      │    │
│ │16 pod CIDR  │ │             │ │     external routing            │    │
│ └─────────────┘ └─────────────┘ └─────────────────────────────────┘    │
│                                                                         │
│ Application Layer:                       Storage Layer:                 │
│ ┌─────────────────────────────────┐     ┌─────────────────────────────┐ │
│ │        Services & Pods          │     │      Persistent Storage     │ │
│ │                                 │     │                             │ │
│ │ • postgresql (StatefulSet)      │────►│ • postgresql-data (20Gi)    │ │
│ │   shared database               │     │   database files            │ │
│ │ • gitea (Deployment)            │────►│ • gitea-data (512Mi)        │ │
│ │   git hosting                   │     │   git repositories          │ │
│ │ • umami (Deployment)            │────►│ • memos-data (512Mi)        │ │
│ │   web analytics                 │     │   notes & content           │ │
│ │ • memos (Deployment)            │────►│ • filestash-data (512Mi)    │ │
│ │   note-taking                   │     │   file storage              │ │
│ │ • filestash (Deployment)        │────►│ • filestash-config (512Mi)  │ │
│ │   file management               │     │   app configuration         │ │
│ │ • uptime-kuma (Deployment)      │────►│ • uptime-kuma-data (512Mi)  │ │
│ │   uptime monitoring             │     │   monitoring data           │ │
│ │ • static-sites (Deployments)    │────►│ • hostPath volumes          │ │
│ │   static websites               │     │   /root/containers/         │ │
│ └─────────────────────────────────┘     └─────────────────────────────┘ │
│                                                                         │
│ Configuration:                                                          │
│ ┌─────────────────────────────────────────────────────────────────────┐ │
│ │ • Secrets: app-secrets (DB creds, API keys)                        │ │
│ │ • ConfigMaps: postgres init, nginx config                          │ │
│ │ • Namespace: base-infrastructure (isolation)                       │ │
│ │ • StorageClass: local-storage (hostPath)                           │ │
│ └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### Request Flow Details
```
External Access:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Internet  │───▶│   Ingress   │───▶│  Kubernetes │───▶│ Application │
│   Client    │    │ Controller  │    │   Service   │    │    Pod      │
│ (Browser)   │    │(nginx:31748)│    │ (ClusterIP) │    │ (Container) │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
HTTPS Request  ──▶ Route by Host  ──▶ Load Balance  ──▶ Process Request
git.arcbjorn.com   nginx-ingress      gitea-service     gitea-pod

Internal Communication:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Application │───▶│ Service DNS │───▶│ PostgreSQL  │───▶│ Persistent  │
│    Pod      │    │ Resolution  │    │   Service   │    │  Volume     │
│  (umami)    │    │ (CoreDNS)   │    │(StatefulSet)│    │ (Storage)   │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
DB Connection  ──▶ Resolve Name  ──▶ Connect DB    ──▶ Persist Data
postgresql:5432    ClusterIP          postgresql-0      /root/containers/

Management:
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   kubectl   │───▶│ kube-api    │───▶│   kubelet   │───▶│ containerd  │
│  (Admin)    │    │   server    │    │ (Node Agent)│    │  (Runtime)  │
│   Command   │    │   :6443     │    │   :10250    │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
API Request    ──▶ Validate &     ──▶ Execute on    ──▶ Manage
kubectl apply      Store in etcd      Worker Node       Containers
```

## Current Setup

### Docker Compose (Legacy)
Individual service directories with `docker-compose.yml` files:
```bash
# Start core services
cd caddy && docker-compose up -d
cd postgresql && docker-compose up -d

# Start application services
cd gitea && docker-compose up -d
cd umami && docker-compose up -d
# ... repeat for other services
```

### Kubernetes (Current)
- **Cluster**: Single-node Kubernetes v1.29.15 on Ubuntu Linux
- **Control Plane**: API Server, etcd, Scheduler, Controller Manager
- **Node Components**: kubelet, kube-proxy, containerd
- **Network**: Calico CNI (192.168.0.0/16)
- **Ingress**: nginx-ingress controller
- **Storage**: Local PersistentVolumes (512Mi per service)
- **Database**: PostgreSQL StatefulSet with shared databases

## Quick Commands

### Kubernetes Management

**Deployment Scripts:**
```bash
# Make scripts executable
chmod +x deploy.sh cleanup.sh

# Deploy infrastructure (recommended)
./deploy.sh

# Complete cleanup and fresh deployment
./cleanup.sh
./deploy.sh
```

**Manual Commands:**
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n base-infrastructure
kubectl get services -n base-infrastructure

# View logs
kubectl logs -f deployment/gitea -n base-infrastructure
kubectl logs -f deployment/umami -n base-infrastructure

# Apply configurations
kubectl apply -f k8s/ --recursive

# Or apply each directory individually if needed
kubectl apply -f k8s/namespace/
kubectl apply -f k8s/storage/
kubectl apply -f k8s/postgresql/
kubectl apply -f k8s/gitea/
kubectl apply -f k8s/umami/
kubectl apply -f k8s/memos/
kubectl apply -f k8s/filestash/
kubectl apply -f k8s/uptime-kuma/
kubectl apply -f k8s/static-sites/
kubectl apply -f k8s/ingress/
```

### Testing Services via Port Forwarding

After deploying services to Kubernetes, you can test them locally using port forwarding and SSH tunneling.

#### On the Server

Start Kubernetes port forwards (avoid ports 3000/3001 if Docker is still running):
```bash
kubectl port-forward svc/gitea 4000:3000 -n base-infrastructure &
kubectl port-forward svc/umami 4001:3000 -n base-infrastructure &
kubectl port-forward svc/memos 5230:5230 -n base-infrastructure &
kubectl port-forward svc/filestash 8080:8080 -n base-infrastructure &
kubectl port-forward svc/uptime-kuma 4002:3001 -n base-infrastructure &
```

#### From Your Local Machine

Create SSH tunnel to forward ports:
```bash
# Single command with multiple ports
ssh -L 4000:localhost:4000 -L 4001:localhost:4001 -L 5230:localhost:5230 -L 8080:localhost:8080 -L 4002:localhost:4002 root@your-server-ip
```

#### Access Services Locally

- **Gitea**: http://localhost:4000
- **Umami**: http://localhost:4001  
- **Memos**: http://localhost:5230
- **Filestash**: http://localhost:8080
- **Uptime Kuma**: http://localhost:4002

#### Cleanup After Testing

Stop port forwards on server:
```bash
pkill -f "kubectl port-forward"
```

Exit SSH tunnel: `Ctrl+C` or `exit` in terminal

### Database Operations
```bash
# Backup all databases
docker exec -t <postgres-container> pg_dumpall -c -U <user> > backup_$(date +%Y%m%d).sql

# Restore databases  
cat backup.sql | docker exec -i <postgres-container> psql -U <user>
```

### Required Permissions
```bash
# pgAdmin directory permissions (Docker Compose only)
sudo chown -R 5050:5050 /root/containers/pgadmin

# PostgreSQL multiple databases script
chmod +x postgresql/create-multiple-postgresql-databases.sh
```

## File Structure
```
├── k8s/                    # Kubernetes manifests
│   ├── postgresql/         # Database StatefulSet
│   ├── gitea/             # Git hosting service  
│   ├── umami/             # Analytics platform
│   ├── memos/             # Note-taking app
│   ├── filestash/         # File management
│   ├── uptime-kuma/       # Uptime monitoring
│   ├── static-sites/      # Static website deployments
│   ├── storage/           # PersistentVolumes
│   ├── ingress/           # Ingress controller rules
│   └── namespace/         # Secrets, ConfigMaps, Namespace
├── caddy/                  # Reverse proxy (Docker legacy)
├── postgresql/             # Database setup (Docker legacy)
└── k8s-setup.md           # Kubernetes installation guide
```

## Service Access

**External Access (via Ingress):**
- Gitea: https://git.arcbjorn.com
- Umami: https://analytics.arcbjorn.com  
- Memos: https://memos.arcbjorn.com
- Filestash: https://server.arcbjorn.com
- Uptime Kuma: https://uptime.arcbjorn.com

**Internal Communication:**
```bash
# Kubernetes service communication
http://service-name.namespace.svc.cluster.local:port
# Example: http://postgresql.base-infrastructure.svc.cluster.local:5432

# Database connections (from within cluster)
postgresql://username:password@postgresql:5432/database_name
```

---

*Infrastructure supporting distributed applications with high availability and scalability*
