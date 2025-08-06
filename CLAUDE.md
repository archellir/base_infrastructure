# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Kubernetes-based infrastructure repository that manages multiple self-hosted services with ingress routing and persistent storage. The architecture consists of:

- **Kubernetes Cluster**: Single-node cluster managing all services
- **Ingress Controller**: nginx-ingress handles SSL/TLS termination and routing
- **Persistent Storage**: Local volumes for stateful services
- **PostgreSQL**: Shared database StatefulSet with multiple databases

## Service Structure

Each service directory under `k8s/` contains:
- `*-deployment.yaml` - Deployment, Service, and PVC manifests
- Service-specific PersistentVolumes mounted to `/root/containers/` on the host

Active services:
- **k8s/postgresql/**: Shared PostgreSQL StatefulSet
- **k8s/gitea/**: Git hosting service (git.arcbjorn.com)
- **k8s/umami/**: Analytics platform (analytics.arcbjorn.com)
- **k8s/memos/**: Note-taking application (memos.arcbjorn.com)
- **k8s/filestash/**: File management interface (server.arcbjorn.com)
- **k8s/uptime-kuma/**: Uptime monitoring (uptime.arcbjorn.com)
- **k8s/static-sites/**: Static website deployments

## Common Commands

### Kubernetes Operations
```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n base-infrastructure
kubectl get services -n base-infrastructure

# Apply all configurations
kubectl apply -f k8s/

# View service logs
kubectl logs -f deployment/gitea -n base-infrastructure
kubectl logs -f deployment/umami -n base-infrastructure
```

### Database Operations
```bash
# Connect to PostgreSQL
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -d postgres

# Backup all databases
kubectl exec -t postgresql-0 -n base-infrastructure -- pg_dumpall -c -U postgres > backup_$(date +%Y%m%d).sql

# Create new database user
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -d postgres -c "CREATE USER newuser WITH PASSWORD 'password';"
```

### Service Management
```bash  
# Restart a service
kubectl rollout restart deployment/gitea -n base-infrastructure

# Scale a service
kubectl scale deployment gitea --replicas=2 -n base-infrastructure

# Port forward for testing
kubectl port-forward svc/gitea 4000:3000 -n base-infrastructure
```

## Configuration Dependencies

- Kubernetes secrets stored in `k8s/namespace/secrets.yaml` (not tracked in repo)
- PostgreSQL uses ConfigMap for database initialization
- Ingress controller maps domains to Kubernetes services
- Static websites served from hostPath volumes at `/root/static/`

## Domain Mapping (Ingress)

- `git.arcbjorn.com` → Gitea service (gitea:3000)
- `analytics.arcbjorn.com` → Umami service (umami:3000)
- `memos.arcbjorn.com` → Memos service (memos:5230)
- `server.arcbjorn.com` → Filestash service (filestash:8080)
- `uptime.arcbjorn.com` → Uptime Kuma service (uptime-kuma:3001)
- Static sites: `dashboard.arcbjorn.com`, `homepage.arcbjorn.com`, `argentinamusic.space`, `humansconnect.ai`

## Development Notes

- Database connections use Kubernetes service names: `postgresql://username:password@postgresql:5432/db_name`
- PersistentVolumes require proper host directory permissions: `chown -R 1000:1000 /root/containers/`
- Services communicate via Kubernetes DNS: `service-name.namespace.svc.cluster.local`
- All services use the shared PostgreSQL StatefulSet with multiple databases
- Storage is limited to 512Mi per service (expandable by updating PV specs)

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
- #memoize principle: Always improve automation rather than doing manual work