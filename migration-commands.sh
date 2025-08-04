#!/bin/bash

# Docker Compose to Kubernetes Migration Script
# This script provides executable commands for the migration process
# Run sections individually, do not execute the entire script at once

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }  
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running in correct directory
check_directory() {
    if [[ ! -f "CLAUDE.md" ]] || [[ ! -d "k8s" ]]; then
        log_error "Must run from base_infrastructure directory"
        log_info "Current directory: $(pwd)"
        log_info "Expected files: CLAUDE.md, k8s/ directory"
        exit 1
    fi
}

# Check SSH environment and requirements
check_ssh_environment() {
    log_info "Checking SSH environment..."
    
    # Check if we're in SSH session
    if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
        log_info "✅ Running over SSH connection"
        
        # Check if kubectl is available
        if ! command -v kubectl &> /dev/null; then
            log_error "kubectl not found. Install with:"
            echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
            echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
            exit 1
        fi
        
        # Check if docker/docker-compose is available for backups
        if ! command -v docker &> /dev/null; then
            log_warning "Docker not found - backup phase may not work"
        fi
        
        # Check multipass VM access if that's where K8s is running
        if command -v multipass &> /dev/null; then
            if multipass list | grep -q "k8s-master.*Running"; then
                log_info "✅ Multipass k8s-master VM detected and running"
                
                # Check if we can access kubectl through the VM
                if ! kubectl cluster-info &> /dev/null; then
                    log_warning "kubectl not configured. You may need to:"
                    echo "  1. Copy kubeconfig from VM: multipass exec k8s-master -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/config"
                    echo "  2. Update server IP in kubeconfig to VM IP"
                    echo "  3. Or run migration script inside VM: multipass shell k8s-master"
                fi
            else
                log_error "k8s-master VM not found or not running"
                echo "Start with: multipass start k8s-master"
                exit 1
            fi
        fi
    else
        log_info "Running locally (not over SSH)"
    fi
}

# Phase 0: Pre-Migration Backup
phase0_backup() {
    log_info "=== PHASE 0: Pre-Migration Backup ==="
    
    # Create backup directory
    BACKUP_DIR="$HOME/k8s-migration-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cd "$BACKUP_DIR"
    log_success "Created backup directory: $BACKUP_DIR"
    
    # Backup Docker volumes
    log_info "Backing up Docker volumes..."
    
    # PostgreSQL (CRITICAL)
    if [[ -d "/root/containers/postgresql/data" ]]; then
        sudo tar -czf postgresql-data-backup.tar.gz -C /root/containers/postgresql/data . 2>/dev/null || {
            log_warning "PostgreSQL backup failed - directory may not exist or permission issue"
        }
    fi
    
    # Gitea (CRITICAL)  
    if [[ -d "/root/containers/gitea/data" ]]; then
        sudo tar -czf gitea-data-backup.tar.gz -C /root/containers/gitea/data . 2>/dev/null || {
            log_warning "Gitea backup failed - directory may not exist or permission issue"
        }
    fi
    
    # Other services
    for service in pgadmin filebrowser uptime-kuma memos; do
        if [[ -d "/root/containers/$service" ]]; then
            sudo tar -czf "${service}-backup.tar.gz" -C "/root/containers/$service" . 2>/dev/null || {
                log_warning "$service backup failed - directory may not exist"
            }
        fi
    done
    
    # List created backups
    log_info "Created backups:"
    ls -lah *.tar.gz 2>/dev/null || log_warning "No backup files found"
    
    log_success "Phase 0 completed. Backup directory: $BACKUP_DIR"
    echo "BACKUP_DIR=$BACKUP_DIR" > ~/.k8s-migration-env
}

