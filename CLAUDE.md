# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Kubernetes-based infrastructure repository that manages multiple self-hosted services with ingress routing and persistent storage. The architecture consists of:

- **Kubernetes Cluster**: Single-node cluster managing all services
- **Ingress Controller**: nginx-ingress with hostNetwork for direct port access (80/443)
- **Firewall Bypass**: Docker-style iptables rules for external access without UFW changes
- **SSL Certificates**: Individual Let's Encrypt certificates per domain (not multi-domain)
- **Persistent Storage**: Local volumes for stateful services
- **PostgreSQL**: Shared database StatefulSet with multiple databases

## Service Structure

Each service directory under `k8s/` contains:
- `*-deployment.yaml` - Deployment, Service, and PVC manifests
- Service-specific PersistentVolumes mounted to `/root/containers/` on the host

Active services:
- **k8s/postgresql/**: Shared PostgreSQL StatefulSet
- **k8s/monitoring/**: Prometheus monitoring stack for denshimon real-time metrics
- **k8s/gitea/**: Git hosting service with container registry (git.arcbjorn.com)
- **k8s/gitea/gitea-actions-runner**: Gitea Actions runner for CI/CD workflows
- **k8s/umami/**: Analytics platform (analytics.arcbjorn.com)
- **k8s/memos/**: Note-taking application (memos.arcbjorn.com)
- **k8s/filebrowser/**: File management interface (server.arcbjorn.com)
- **k8s/uptime-kuma/**: Uptime monitoring (uptime.arcbjorn.com)
- **k8s/static-sites/**: Static website deployments

## Common Commands

### Kubernetes Operations
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n base-infra
kubectl get services -n base-infra

# Apply all configurations
kubectl apply -f k8s/

# View service logs
kubectl logs -f deployment/gitea -n base-infra
kubectl logs -f deployment/gitea-actions-runner -n base-infra
kubectl logs -f deployment/umami -n base-infra
```

### Database Operations
```bash
# Connect to PostgreSQL
kubectl exec -it postgresql-0 -n base-infra -- psql -U postgres -d postgres

# Backup all databases
kubectl exec -t postgresql-0 -n base-infra -- pg_dumpall -c -U postgres > backup_$(date +%Y%m%d).sql

# Create new database user
kubectl exec -it postgresql-0 -n base-infra -- psql -U postgres -d postgres -c "CREATE USER newuser WITH PASSWORD 'password';"
```

### Service Management
```bash  
# Restart a service
kubectl rollout restart deployment/gitea -n base-infra
kubectl rollout restart deployment/gitea-actions-runner -n base-infra

# Scale a service
kubectl scale deployment gitea --replicas=2 -n base-infra

# Port forward for testing
kubectl port-forward svc/gitea 4000:3000 -n base-infra
```

### Monitoring Stack Operations
```bash
# Deploy monitoring stack
cd k8s/monitoring && ./deploy.sh

# Check monitoring services status
kubectl get pods -n monitoring
kubectl get services -n monitoring

# View monitoring logs
kubectl logs -f deployment/prometheus -n monitoring
kubectl logs -f deployment/kube-state-metrics -n monitoring
kubectl logs -f daemonset/node-exporter -n monitoring
kubectl logs -f daemonset/storage-exporter -n monitoring

# Access Prometheus UI (for debugging)
kubectl port-forward -n monitoring svc/prometheus-service 9090:9090

# Check Prometheus targets and metrics
curl http://localhost:9090/api/v1/targets
curl http://localhost:9090/api/v1/query?query=up

# Restart monitoring components
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout restart deployment/kube-state-metrics -n monitoring
kubectl rollout restart daemonset/node-exporter -n monitoring
kubectl rollout restart daemonset/storage-exporter -n monitoring
```

### Gitea Actions and CI/CD
```bash
# Check runner status
kubectl get pods -n base-infra -l app=gitea-actions-runner
kubectl logs -f deployment/gitea-actions-runner -n base-infra

# Get runner registration token (from Gitea admin panel)
# https://git.arcbjorn.com/admin/actions/runners

# Add runner token to secrets
kubectl patch secret app-secrets -n base-infra --type='merge' -p='{"data":{"GITEA_RUNNER_TOKEN":"'$(echo -n 'YOUR_TOKEN_HERE' | base64)'"}}'

# Example workflow for Docker build and push to registry
# Place in repository: .gitea/workflows/docker-build.yml
```

Example CI/CD workflow:
```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [ main, master ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
    
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
    
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: |
          git.arcbjorn.com/${{ gitea.repository }}:${{ gitea.sha }}
          git.arcbjorn.com/${{ gitea.repository }}:latest
```

## Configuration Dependencies

- Kubernetes secrets stored in `k8s/namespace/secrets.yaml` (not tracked in repo)
- PostgreSQL uses ConfigMap for database initialization
- Ingress controller uses hostNetwork: true for direct port 80/443 access
- Docker-style iptables bypass rules: `DOCKER-STYLE-HTTP-BYPASS` (port 80), `DOCKER-STYLE-HTTPS-BYPASS` (port 443)
- Individual SSL certificates per domain (each domain gets separate Let's Encrypt certificate)
- Static websites served from hostPath volumes at `/root/static/`

## Domain Mapping (Ingress)

- `git.arcbjorn.com` → Gitea service (gitea:3000)
- `analytics.arcbjorn.com` → Umami service (umami:3000)
- `memos.arcbjorn.com` → Memos service (memos:5230)
- `server.arcbjorn.com` → Filebrowser service (filebrowser:80)
- `uptime.arcbjorn.com` → Uptime Kuma service (uptime-kuma:3001)
- Static sites: `dashboard.arcbjorn.com`, `homepage.arcbjorn.com`, `argentinamusic.space`, `humansconnect.ai`

## Development Notes

- Database connections use Kubernetes service names: `postgresql://username:password@postgresql:5432/db_name`
- **Monitoring backend connection**: `http://prometheus-service.monitoring.svc.cluster.local:9090`
- PersistentVolumes require proper host directory permissions: `chown -R 1000:1000 /root/containers/`
- Gitea Actions runner requires Docker socket access and privileged container mode
- Services communicate via Kubernetes DNS: `service-name.namespace.svc.cluster.local`
- All services use the shared PostgreSQL StatefulSet with multiple databases
- Storage is limited to 512Mi per service (expandable by updating PV specs)
- External access uses nginx-ingress with hostNetwork: true (no NodePort/LoadBalancer needed)
- iptables bypass rules inserted at position 1 in INPUT chain (before UFW/Calico rules)
- **Monitoring stack provides real metrics for denshimon dashboards** (replaces frontend mock data)

## Network Security

- UFW firewall remains unchanged (only SSH port 22 allowed)
- External access achieved via Docker-style iptables bypass rules
- Rules automatically added by deploy script, removed by cleanup script
- Individual SSL certificates per domain prevent certificate domain conflicts

## Git Commit Guidelines

- Use conventional commits format: `type(scope): description`
- Keep commit messages clean and focused on code changes only
- NEVER add co-authors, "Generated with" tags, or other metadata
- Use separate commits for different file types/purposes:
  - Scripts/automation: `feat:` or `fix:`
  - Documentation: `docs:`
  - Configuration: `fix:` or `refactor:`
- Focus on what changed and why, not who or how it was generated

## Important Automation Rules

- **NEVER perform manual database operations or fixes**
- **ALWAYS fix the automation scripts instead of manual intervention**
- If database initialization fails, fix the cleanup script to properly remove all data directories
- Database issues must be resolved by fixing scripts, not by manual database commands
- Ingress admission webhook conflicts are automatically handled in deploy script
- #memoize principle: Always improve automation rather than doing manual work

## Monitoring Stack Architecture

### Components
- **Prometheus Server**: Central metrics database with 15-day retention
- **Node Exporter**: System-level metrics (CPU, memory, disk I/O, network)
- **kube-state-metrics**: Kubernetes object state metrics (pods, deployments, nodes)
- **Storage Exporter**: Custom per-volume IOPS, throughput, and latency metrics

### Integration
- **denshimon backend** connects to Prometheus API for real dashboard data
- **Replaces frontend mock data** with actual infrastructure metrics
- **Headless deployment**: No external UI, ClusterIP services only
- **Automatic service discovery** and 15-second scrape intervals

### Key Metrics Available
```promql
# CPU usage across cluster
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory utilization
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Network traffic by pod
sum(rate(container_network_receive_bytes_total[5m])) by (pod)

# Storage IOPS and throughput
storage_volume_read_iops{volume="pvc-name"}
storage_volume_write_throughput_bytes{volume="pvc-name"}
```

## Testing and Verification Rules

- **DO NOT SAY SOMETHING IS WORKING UNTIL YOU VERIFY IT**
- **Test actual external URLs that users will access**
- **Verify both HTTP and HTTPS from external perspective**
- **Check all services, not just one**
- **Test from user's perspective, not localhost**
- **Verify monitoring stack**: Check all exporters are scraped and metrics available