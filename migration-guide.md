# Docker Compose to Kubernetes Migration Guide

This guide provides a complete step-by-step migration process from Docker Compose to Kubernetes.

## Prerequisites

- ✅ Kubernetes cluster running (confirmed in k8s-migration.md)
- ✅ kubectl configured and working
- ✅ Access to current Docker Compose services
- ✅ Portainer secrets available

## Phase 0: Pre-Migration Backup & Preparation

### 1. Create Backup Directory
```bash
mkdir -p ~/k8s-migration-backup/$(date +%Y%m%d-%H%M%S)
cd ~/k8s-migration-backup/$(date +%Y%m%d-%H%M%S)
```

### 2. Backup All Docker Volumes
```bash
# PostgreSQL data (CRITICAL)
sudo tar -czf postgresql-data-backup.tar.gz -C /root/containers/postgresql/data .

# Gitea data (CRITICAL)
sudo tar -czf gitea-data-backup.tar.gz -C /root/containers/gitea/data .

# Other service data
sudo tar -czf pgadmin-backup.tar.gz -C /root/containers/pgadmin .
sudo tar -czf filebrowser-backup.tar.gz -C /root/containers/filebrowser .
sudo tar -czf uptime-kuma-backup.tar.gz -C /root/containers/uptime-kuma .
sudo tar -czf memos-backup.tar.gz -C /root/containers/memos .

# Verify backups
ls -lah *.tar.gz
```

### 3. Export Docker Compose Environment
```bash
# Extract current environment variables from Portainer or stack.env
# Save them to a temporary file for reference
cat > docker-secrets.env << 'EOF'
# Copy your actual values from Portainer:
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_actual_password
POSTGRES_DB=postgres
POSTGRES_MULTIPLE_DATABASES=gitea,umami,memos

# Gitea database
GIT_DB=gitea
GIT_DB_USER=gitea
GIT_DB_USER_PASSWORD=your_actual_password

# pgAdmin
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=your_actual_password

# Add any other secrets from Portainer
EOF
```

### 4. Create Kubernetes Secrets
```bash
# Base64 encode your secrets (replace with actual values)
echo -n "your_postgres_password" | base64
echo -n "your_gitea_password" | base64
echo -n "admin@example.com" | base64

# Edit the secrets file with real values
nano k8s/namespace/secrets.yaml
```

## Phase 1: Infrastructure Setup

### 1. Create Namespace and Core Resources
```bash
# Apply namespace
kubectl apply -f k8s/namespace/namespace.yaml

# Verify namespace
kubectl get namespaces

# Apply configmap (for PostgreSQL init scripts)
kubectl apply -f k8s/namespace/configmap.yaml

# Apply secrets (after updating with real values)
kubectl apply -f k8s/namespace/secrets.yaml

# Verify secrets (don't show values)
kubectl get secrets -n base-infrastructure
```

### 2. Start PostgreSQL (Foundation Service)
```bash
# Apply PostgreSQL StatefulSet and Service
kubectl apply -f k8s/postgresql/postgresql-statefulset.yaml
kubectl apply -f k8s/postgresql/postgresql-service.yaml

# Wait for PostgreSQL to be ready (this is CRITICAL)
kubectl wait --for=condition=ready pod -l app=postgresql -n base-infrastructure --timeout=300s

# Verify PostgreSQL is running
kubectl get pods -n base-infrastructure -l app=postgresql
kubectl logs -n base-infrastructure -l app=postgresql
```

### 3. Migrate PostgreSQL Data
```bash
# Copy PostgreSQL backup to the running pod
kubectl cp postgresql-data-backup.tar.gz base-infrastructure/postgresql-0:/tmp/

# Extract data in the pod (if migrating existing data)
kubectl exec -it postgresql-0 -n base-infrastructure -- bash -c "
  cd /var/lib/postgresql/data
  tar -xzf /tmp/postgresql-data-backup.tar.gz
  chown -R postgres:postgres .
"

# Test PostgreSQL connection
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -c '\l'
```

## Phase 2: Core Services Deployment

### 1. Deploy Gitea
```bash
# Apply Gitea deployment
kubectl apply -f k8s/gitea/gitea-deployment.yaml

# Wait for Gitea to be ready
kubectl wait --for=condition=ready pod -l app=gitea -n base-infrastructure --timeout=300s

# Check Gitea logs
kubectl logs -n base-infrastructure -l app=gitea --tail=50
```