# Phase 1: Infrastructure Setup
phase1_infrastructure() {
    log_info "=== PHASE 1: Infrastructure Setup ==="
    
    # Check kubectl connectivity
    kubectl cluster-info >/dev/null 2>&1 || {
        log_error "kubectl not configured or cluster not accessible"
        exit 1
    }
    
    # Apply namespace
    log_info "Creating namespace..."
    kubectl apply -f k8s/namespace/namespace.yaml
    
    # Apply configmap
    log_info "Creating configmap..."
    kubectl apply -f k8s/namespace/configmap.yaml
    
    # Check if secrets need to be updated
    if grep -q "changeme" k8s/namespace/secrets.yaml; then
        log_warning "⚠️  Secrets file contains placeholder values!"
        log_warning "Edit k8s/namespace/secrets.yaml with real base64-encoded values before continuing"
        echo "Example commands to encode secrets:"
        echo "  echo -n 'your_postgres_password' | base64"
        echo "  echo -n 'your_gitea_password' | base64"
        echo ""
        read -p "Press Enter after updating secrets file to continue..."
    fi
    
    # Apply secrets
    log_info "Creating secrets..."
    kubectl apply -f k8s/namespace/secrets.yaml
    
    # Verify resources
    kubectl get namespaces | grep base-infrastructure >/dev/null && log_success "Namespace created"
    kubectl get secrets -n base-infrastructure | grep app-secrets >/dev/null && log_success "Secrets created"
    kubectl get configmap -n base-infrastructure >/dev/null && log_success "ConfigMap created"
    
    log_success "Phase 1 completed"
}

# Phase 2: PostgreSQL Deployment
phase2_postgresql() {
    log_info "=== PHASE 2: PostgreSQL Deployment ==="
    
    # Deploy PostgreSQL
    log_info "Deploying PostgreSQL..."
    kubectl apply -f k8s/postgresql/postgresql-statefulset.yaml
    kubectl apply -f k8s/postgresql/postgresql-service.yaml
    
    # Wait for PostgreSQL to be ready
    log_info "Waiting for PostgreSQL to be ready (up to 5 minutes)..."
    if kubectl wait --for=condition=ready pod -l app=postgresql -n base-infrastructure --timeout=300s; then
        log_success "PostgreSQL is ready"
    else
        log_error "PostgreSQL failed to start within timeout"
        kubectl logs -n base-infrastructure -l app=postgresql --tail=20
        return 1
    fi
    
    # Test PostgreSQL connection
    log_info "Testing PostgreSQL connection..."
    if kubectl exec -n base-infrastructure postgresql-0 -- pg_isready -U postgres >/dev/null 2>&1; then
        log_success "PostgreSQL connection test passed"
    else
        log_error "PostgreSQL connection test failed"
        return 1
    fi
    
    log_success "Phase 2 completed"
}

# Phase 3: Data Migration
phase3_data_migration() {
    log_info "=== PHASE 3: Data Migration ==="
    
    # Load backup directory
    if [[ -f ~/.k8s-migration-env ]]; then
        source ~/.k8s-migration-env
    else
        log_error "Backup directory not found. Run phase0 first."
        return 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory $BACKUP_DIR does not exist"
        return 1
    fi
    
    cd "$BACKUP_DIR"
    
    # Migrate PostgreSQL data (if backup exists)
    if [[ -f "postgresql-data-backup.tar.gz" ]]; then
        log_info "Migrating PostgreSQL data..."
        kubectl cp postgresql-data-backup.tar.gz base-infrastructure/postgresql-0:/tmp/ || {
            log_error "Failed to copy PostgreSQL backup to pod"
            return 1
        }
        
        # Note: This will replace existing data in the pod
        log_warning "This will replace any existing PostgreSQL data in the pod"
        read -p "Continue with PostgreSQL data migration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl exec -n base-infrastructure postgresql-0 -- bash -c "
                cd /var/lib/postgresql/data &&
                rm -rf * &&
                tar -xzf /tmp/postgresql-data-backup.tar.gz &&
                chown -R postgres:postgres .
            " || {
                log_error "PostgreSQL data migration failed"
                return 1
            }
            
            # Restart PostgreSQL to pick up data
            kubectl delete pod postgresql-0 -n base-infrastructure
            kubectl wait --for=condition=ready pod -l app=postgresql -n base-infrastructure --timeout=300s
            log_success "PostgreSQL data migrated and restarted"
        fi
    else
        log_warning "No PostgreSQL backup found, skipping data migration"
    fi
    
    log_success "Phase 3 completed"
}

