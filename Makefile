# Kubernetes Infrastructure Management Makefile
# Usage: make deploy SERVER=your.server.ip
# Server IP must be provided as argument

SERVER ?= $(error SERVER is required. Usage: make deploy SERVER=your.server.ip)
REPO_DIR = ~/base_infrastructure

.PHONY: help deploy-prep deploy cleanup sync-only status logs

help: ## Show available commands
	@echo "Kubernetes Infrastructure Management"
	@echo "Usage: make <target> SERVER=<ip-address>"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Examples:"
	@echo "  make deploy SERVER=your.server.ip"
	@echo "  make cleanup SERVER=your.server.ip"
	@echo "  make sync-only SERVER=192.168.1.100"

deploy-prep: ## Prepare server for deployment (sync code + secrets)
	@echo "🚀 Preparing server deployment to $(SERVER)..."
	@git push origin master
	@ssh root@$(SERVER) "cd $(REPO_DIR) && git stash push -m 'Auto-stash $$(date)' 2>/dev/null || true && git pull origin master"
	@scp secrets-actual.yaml root@$(SERVER):$(REPO_DIR)/k8s/namespace/secrets.yaml
	@ssh root@$(SERVER) "cd $(REPO_DIR) && chmod +x *.sh"
	@echo "✅ Server prepared for deployment"

deploy: deploy-prep ## Full deployment: sync + secrets + deploy
	@echo "🚀 Starting deployment on $(SERVER)..."
	@ssh -t root@$(SERVER) "cd $(REPO_DIR) && ./deploy.sh"

cleanup: ## Clean up infrastructure on server
	@echo "🧹 Cleaning up infrastructure on $(SERVER)..."
	@ssh -t root@$(SERVER) "cd $(REPO_DIR) && ./cleanup.sh"

sync-only: ## Sync code only (no secrets, no deployment)
	@echo "🔄 Syncing code to $(SERVER)..."
	@git push origin master
	@ssh root@$(SERVER) "cd $(REPO_DIR) && git stash push -m 'Auto-stash $$(date)' 2>/dev/null || true && git pull origin master"
	@ssh root@$(SERVER) "cd $(REPO_DIR) && chmod +x *.sh"
	@echo "✅ Code synced"

secrets: ## Copy secrets to server only
	@echo "🔐 Copying secrets to $(SERVER)..."
	@scp secrets-actual.yaml root@$(SERVER):$(REPO_DIR)/k8s/namespace/secrets.yaml
	@echo "✅ Secrets copied"

status: ## Check infrastructure status on server
	@echo "📊 Checking infrastructure status on $(SERVER)..."
	@ssh root@$(SERVER) "cd $(REPO_DIR) && KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n base-infra"

logs: ## Show logs for a service (specify SERVICE=service-name)
	@echo "📋 Showing logs for $(SERVICE) on $(SERVER)..."
	@ssh -t root@$(SERVER) "cd $(REPO_DIR) && KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -f deployment/$(SERVICE) -n base-infra"

update: deploy-prep ## Update specific service configuration (specify SERVICE=service-name)
	@echo "🔄 Updating $(SERVICE) on $(SERVER)..."
	@ssh root@$(SERVER) "cd $(REPO_DIR) && KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f k8s/$(SERVICE)/ --validate=false"
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart deployment/$(SERVICE) -n base-infra"
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n base-infra | grep $(SERVICE)"
	@echo "✅ $(SERVICE) updated and restarted"

restart: ## Restart a service (specify SERVICE=service-name)
	@echo "🔄 Restarting $(SERVICE) on $(SERVER)..."
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart deployment/$(SERVICE) -n base-infra"
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n base-infra | grep $(SERVICE)"
	@echo "✅ $(SERVICE) restarted"

apply-all: deploy-prep ## Apply all k8s configurations without full deploy
	@echo "📦 Applying all configurations on $(SERVER)..."
	@ssh root@$(SERVER) "cd $(REPO_DIR) && KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -R -f k8s/ --validate=false"
	@echo "✅ All configurations applied"

exec: ## Execute command in pod (specify SERVICE=service-name CMD="command")
	@echo "💻 Executing command in $(SERVICE) pod..."
	@ssh -t root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -it deployment/$(SERVICE) -n base-infra -- $(CMD)"

restart-all: ## Restart all services
	@echo "🔄 Restarting all services on $(SERVER)..."
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart deployments --all -n base-infra"
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart statefulsets --all -n base-infra"
	@echo "⏳ Waiting for services to be ready..."
	@sleep 5
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n base-infra"
	@echo "✅ All services restarted"

update-all: deploy-prep ## Update and restart all services
	@echo "🔄 Updating all services on $(SERVER)..."
	@ssh root@$(SERVER) "cd $(REPO_DIR) && KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -R -f k8s/ --validate=false"
	@echo "🔄 Restarting all services..."
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart deployments --all -n base-infra"
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart statefulsets --all -n base-infra"
	@echo "⏳ Waiting for services to be ready..."
	@sleep 5
	@ssh root@$(SERVER) "KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n base-infra"
	@echo "✅ All services updated and restarted"