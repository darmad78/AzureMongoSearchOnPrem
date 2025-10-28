#!/bin/bash
set -e

# Phase 3: Deploy MongoDB Search
# This deploys MongoDB Search (mongot) with the MongoDB Enterprise replica set

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
║                Phase 3: MongoDB Search Setup               ║
║              Deploy MongoDB Search (mongot)                ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
MDB_RESOURCE_NAME="mdb-rs"

# Step 1: Verify MongoDB is Ready
log_step "Step 1: Verifying MongoDB is Ready"
log_info "Checking MongoDB Enterprise status..."

MONGODB_STATUS=$(kubectl get mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}')
if [ "$MONGODB_STATUS" != "Running" ]; then
    log_error "MongoDB is not in Running state. Current status: $MONGODB_STATUS"
    log_info "Please ensure Phase 2 completed successfully before running Phase 3"
    exit 1
fi

log_success "MongoDB Enterprise is running and ready"

# Step 2: Deploy MongoDB Search
log_step "Step 2: Deploying MongoDB Search"
log_info "Deploying MongoDB Search (mongot) with proper resource requirements..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  resourceRequirements:
    limits:
      cpu: "3"
      memory: 5Gi
    requests:
      cpu: "2"
      memory: 3Gi
EOF

log_info "Waiting for MongoDBSearch resource to reach Running phase..."
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdbs/${MDB_RESOURCE_NAME}" -n ${NAMESPACE} --timeout=300s

log_success "MongoDB Search deployed and running"

# Step 3: Verify Complete Stack
log_step "Step 3: Verifying Complete Stack"
log_info "Checking all components status..."

echo "MongoDB Enterprise:"
kubectl get "mdb/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "MongoDB Search:"
kubectl get "mdbs/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "All Pods:"
kubectl get pods -n ${NAMESPACE}
echo ""
echo "Ops Manager Pods:"
kubectl get pods -n ops-manager
echo ""

# Step 4: Get Access Information
log_step "Step 4: Access Information"
VM_IP=$(hostname -I | awk '{print $1}')
OPS_MANAGER_PORT=$(kubectl get svc ops-manager-svc -n ops-manager -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "8080")
MONGODB_PORT=$(kubectl get svc mongodb-rs-svc -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "27017")

echo "🎉 Complete MongoDB Enterprise Stack is Deployed!"
echo ""
echo "📊 Deployment Summary:"
echo "   ✅ MongoDB Enterprise: 3-node replica set"
echo "   ✅ MongoDB Search (mongot): Vector search enabled"
echo "   ✅ Ops Manager: Monitoring & management"
echo "   ✅ All users created with proper roles"
echo ""
echo "🔗 Access Information:"
echo "   Ops Manager: http://${VM_IP}:${OPS_MANAGER_PORT}"
echo "   MongoDB: mongodb://mdb-user:mdb-user-password-CHANGE-ME@${VM_IP}:${MONGODB_PORT}/sample_mflix?replicaSet=${MDB_RESOURCE_NAME}&authSource=admin"
echo ""
echo "📋 Useful Commands:"
echo "   # Check all pods"
echo "   kubectl get pods -n ${NAMESPACE}"
echo "   kubectl get pods -n ops-manager"
echo ""
echo "   # Check MongoDB status"
echo "   kubectl get mdb,mdbs -n ${NAMESPACE}"
echo ""
echo "   # View logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=mongodb-rs-svc -f"
echo "   kubectl logs -n ${NAMESPACE} -l app=mongodb-rs-search-svc -f"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it ${MDB_RESOURCE_NAME}-0 -n ${NAMESPACE} -- mongosh -u mdb-admin -p admin-user-password-CHANGE-ME --authenticationDatabase admin"
echo ""

log_success "Phase 3 complete! MongoDB Search is running."
echo ""
echo "🎯 Next Steps:"
echo "   1. Add data to your MongoDB cluster"
echo "   2. Create MongoDB Search and Vector Search indexes"
echo "   3. Run queries against your data"
echo "   4. Test vector search functionality"
echo ""