# Phase 4: Services Deployment  
phase4_services() {
    log_info "=== PHASE 4: Services Deployment ==="
    
    # Deploy services that depend on PostgreSQL
    log_info "Deploying Gitea..."
    kubectl apply -f k8s/gitea/gitea-deployment.yaml
    
    log_info "Deploying Umami..."
    kubectl apply -f k8s/umami/umami-deployment.yaml
    
    # Deploy other services
    log_info "Deploying other services..."
    kubectl apply -f k8s/memos/memos-deployment.yaml
    kubectl apply -f k8s/uptime-kuma/uptime-kuma-deployment.yaml  
    kubectl apply -f k8s/dozzle/dozzle-deployment.yaml
    kubectl apply -f k8s/filestash/filestash-deployment.yaml
    
    # Wait for services to be ready
    services=("gitea" "umami" "memos" "uptime-kuma" "dozzle")
    
    for service in "${services[@]}"; do
        log_info "Waiting for $service to be ready..."
        if kubectl wait --for=condition=ready pod -l app=$service -n base-infrastructure --timeout=300s 2>/dev/null; then
            log_success "$service is ready"
        else
            log_warning "$service failed to start within timeout (may not exist or different label)"
            kubectl get pods -n base-infrastructure -l app=$service
        fi
    done
    
    log_success "Phase 4 completed"
}

# Phase 5: Ingress & Networking
phase5_networking() {
    log_info "=== PHASE 5: Ingress & Networking ==="
    
    # Check if ingress controller is running
    if ! kubectl get pods -n ingress-nginx | grep -q "Running"; then
        log_warning "Ingress controller not found or not running"
        log_info "Install ingress controller with:"
        echo "kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml"
        read -p "Press Enter after installing ingress controller..."
    fi
    
    # Apply ingress rules
    log_info "Applying ingress rules..."
    kubectl apply -f k8s/ingress/ingress.yaml
    
    # Show ingress status
    kubectl get ingress -n base-infrastructure
    
    log_success "Phase 5 completed"
}

# Phase 6: Verification
phase6_verification() {
    log_info "=== PHASE 6: Verification ==="
    
    # Check all pods
    log_info "Checking pod status..."
    kubectl get pods -n base-infrastructure
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n base-infrastructure
    
    # Check ingress
    log_info "Checking ingress..."
    kubectl get ingress -n base-infrastructure
    
    # Test database connectivity
    log_info "Testing database connectivity..."
    if kubectl exec -n base-infrastructure postgresql-0 -- psql -U postgres -c '\l' >/dev/null 2>&1; then
        log_success "Database connectivity test passed"
    else
        log_error "Database connectivity test failed"
    fi
    
    # Count running pods
    running_pods=$(kubectl get pods -n base-infrastructure --no-headers | grep "Running" | wc -l)
    total_pods=$(kubectl get pods -n base-infrastructure --no-headers | wc -l)
    
    log_info "Pod status: $running_pods/$total_pods running"
    
    if [[ $running_pods -eq $total_pods ]] && [[ $total_pods -gt 0 ]]; then
        log_success "All pods are running!"
    else
        log_warning "Not all pods are running. Check logs:"
        kubectl get pods -n base-infrastructure | grep -v "Running"
    fi
    
    log_success "Phase 6 completed"
}

# Phase 7: Docker Cleanup (DANGEROUS)
phase7_cleanup() {
    log_warning "=== PHASE 7: Docker Cleanup (DANGEROUS) ==="
    log_warning "This will stop and remove Docker Compose services"
    log_warning "Only proceed if Kubernetes migration is fully verified!"
    
    read -p "Are you absolutely sure you want to proceed with Docker cleanup? (type 'yes'): " confirm
    if [[ $confirm != "yes" ]]; then
        log_info "Docker cleanup cancelled"
        return 0
    fi
    
    # Stop Docker Compose services
    services_dirs=("caddy" "postgresql" "gitea" "umami" "memos" "uptime-kuma" "dozzle" "filebrowser")
    
    for service_dir in "${services_dirs[@]}"; do
        if [[ -d "$service_dir" ]] && [[ -f "$service_dir/docker-compose.yaml" || -f "$service_dir/docker-compose.yml" ]]; then
            log_info "Stopping $service_dir..."
            (cd "$service_dir" && docker-compose down 2>/dev/null) || log_warning "Failed to stop $service_dir"
        fi
    done
    
    # Clean up Docker resources
    log_info "Cleaning up Docker containers..."
    docker container prune -f 2>/dev/null || log_warning "Container cleanup failed"
    
    log_info "Cleaning up Docker images..."
    docker image prune -f 2>/dev/null || log_warning "Image cleanup failed"
    
    log_info "Cleaning up Docker networks..."
    docker network prune -f 2>/dev/null || log_warning "Network cleanup failed"
    
    log_warning "Docker volumes NOT cleaned up for safety"
    log_info "To clean volumes manually: docker volume prune -f"
    
    log_success "Phase 7 completed"
}

