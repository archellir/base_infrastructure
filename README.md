# Base Infrastructure

Self-hosted services infrastructure with Docker Compose and Kubernetes deployment options.

## Architecture

### Services
- **PostgreSQL** - Shared database with multiple database support
- **Gitea** - Git hosting service
- **Umami** - Analytics platform  
- **Memos** - Note-taking application
- **Filestash** - File management interface
- **Uptime Kuma** - Uptime monitoring
- **Dozzle** - Docker logs viewer
- **k8s-webui** - Kubernetes web interface

### Docker Compose Architecture (Legacy)
```
External Request → Caddy (Reverse Proxy) → Service Container → PostgreSQL Database

┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│    Caddy    │    │  Services   │    │ PostgreSQL  │
│   (Proxy)   │◄───┤             ├───►│ (Database)  │
│    :80/:443 │    │ Gitea       │    │    :5432    │
└─────────────┘    │ Umami       │    └─────────────┘
                   │ Memos       │
                   │ Uptime-Kuma │
                   │ FileBrowser │
                   │ pgAdmin     │
                   │ Dozzle      │
                   └─────────────┘
```

### Kubernetes Architecture (Current)
```
External Request → Ingress → Service → Pod → Container → Database

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
│  │  nginx-ingress  │     │   K8s Services  │     │      Pods       │        │
│  │  (Controller)   │────►│   (ClusterIP)   │────►│                 │        │
│  │   Port 80/443   │     │                 │     │ gitea-pod       │        │
│  └─────────────────┘     │ gitea:3000      │     │ umami-pod       │        │
│                          │ umami:3000      │     │ memos-pod       │        │
│  ┌─────────────────┐     │ memos:5230      │     │ filestash-pod   │        │
│  │   kube-proxy    │     │ filestash:8080  │     │ uptime-pod      │        │
│  │ (Load Balancer) │     │ uptime:3001     │     │ dozzle-pod      │        │
│  │                 │     │ dozzle:8080     │     │ dashboard-pod   │        │
│                          │ dashboard:80    │     │ homepage-pod    │        │
│                          │ homepage:80     │     │ argmusic-pod    │        │
│                          │ argmusic:80     │     │ humans-pod      │        │
│                          │ humans:80       │     │                 │        │
│  └─────────────────┘     └─────────────────┘     └─────────┬───────┘        │
│                                                            │                │
│                                                            ▼                │
│  ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐        │
│  │   containerd    │     │  Containers     │     │ PostgreSQL      │        │
│  │ (Runtime + CRI) │────►│                 │────►│ (StatefulSet)   │        │
│  │                 │     │ gitea:latest    │     │                 │        │
│  │ Image Storage   │     │ umami:latest    │     │ Port 5432       │        │
│  │ Container Mgmt  │     │ memos:latest    │     └─────────────────┘        │
│  └─────────────────┘     │ filestash:latest│                                │
│                          │ uptime:latest   │     ┌─────────────────┐        │
│  ┌─────────────────┐     │ dozzle:latest   │     │ PersistentVols  │        │
│  │    Calico       │     │ nginx:alpine    │     │                 │        │
│  │  (CNI Plugin)   │     └─────────────────┘     │ postgresql-pvc  │        │
│  │                 │                             │ gitea-pvc       │        │
│  │ Pod Network     │     ┌─────────────────┐     │ memos-pvc       │        │
│  │ 192.168.0.0/16  │     │   Secrets       │     │ filestash-pvc   │        │
│  └─────────────────┘     │                 │     │ uptime-pvc      │        │
│                          │ DB passwords    │     └─────────────────┘        │
│                          │ API keys        │                                │
│                          │ Certificates    │     ┌─────────────────┐        │
│                          └─────────────────┘     │  Host Storage   │        │
│                                                  │                 │        │
│                          ┌─────────────────┐     │ /root/containers│        │
│                          │   ConfigMaps    │     │ (Volume Mounts) │        │
│                          │                 │     └─────────────────┘        │
│                          │ Init scripts    │                                │
│                          │ Configuration   │                                │
│                          │ Environment     │                                │
│                          └─────────────────┘                                │
└──────────────────────────────────────────────────────────────────────────────┘

Data Flow Sequence:
1. External HTTP/HTTPS → nginx-ingress (Port 80/443)
2. Ingress routes by hostname → K8s Service (ClusterIP via kube-proxy)
3. Service load-balances → Pod (Scheduled by kube-scheduler)
4. kubelet manages → Container (via containerd runtime)
5. Container connects → PostgreSQL StatefulSet (Database)
6. PostgreSQL stores data → PersistentVolume (Host storage)
7. All communication secured by API Server and managed by Controller Manager
8. Pod-to-pod networking handled by Calico CNI (192.168.0.0/16)
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
- **Storage**: PersistentVolumes for stateful services
- **Management**: kubectl CLI, kubeadm for cluster management

## Migration Status

✅ **Kubernetes cluster ready**  
🔄 **Migration in progress** - Use `./migration-commands.sh` for step-by-step migration  
📋 **Documentation**: See `k8s-setup.md` and `migration-guide.md`

## Quick Commands

### Kubernetes Management
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Migration script
./migration-commands.sh help
./migration-commands.sh phase0  # Start with backup
```

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
│   ├── gitea/             # Git service  
│   ├── umami/             # Analytics service
│   ├── memos/             # Notes service
│   ├── filestash/         # File management
│   ├── uptime-kuma/       # Monitoring service
│   ├── dozzle/            # Log viewer
│   ├── k8s-webui/         # Kubernetes web UI
│   ├── ingress/           # Ingress rules
│   └── namespace/         # Secrets, ConfigMaps
├── caddy/                  # Reverse proxy (Docker)
├── postgresql/             # Database (Docker)
├── migration-commands.sh   # Migration automation
├── migration-guide.md     # Detailed migration steps
└── k8s-setup.md           # Kubernetes installation guide
```

## Connection Examples
```bash
# Database connection format
postgres://username:password@container_name:port/db_name

# Internal service communication (Docker)
http://service_name:port

# Kubernetes service communication
http://service-name.namespace.svc.cluster.local:port
```

---

*Infrastructure supporting distributed applications with high availability and scalability*