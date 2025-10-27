#!/bin/bash
set -e

# MongoDB Ops Manager Installation on Kubernetes with Helm
# Based on official MongoDB Helm charts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "\n${BLUE}🚀 $1${NC}\n=================================================="; }

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              MongoDB Ops Manager Installation                ║
║                    Using Helm Charts                        ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-ops-manager}"
RELEASE_NAME="${RELEASE_NAME:-ops-manager}"

log_info "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  Release Name: ${RELEASE_NAME}"
echo ""

# Step 1: Clean existing deployment
log_step "Step 1: Cleaning Existing Resources"
log_info "Removing old Ops Manager deployment..."
helm uninstall ${RELEASE_NAME} -n ${NAMESPACE} 2>/dev/null || true
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --wait=true 2>/dev/null || true
sleep 5
log_success "Cleanup complete"

# Step 2: Add MongoDB Helm Repository
log_step "Step 2: Adding MongoDB Helm Repository"
log_info "Adding MongoDB Helm repository..."
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update
log_success "MongoDB Helm repository added and updated"

# Step 3: Create Namespace
log_step "Step 3: Creating Namespace"
kubectl create namespace ${NAMESPACE}
log_success "Namespace '${NAMESPACE}' created"

# Step 4: Create values.yaml
log_step "Step 4: Creating Ops Manager Configuration"

cat > ops-manager-values.yaml << EOF
# Ops Manager Configuration
operator:
  version: 2.3.2

appDb:
  # Application Database settings
  storageSize: 50Gi
  storageClass: standard
  cpu:
    limits: "1000m"
    requests: "500m"
  memory:
    limits: "4Gi"
    requests: "2Gi"

opsManager:
  # Ops Manager settings
  replicas: 1
  version: 8.0.15
  cpu:
    limits: "1000m"
    requests: "500m"
  memory:
    limits: "4Gi"
    requests: "2Gi"

# Service configuration
service:
  type: LoadBalancer
  port: 8080
  targetPort: 8080

# Backup Daemon (optional)
backupDaemon:
  enabled: false

# Monitoring
monitoring:
  enabled: true

# Security
security:
  tls:
    enabled: false
EOF

log_success "Configuration file created: ops-manager-values.yaml"

# Step 5: Install Ops Manager with Helm
log_step "Step 5: Installing Ops Manager with Helm"
log_info "Installing Ops Manager (this may take 5-10 minutes)..."

helm install ${RELEASE_NAME} mongodb/ops-manager \
  -n ${NAMESPACE} \
  -f ops-manager-values.yaml \
  --wait --timeout=15m

log_success "Ops Manager installed"

# Step 6: Verify Installation
log_step "Step 6: Verifying Installation"
log_info "Checking pods status..."
kubectl get pods -n ${NAMESPACE}

log_info "Checking services..."
kubectl get svc -n ${NAMESPACE}

log_info "Checking persistent volume claims..."
kubectl get pvc -n ${NAMESPACE}

log_info "Waiting for Ops Manager to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ops-manager -n ${NAMESPACE} --timeout=600s || log_warning "Ops Manager may still be starting..."

log_success "Installation verification complete"

# Step 7: Get Access Information
log_step "Step 7: Access Information"

log_info "Getting service information..."
kubectl get svc ${RELEASE_NAME} -n ${NAMESPACE}

echo ""
echo -e "${GREEN}🎉 Ops Manager Installation Complete!${NC}"
echo ""
echo "📊 Installation Summary:"
echo "   Namespace: ${NAMESPACE}"
echo "   Release: ${RELEASE_NAME}"
echo ""

echo "🔗 Access Ops Manager:"
echo ""
echo "   Option 1 - External IP (if LoadBalancer available):"
echo "   kubectl get svc ${RELEASE_NAME} -n ${NAMESPACE}"
echo "   Then access: http://<EXTERNAL-IP>:8080"
echo ""
echo "   Option 2 - Port Forward (recommended for testing):"
echo "   kubectl port-forward svc/${RELEASE_NAME} 8080:8080 -n ${NAMESPACE}"
echo "   Then access: http://localhost:8080"
echo ""

echo "📋 Useful Commands:"
echo "   # Check all resources"
echo "   kubectl get all -n ${NAMESPACE}"
echo ""
echo "   # View Ops Manager logs"
echo "   kubectl logs -f deployment/${RELEASE_NAME} -n ${NAMESPACE}"
echo ""
echo "   # View App DB logs"
echo "   kubectl logs -f statefulset/${RELEASE_NAME}-appdb -n ${NAMESPACE}"
echo ""
echo "   # Update Helm release"
echo "   helm upgrade ${RELEASE_NAME} mongodb/ops-manager -n ${NAMESPACE} -f ops-manager-values.yaml"
echo ""
echo "   # Uninstall"
echo "   helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "   kubectl delete namespace ${NAMESPACE}"
echo ""

echo "🎯 Next Steps:"
echo "   1. Access Ops Manager UI"
echo "   2. Create organization and project"
echo "   3. Generate API keys"
echo "   4. Update MongoDB deployment to use Ops Manager"
echo ""

log_success "Ops Manager deployment script completed successfully!"