### 2. Migrate Gitea Data
```bash
# Find Gitea pod name
GITEA_POD=$(kubectl get pods -n base-infrastructure -l app=gitea -o jsonpath='{.items[0].metadata.name}')

# Copy Gitea backup
kubectl cp gitea-data-backup.tar.gz base-infrastructure/$GITEA_POD:/tmp/

# Extract Gitea data
kubectl exec -it $GITEA_POD -n base-infrastructure -- bash -c "
  cd /data
  tar -xzf /tmp/gitea-data-backup.tar.gz
  chown -R 1000:1000 .
"

# Restart Gitea to pick up data
kubectl rollout restart deployment/gitea -n base-infrastructure
kubectl wait --for=condition=ready pod -l app=gitea -n base-infrastructure --timeout=300s
```

### 3. Deploy Other Services
```bash
# Deploy all other services
kubectl apply -f k8s/umami/umami-deployment.yaml
kubectl apply -f k8s/memos/memos-deployment.yaml
kubectl apply -f k8s/uptime-kuma/uptime-kuma-deployment.yaml
kubectl apply -f k8s/dozzle/dozzle-deployment.yaml

# Note: filestash-deployment.yaml might be for filebrowser replacement
kubectl apply -f k8s/filestash/filestash-deployment.yaml

# Wait for all services to be ready
kubectl wait --for=condition=ready pod -l app=umami -n base-infrastructure --timeout=300s
kubectl wait --for=condition=ready pod -l app=memos -n base-infrastructure --timeout=300s
kubectl wait --for=condition=ready pod -l app=uptime-kuma -n base-infrastructure --timeout=300s
kubectl wait --for=condition=ready pod -l app=dozzle -n base-infrastructure --timeout=300s
```

### 4. Migrate Service Data
```bash
# Migrate other service data as needed
# Example for memos:
MEMOS_POD=$(kubectl get pods -n base-infrastructure -l app=memos -o jsonpath='{.items[0].metadata.name}')
kubectl cp memos-backup.tar.gz base-infrastructure/$MEMOS_POD:/tmp/
kubectl exec -it $MEMOS_POD -n base-infrastructure -- bash -c "cd /var/opt/memos && tar -xzf /tmp/memos-backup.tar.gz"

# Repeat for other services as needed
```

## Phase 3: Networking & Ingress

### 1. Deploy Ingress
```bash
# Apply ingress rules
kubectl apply -f k8s/ingress/ingress.yaml

# Check ingress status
kubectl get ingress -n base-infrastructure
kubectl describe ingress -n base-infrastructure
```

### 2. Verify Service Access
```bash
# Check all pods are running
kubectl get pods -n base-infrastructure

# Check all services
kubectl get services -n base-infrastructure

# Test internal connectivity
kubectl exec -it postgresql-0 -n base-infrastructure -- nslookup gitea
```

## Phase 4: k8s-webui Setup (CI/CD)

### 1. Configure Gitea Container Registry
```bash
# Access Gitea admin panel through port-forward first
kubectl port-forward -n base-infrastructure svc/gitea 3000:3000

# In browser: http://localhost:3000
# Go to Site Administration > Configuration
# Enable "Enable Container Registry" if not already enabled
```

### 2. Create Gitea CI/CD Pipeline
Create in your k8s-webui repositories:
```yaml
# .gitea/workflows/build-and-deploy.yaml
name: Build and Deploy k8s-webui
on:
  push:
    branches: [main]

jobs:
  build-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push backend
        run: |
          docker build -t git.arcbjorn.com/archellir/k8s-webui-backend:latest ./backend
          docker push git.arcbjorn.com/archellir/k8s-webui-backend:latest
  
  build-frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build and push frontend
        run: |
          docker build -t git.arcbjorn.com/archellir/k8s-webui-frontend:latest ./frontend
          docker push git.arcbjorn.com/archellir/k8s-webui-frontend:latest

  deploy:
    needs: [build-backend, build-frontend]
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to k8s
        run: |
          kubectl rollout restart deployment/k8s-webui-backend -n base-infrastructure
          kubectl rollout restart deployment/k8s-webui-frontend -n base-infrastructure
```

### 3. Deploy k8s-webui
```bash
# After CI/CD is set up and images are built
kubectl apply -f k8s/k8s-webui/k8s-webui-deployment.yaml

# Wait for deployment
kubectl wait --for=condition=ready pod -l app=k8s-webui-backend -n base-infrastructure --timeout=300s
kubectl wait --for=condition=ready pod -l app=k8s-webui-frontend -n base-infrastructure --timeout=300s
```

## Phase 5: Verification & Testing

### 1. Service Health Check
```bash
# Check all pods are running
kubectl get pods -n base-infrastructure

# Check service endpoints
kubectl get endpoints -n base-infrastructure

# Test database connections
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -c '\l'

# Check logs for errors
kubectl logs -n base-infrastructure -l app=gitea --tail=20
kubectl logs -n base-infrastructure -l app=umami --tail=20
```

