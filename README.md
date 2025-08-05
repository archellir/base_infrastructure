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

### Kubernetes Architecture

**Data Flow:**
```
External Request → Ingress Controller → Service → Pod → Container

┌─────────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                      │
│                                                             │
│  Internet → Ingress → Services → Pods → Containers         │
│                                                             │
│  Services:                    Storage:                      │
│  • gitea (git.arcbjorn.com)   • PostgreSQL (StatefulSet)   │
│  • umami (analytics.*)        • PersistentVolumes          │
│  • memos (memos.*)           • Local storage (/root/...)   │
│  • filestash (server.*)                                    │
│  • uptime-kuma (uptime.*)     Database:                    │
│  • static sites              • Shared PostgreSQL          │
│                               • Multiple databases         │
└─────────────────────────────────────────────────────────────┘
```

**Detailed Architecture:**
```

┌──────────────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Control Plane                                  │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   API Server    │  │      etcd       │  │   Scheduler     │              │
│  │   (kube-api)    │  │   (Database)    │  │ (kube-scheduler)│              │
│  │    Port 6443    │  │  Ports 2379-80  │  │   Port 10259   │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   Controller    │  │     kubectl     │  │    kubeadm      │              │
│  │    Manager      │  │  (CLI Client)   │  │ (Cluster Init)  │              │
│  │   Port 10257    │  │                 │  │                 │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
└──────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Node Components                                     │
│                                                                              │
│  ┌─────────────────┐                                                         │
│  │     kubelet     │  ← Manages Pods and Containers                          │
│  │   Port 10250    │                                                         │
│  └──────┬──────────┘                                                         │
│         │                                                                    │
│         ▼                                                                    │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐        │
│  │ Ingress-nginx   │     │   K8s Services  │     │      Pods       │        │
│  │  (Controller)   │────►│   (ClusterIP)   │────►│                 │        │
│  │   Port 80/443   │     │                 │     │ gitea           │        │
│  └─────────────────┘     │ gitea:3000      │     │ umami           │        │
│                          │ umami:3000      │     │ memos           │        │
│  ┌─────────────────┐     │ memos:5230      │     │ filestash       │        │
│  │   kube-proxy    │     │ filestash:8080  │     │ uptime-kuma     │        │
│  │ (Load Balancer) │     │ uptime-kuma:3001│     │ postgresql      │        │
│  │                 │     │ postgresql:5432 │     │ static-sites    │        │
│                          │ static-sites:80 │     │                 │        │
│  └─────────────────┘     └─────────────────┘     └─────────┬───────┘        │
│                                                            │                │
│                                                            ▼                │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐        │
│  │   containerd    │     │  Containers     │     │ PostgreSQL      │        │
│  │ (Runtime + CRI) │────►│                 │────►│ (StatefulSet)   │        │
│  │                 │     │ gitea/gitea     │     │                 │        │
│  │ Image Storage   │     │ umami-software  │     │ Port 5432       │        │
│  │ Container Mgmt  │     │ neosmemo/memos  │     └─────────────────┘        │
│  └─────────────────┘     │ machines/files* │                                │
│                          │ louislam/uptime │     ┌─────────────────┐        │
│  ┌─────────────────┐     │ nginx:alpine    │     │ PersistentVols  │        │
│  │    Calico       │     │                 │     │                 │        │
│  │  (CNI Plugin)   │     └─────────────────┘     │ postgresql-data │        │
│  │                 │                             │ gitea-data      │        │
│  │ Pod Network     │     ┌─────────────────┐     │ memos-data      │        │
│  │ 192.168.0.0/16  │     │   Secrets       │     │ filestash-data  │        │
│  └─────────────────┘     │                 │     │ filestash-config│        │
│                          │ app-secrets     │     │ uptime-kuma-data│        │
│                          │ DB credentials  │     └─────────────────┘        │
│                          │ Service config  │                                │
│                          └─────────────────┘     ┌─────────────────┐        │
│                                                  │  Host Storage   │        │
│                          ┌─────────────────┐     │                 │        │
│                          │   ConfigMaps    │     │ /root/containers│        │
│                          │                 │     │ (Local volumes) │        │
│                          │ postgresql-init │     └─────────────────┘        │
│                          │ static-nginx    │                                │
│                          └─────────────────┘                                │
└──────────────────────────────────────────────────────────────────────────────┘

**Request Flow:**
1. External HTTP/HTTPS → Ingress Controller (nginx-ingress)
2. Ingress routes by hostname → Kubernetes Service (ClusterIP)
3. Service load-balances → Pod (via kube-proxy)
4. kubelet manages → Container (via containerd runtime)
5. Container connects → PostgreSQL StatefulSet (if needed)
6. PostgreSQL stores data → PersistentVolume (local storage)
7. Pod-to-pod networking handled by Calico CNI
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
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n base-infrastructure
kubectl get services -n base-infrastructure

# View logs
kubectl logs -f deployment/gitea -n base-infrastructure
kubectl logs -f deployment/umami -n base-infrastructure

# Apply configurations
kubectl apply -f k8s/
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