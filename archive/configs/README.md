# Archived Configuration Files

This directory contains Kubernetes YAML configuration files that are **not used by the phase-based deployment scripts**.

## Why These Files Are Archived

The phase-based deployment scripts (deploy-phase1 through deploy-phase5) use **inline YAML** definitions within the scripts themselves (via `kubectl apply -f - <<EOF`). This approach:
- Keeps everything self-contained in the deployment scripts
- Reduces file dependencies
- Makes the deployment process more straightforward

These archived YAML files were used by alternative deployment scripts that have also been archived.

## Archived Configuration Files

### Application Configuration
- `backend-frontend-config.yaml` - Backend and frontend deployment configuration (used by archived deploy-complete-stack.sh)
- `ollama-config.yaml` - Ollama LLM service configuration (used by archived deploy-complete-stack.sh)

### MongoDB Configuration
- `mongodb-enterprise-replica-set.yaml` - MongoDB Enterprise replica set configuration
- `mongodb-search-config.yaml` - MongoDB Search (mongot) configuration
- `mongodb-users-config.yaml` - MongoDB users and roles configuration
- `ops-manager-config.yaml` - Ops Manager configuration (used by archived deploy-complete-stack.sh)
- `temp_mongodb_search.yaml` - Temporary MongoDB Search configuration file

## Using These Files

If you need to use these configuration files:

1. **For reference**: These files can serve as examples of Kubernetes resource definitions
2. **For alternative deployments**: If using archived deployment scripts, copy these files back to the root directory
3. **For customization**: You can use these as templates and modify them for your needs

## Current Deployment Method

The current phase-based deployment uses inline YAML definitions. To see the actual configurations being deployed, check the phase scripts:
- `deploy-phase1-ops-manager.sh` - Ops Manager configuration
- `deploy-phase2-mongodb-enterprise.sh` - MongoDB Enterprise configuration
- `deploy-phase3-mongodb-search.sh` - MongoDB Search configuration
- `deploy-phase4-ai-models.sh` - Ollama configuration
- `deploy-phase5-backend-frontend.sh` - Backend and frontend configuration

