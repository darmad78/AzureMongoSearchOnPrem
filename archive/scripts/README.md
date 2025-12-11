# Archived Scripts

This directory contains scripts that are **not part of the standard Phase 1-5 deployment workflow**. These scripts have been archived to keep the root directory clean and focused on the primary deployment method.

## Why These Scripts Are Archived

The standard deployment workflow uses these scripts in order:
1. `deploy-phase1-ops-manager.sh` - Deploy Ops Manager
2. `deploy-phase2-mongodb-enterprise.sh` - Deploy MongoDB Enterprise
3. `deploy-phase3-mongodb-search.sh` - Deploy MongoDB Search
4. `deploy-phase4-ai-models.sh` - Deploy AI Models (Ollama)
5. `deploy-phase5-backend-frontend.sh` - Deploy Backend & Frontend

The scripts in this archive are:
- **Alternative deployment methods** (different approaches to deployment)
- **Legacy setup scripts** (older setup methods not used by phases)
- **Utility/testing scripts** (fix scripts, test scripts, troubleshooting tools)

## Archived Scripts

### Alternative Deployment Scripts
These scripts provide alternative ways to deploy the stack, but are not the recommended approach:

- `deploy.sh` - Single executable deployment script
- `deploy-complete-stack.sh` - Complete stack deployment (alternative)
- `deploy-complete-kubernetes.sh` - Complete Kubernetes deployment (alternative)
- `deploy-enterprise-k8s.sh` - Enterprise K8s deployment (alternative)
- `deploy-enterprise-cloud-manager.sh` - Cloud manager deployment (alternative)
- `deploy-mongodb-enterprise-complete.sh` - Complete MongoDB Enterprise deployment (alternative)
- `deploy-mongodb-enterprise-complete-fixed.sh` - Fixed version of complete deployment
- `deploy-official-mongodb-search.sh` - Official MongoDB Search deployment (alternative)
- `deploy-search-only.sh` - Hybrid deployment (search nodes only for Docker Compose setups)
- `deploy-ops-manager-helm.sh` - Ops Manager Helm deployment (alternative)

### Legacy Setup Scripts
These scripts were used in older setup methods but are not part of the phase-based deployment:

- `setup-kubernetes.sh` - Legacy Kubernetes setup
- `setup-ops-manager.sh` - Legacy Ops Manager setup
- `setup-mongodb-standalone.sh` - Legacy standalone MongoDB setup

### Utility/Testing/Fix Scripts
These are utility scripts for troubleshooting, testing, and fixing issues:

- `setup-port-forward.sh` - Port forwarding utility
- `test-application.sh` - Application testing script
- `test-mongodb-data.sh` - MongoDB data testing script
- `fix-ollama-model.sh` - Fix script for Ollama model issues
- `fix-ollama-memory.sh` - Fix script for Ollama memory issues
- `fix-gcp-firewall-mongodb.sh` - Fix script for GCP firewall issues
- `fix-mongodb-firewall.sh` - Fix script for MongoDB firewall issues
- `troubleshoot-mongodb-connection.sh` - MongoDB connection troubleshooting
- `flush_unusaed.sh` - Utility script for cleanup

## Using Archived Scripts

If you need to use any of these archived scripts:

1. Copy the script back to the root directory, or
2. Run it directly from this directory: `./archive/scripts/script-name.sh`

**Note:** These scripts may not be maintained or tested as regularly as the phase-based deployment scripts. Use at your own discretion.

## Recommended Approach

For new deployments, use the phase-based approach:
```bash
./deploy-phase1-ops-manager.sh
./deploy-phase2-mongodb-enterprise.sh
./deploy-phase3-mongodb-search.sh
./deploy-phase4-ai-models.sh
./deploy-phase5-backend-frontend.sh
```

This ensures consistency and easier troubleshooting.