### 2. External Access Test
```bash
# Port forward to test services
kubectl port-forward -n base-infrastructure svc/gitea 3000:3000 &
kubectl port-forward -n base-infrastructure svc/umami 3001:3000 &
kubectl port-forward -n base-infrastructure svc/k8s-webui-frontend 3002:3000 &

# Test in browser:
# http://localhost:3000 - Gitea
# http://localhost:3001 - Umami  
# http://localhost:3002 - k8s-webui

# Kill port forwards
pkill -f "kubectl port-forward"
```

### 3. Data Integrity Check
```bash
# Verify PostgreSQL databases exist
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -c '\l'

# Check Gitea repositories are accessible
# Check Umami analytics data
# Verify other service data
```

## Phase 6: DNS & Production Access

### 1. Update DNS Records
Point your domains to the Kubernetes ingress IP:
```bash
# Get ingress IP
kubectl get ingress -n base-infrastructure -o wide

# Update DNS A records:
# git.arcbjorn.com -> <ingress-ip>
# analytics.arcbjorn.com -> <ingress-ip>
# uptime.arcbjorn.com -> <ingress-ip>
# etc.
```

### 2. SSL Certificate Check
```bash
# Check if cert-manager is handling SSL
kubectl get certificates -n base-infrastructure
kubectl describe ingress -n base-infrastructure
```

## Phase 7: Docker Cleanup (ONLY AFTER VERIFICATION)

### 1. Stop Docker Compose Services
```bash
# Navigate to each service directory and stop
cd caddy && docker-compose down
cd ../postgresql && docker-compose down
cd ../gitea && docker-compose down
cd ../umami && docker-compose down
cd ../memos && docker-compose down
cd ../uptime-kuma && docker-compose down
cd ../dozzle && docker-compose down
cd ../filebrowser && docker-compose down
```

### 2. Clean Up Docker Resources
```bash
# Remove containers
docker container prune -f

# Remove dangling images
docker image prune -f

# Remove unused volumes (BE CAREFUL - only after data is confirmed migrated)
docker volume prune -f

# Remove unused networks
docker network prune -f

# Clean up everything (DANGEROUS - only when confident)
# docker system prune -a --volumes -f
```

### 3. Archive Old Configuration
```bash
# Move docker-compose files to archive
mkdir -p ~/docker-compose-archive
cp -r caddy/ postgresql/ gitea/ umami/ memos/ uptime-kuma/ dozzle/ filebrowser/ ~/docker-compose-archive/
```

## Troubleshooting

### Common Issues & Solutions

1. **Pod stuck in Pending**
   ```bash
   kubectl describe pod <pod-name> -n base-infrastructure
   # Check: PVC binding, resource constraints, node capacity
   ```

2. **Database connection errors**
   ```bash
   kubectl logs -n base-infrastructure -l app=postgresql
   kubectl exec -it postgresql-0 -n base-infrastructure -- pg_isready
   ```

3. **Service not accessible**
   ```bash
   kubectl get endpoints -n base-infrastructure
   kubectl port-forward -n base-infrastructure svc/<service-name> 8080:3000
   ```

4. **Ingress not working**
   ```bash
   kubectl get ingress -n base-infrastructure
   kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
   ```

### Rollback Procedure

If migration fails:
```bash
# 1. Scale down K8s deployments
kubectl scale deployment --all --replicas=0 -n base-infrastructure

# 2. Restore Docker Compose services
cd postgresql && docker-compose up -d
cd ../gitea && docker-compose up -d
# ... etc

# 3. Restore data if needed
sudo tar -xzf ~/k8s-migration-backup/*/postgresql-data-backup.tar.gz -C /root/containers/postgresql/data/
```

## Post-Migration Checklist

- [ ] All services running in Kubernetes
- [ ] Data integrity verified
- [ ] External access working via ingress
- [ ] SSL certificates working
- [ ] DNS records updated
- [ ] Monitoring/logging working
- [ ] Backup strategy updated for K8s
- [ ] Docker resources cleaned up
- [ ] Documentation updated

## Migration Success Verification

Run these final checks:
```bash
# All pods running
kubectl get pods -n base-infrastructure | grep -v Running && echo "❌ Some pods not running" || echo "✅ All pods running"

# All services have endpoints  
kubectl get endpoints -n base-infrastructure

# Database accessible
kubectl exec -it postgresql-0 -n base-infrastructure -- psql -U postgres -c 'SELECT version();'

# Ingress configured
kubectl get ingress -n base-infrastructure

echo "🎉 Migration completed successfully!"
```

---

**⚠️ Important Notes:**
- Always backup before starting migration
- Test each phase before proceeding 
- Keep Docker Compose running until K8s is fully verified
- Monitor logs during migration for issues
- Have rollback plan ready

**Migration Time Estimate:** 2-4 hours depending on data size and complexity