# Status check function
status_check() {
    log_info "=== Kubernetes Cluster Status ==="
    
    echo "Cluster Info:"
    kubectl cluster-info
    
    echo -e "\nNamespace Resources:"
    kubectl get all -n base-infrastructure
    
    echo -e "\nPod Details:"
    kubectl get pods -n base-infrastructure -o wide
    
    echo -e "\nIngress Status:"  
    kubectl get ingress -n base-infrastructure
    
    echo -e "\nPersistent Volumes:"
    kubectl get pv,pvc -n base-infrastructure
}

# Port forward for testing
port_forward_test() {
    log_info "=== Port Forward Test ==="
    log_info "Starting port forwards for testing..."
    
    # Kill any existing port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Start port forwards in background
    kubectl port-forward -n base-infrastructure svc/gitea 3000:3000 &
    kubectl port-forward -n base-infrastructure svc/umami 3001:3000 &
    kubectl port-forward -n base-infrastructure svc/postgresql 5432:5432 &
    
    log_success "Port forwards started:"
    echo "  Gitea: http://localhost:3000"
    echo "  Umami: http://localhost:3001"  
    echo "  PostgreSQL: localhost:5432"
    echo ""
    echo "Press Ctrl+C to stop port forwards"
    
    # Wait for interrupt
    trap 'pkill -f "kubectl port-forward"; log_info "Port forwards stopped"' INT
    wait
}

# Help function
show_help() {
    echo "Docker Compose to Kubernetes Migration Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  phase0     - Create backups of Docker volumes"
    echo "  phase1     - Set up Kubernetes infrastructure (namespace, secrets)"
    echo "  phase2     - Deploy PostgreSQL"
    echo "  phase3     - Migrate data from Docker to Kubernetes"
    echo "  phase4     - Deploy application services"
    echo "  phase5     - Set up ingress and networking"
    echo "  phase6     - Verify deployment"
    echo "  phase7     - Clean up Docker resources (DANGEROUS)"
    echo "  status     - Show cluster status"
    echo "  test       - Start port forwards for testing"
    echo "  help       - Show this help"
    echo ""
    echo "Run phases in order. Each phase should complete successfully before proceeding."
    echo ""
    echo "Example workflow:"
    echo "  $0 phase0   # Backup"
    echo "  $0 phase1   # Infrastructure" 
    echo "  $0 phase2   # PostgreSQL"
    echo "  $0 phase3   # Data migration"
    echo "  $0 phase4   # Services"
    echo "  $0 phase5   # Networking"
    echo "  $0 phase6   # Verification"
    echo "  $0 test     # Test access"
    echo "  $0 phase7   # Cleanup (only when satisfied)"
}

# Main execution
main() {
    check_directory
    check_ssh_environment
    
    case "${1:-help}" in
        "phase0"|"backup")
            phase0_backup
            ;;
        "phase1"|"infrastructure")
            phase1_infrastructure
            ;;
        "phase2"|"postgresql")
            phase2_postgresql
            ;;
        "phase3"|"data")
            phase3_data_migration
            ;;
        "phase4"|"services")
            phase4_services
            ;;
        "phase5"|"networking")
            phase5_networking
            ;;
        "phase6"|"verify")
            phase6_verification
            ;;
        "phase7"|"cleanup")
            phase7_cleanup
            ;;
        "status")
            status_check
            ;;
        "test"|"port-forward")
            port_forward_test
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi