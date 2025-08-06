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
	@ssh root@$(SERVER) "cd $(REPO_DIR) && kubectl get pods -n base-infra"

logs: ## Show logs for a service (specify SERVICE=service-name)
	@echo "📋 Showing logs for $(SERVICE) on $(SERVER)..."
	@ssh -t root@$(SERVER) "cd $(REPO_DIR) && kubectl logs -f deployment/$(SERVICE) -n base-infra"