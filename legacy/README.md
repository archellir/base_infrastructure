# Legacy Docker Compose Files

This directory contains the original Docker Compose configuration files that were used before migrating to Kubernetes.

## Migration Status: ✅ COMPLETE

All services have been successfully migrated to Kubernetes and are running in the `base-infra` namespace.

## Legacy Services

| Service | Status | K8s Equivalent |
|---------|--------|----------------|
| **PostgreSQL** | ✅ Migrated | StatefulSet in k8s/postgresql/ |
| **Gitea** | ✅ Migrated | Deployment in k8s/gitea/ |
| **Umami** | ✅ Migrated | Deployment in k8s/umami/ |
| **Memos** | ✅ Migrated | Deployment in k8s/memos/ |
| **Uptime Kuma** | ✅ Migrated | Deployment in k8s/uptime-kuma/ |
| **Caddy** | ✅ Replaced | nginx-ingress in k8s/ingress/ |
| **Filebrowser** | ✅ Replaced | Filestash in k8s/filestash/ |
| **Dozzle** | ✅ Replaced | kubectl logs commands |

## Notes

- These files are kept for reference only
- Docker container data has been cleaned up from the server
- All services now run on Kubernetes with improved reliability and automation
- External access works via nginx-ingress with hostNetwork and iptables bypass rules

## DO NOT USE

These Docker Compose files should not be used anymore. Use the Kubernetes manifests in the `k8s/` directory instead.