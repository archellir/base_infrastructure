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
kubectl get pods -n base-infra
kubectl get services -n base-infra

# Apply all configurations
kubectl apply -f k8s/

# View service logs
kubectl logs -f deployment/gitea -n base-infra
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

# Scale a service
kubectl scale deployment gitea --replicas=2 -n base-infra

# Port forward for testing
kubectl port-forward svc/gitea 4000:3000 -n base-infra
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
- `server.arcbjorn.com` → Filestash service (filestash:8080)
- `uptime.arcbjorn.com` → Uptime Kuma service (uptime-kuma:3001)
- Static sites: `dashboard.arcbjorn.com`, `homepage.arcbjorn.com`, `argentinamusic.space`, `humansconnect.ai`

## Development Notes

- Database connections use Kubernetes service names: `postgresql://username:password@postgresql:5432/db_name`
- PersistentVolumes require proper host directory permissions: `chown -R 1000:1000 /root/containers/`
- Services communicate via Kubernetes DNS: `service-name.namespace.svc.cluster.local`
- All services use the shared PostgreSQL StatefulSet with multiple databases
- Storage is limited to 512Mi per service (expandable by updating PV specs)
- External access uses nginx-ingress with hostNetwork: true (no NodePort/LoadBalancer needed)
- iptables bypass rules inserted at position 1 in INPUT chain (before UFW/Calico rules)

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

## Testing and Verification Rules

- **DO NOT SAY SOMETHING IS WORKING UNTIL YOU VERIFY IT**
- **Test actual external URLs that users will access**
- **Verify both HTTP and HTTPS from external perspective**
- **Check all services, not just one**
- **Test from user's perspective, not localhost**