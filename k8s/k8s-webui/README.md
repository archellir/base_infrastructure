# K8s WebUI Deployment

This directory contains Kubernetes manifests for deploying the K8s WebUI application to manage the base-infrastructure services.

## Overview

The K8s WebUI provides a web interface for monitoring and managing the Kubernetes infrastructure services including:

- **Gitea** - Git repository hosting
- **Umami** - Web analytics platform  
- **Memos** - Notes and memos service
- **Uptime Kuma** - Uptime monitoring dashboard
- **FileBrowser** - File browser and management
- **Dozzle** - Container logs viewer
- **PostgreSQL** - Database server

## Architecture

The application consists of:

- **Frontend**: Svelte 5 application serving the web interface
- **Backend**: Bun.js API server with Kubernetes client integration
- **PostgreSQL**: Database for audit logs and application data
- **Redis**: Session storage and caching

## Deployment

### Prerequisites

1. Kubernetes cluster with nginx-ingress controller
2. cert-manager for SSL certificates (optional)
3. DNS configured for `k8s.arcbjorn.com`

### Build Images

First, build the Docker images for the frontend and backend:

```bash
# From the hellir/k8s-webui directory
cd ../../hellir/k8s-webui

# Build backend image
docker build -t k8s-webui-backend:latest ./backend

# Build frontend image  
docker build -t k8s-webui-frontend:latest ./frontend

# Tag and push to your registry if needed
# docker tag k8s-webui-backend:latest your-registry/k8s-webui-backend:latest
# docker push your-registry/k8s-webui-backend:latest
```

### Deploy to Kubernetes

Apply the manifests in order:

```bash
# Create namespace and RBAC
kubectl apply -f namespace.yaml
kubectl apply -f rbac.yaml

# Create secrets and config
kubectl apply -f secrets.yaml

# Deploy database and cache
kubectl apply -f postgres.yaml
kubectl apply -f redis.yaml

# Wait for database to be ready
kubectl wait --for=condition=ready pod -l app=k8s-webui-postgres -n k8s-webui --timeout=120s

# Deploy application
kubectl apply -f backend-deployment.yaml
kubectl apply -f frontend-deployment.yaml

# Create ingress
kubectl apply -f ingress.yaml
```

### Verify Deployment

Check that all pods are running:

```bash
kubectl get pods -n k8s-webui
kubectl get services -n k8s-webui
kubectl get ingress -n k8s-webui
```

## Access

Once deployed, the application will be available at:

- **URL**: https://k8s.arcbjorn.com
- **Credentials**: admin / admin (change in production)

## Configuration

### Environment Variables

Key configuration is managed through:

- `k8s-webui-config` ConfigMap
- `k8s-webui-secrets` Secret

### RBAC Permissions

The application uses a ServiceAccount with minimal required permissions:

- Read access to pods, services, deployments, statefulsets, ingresses
- Read access to configmaps and secrets (data redacted)
- Limited write access for scaling deployments
- Access to pod logs

### Security Notes

- Generate a secure 32-byte PASETO key for production (run `bun run generate-key` in backend/)
- Update database passwords
- Review RBAC permissions based on your security requirements
- Consider using external secrets management
- PASETO tokens provide better security than JWT (immune to algorithm confusion attacks)

## Monitoring

The application provides:

- Real-time WebSocket updates for cluster status
- Health check endpoints at `/health`
- Prometheus-compatible metrics (if metrics-server is installed)

## Troubleshooting

### Common Issues

1. **Images not found**: Ensure Docker images are built and available in your cluster
2. **RBAC errors**: Verify ServiceAccount and ClusterRole are applied
3. **Database connection**: Check postgres StatefulSet is running and ready
4. **Ingress not working**: Verify nginx-ingress controller and DNS configuration

### Logs

```bash
# Backend logs
kubectl logs -f deployment/k8s-webui-backend -n k8s-webui

# Frontend logs  
kubectl logs -f deployment/k8s-webui-frontend -n k8s-webui

# Database logs
kubectl logs -f statefulset/k8s-webui-postgres -n k8s-webui
```

## Development

For local development, use the docker-compose setup in the hellir/k8s-webui directory:

```bash
cd ../../hellir/k8s-webui
docker-compose up -d
```

This will start the application with hot reload and development databases.