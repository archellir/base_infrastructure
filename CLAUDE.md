# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a Docker-based infrastructure repository that manages multiple self-hosted services behind a Caddy reverse proxy. The architecture consists of:

- **Caddy**: Acts as the reverse proxy and handles SSL/TLS termination for all services
- **Centralized networking**: All services connect through the `caddy-network` Docker network
- **Service isolation**: Each service has its own directory with dedicated docker-compose configuration
- **PostgreSQL**: Shared database infrastructure with support for multiple databases

## Service Structure

Each service directory contains:
- `docker-compose.yml/yaml` - Service configuration
- Service-specific volumes mounted to `/containers/` or `/root/containers/` on the host

Key services:
- **caddy/**: Reverse proxy with Caddyfile configuration mapping domains to services
- **postgresql/**: Shared PostgreSQL instance with pgAdmin interface
- **umami/**: Analytics service with dedicated PostgreSQL database
- **gitea/**: Git hosting service
- **memos/**: Note-taking application
- **filebrowser/**: File management interface
- **uptime-kuma/**: Uptime monitoring
- **dozzle/**: Docker logs viewer

## Common Commands

### Starting the Infrastructure
1. **Start core services first**: `cd caddy && docker compose up -d`
2. **Start PostgreSQL networks**: `docker network create postgresql-network`
3. **Start individual services**: Navigate to each service directory and run `docker compose up -d`

### Database Operations
```bash
# Make database script executable
chmod +x postgresql/create-multiple-postgresql-databases.sh

# Backup all databases
docker exec -t <postgres-container-id> pg_dumpall -c -U <user> > dump_`date +%d-%m-%Y"_"%H_%M_%S`.sql

# Restore databases
cat <dump_name>.sql | docker exec -i <postgres-container-id> psql -U <user>
```

### Network Management
```bash
# Create required networks
docker network create caddy-network
docker network create postgresql-network
docker network create umami-network
```

## Configuration Dependencies

- Services reference `../stack.env` for environment variables (not tracked in repo)
- PostgreSQL uses the multiple database creation script at `postgresql/create-multiple-postgresql-databases.sh`
- Caddy configuration maps domains to service containers in `/caddy/Caddyfile`
- Static websites are served from `/static/` directory on the host

## Domain Mapping (Caddyfile)

- `infra.arcbjorn.com` → Portainer (portainer:9000)
- `db.arcbjorn.com` → pgAdmin (pgadmin:80)
- `git.arcbjorn.com` → Gitea (gitea:3000)
- `analytics.arcbjorn.com` → Umami (umami:3000)
- `uptime.arcbjorn.com` → Uptime Kuma (uptime-kuma:3001)
- `server.arcbjorn.com` → FileBrowser (filebrowser:8080)
- `logs.arcbjorn.com` → Dozzle (dozzle:8080)
- `memos.arcbjorn.com` → Memos (memos:5230)
- Static sites: `dashboard.arcbjorn.com`, `homepage.arcbjorn.com`

## Development Notes

- Database connections use container names as hostnames: `postgres://username:password@container_name:port/db_name`
- pgAdmin requires proper permissions: `sudo chown -R 5050:5050 <host_directory>`
- Services depend on external Docker networks being created before startup
- Some services (like Umami) run their own dedicated PostgreSQL instances