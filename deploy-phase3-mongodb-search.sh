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

MONGODB_STATUS=$(kubectl get mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [ "$MONGODB_STATUS" != "Running" ]; then
    # Fallback: check StatefulSet readiness and pod readiness
    STS_READY=$(kubectl get sts ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    STS_REPLICAS=$(kubectl get sts ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
    PODS_READY=$(kubectl get pods -n ${NAMESPACE} -l app=mongodb-rs-svc -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{" "}{end}' | tr ' ' '\n' | grep -c '^true$' || true)

    if [ "$STS_READY" = "3" ] && [ "$STS_READY" = "$STS_REPLICAS" ]; then
        log_warning "MongoDB CR phase is '$MONGODB_STATUS' but StatefulSet reports ${STS_READY}/${STS_REPLICAS} ready. Proceeding."
    else
        log_error "MongoDB not ready (phase=$MONGODB_STATUS, sts=${STS_READY}/${STS_REPLICAS}, ready containers=${PODS_READY})."
        log_info "Recent events (mongodb namespace):"
        kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp | tail -n 40 || true
        log_info "Describe MongoDB CR for details: kubectl describe mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE}"
        exit 1
    fi
fi

log_success "MongoDB Enterprise is running or pods are Ready; continuing"

# Step 2: Ensure Search Sync User and Secret
log_step "Step 2: Creating search sync user and secret"
log_info "Creating secret for search sync user (if not exists)..."

kubectl create secret generic ${MDB_RESOURCE_NAME}-search-sync-source-password \
  -n ${NAMESPACE} \
  --from-literal=password="search-sync-user-password-CHANGE-ME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: search-sync-source-user
  namespace: ${NAMESPACE}
spec:
  username: search-sync-source
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: ${MDB_RESOURCE_NAME}-search-sync-source-password
    key: password
  roles:
  - name: searchCoordinator
    db: admin
EOF

log_success "Search sync user created"

# Step 3: Deploy MongoDB Search
log_step "Step 3: Deploying MongoDB Search"
log_info "Deploying MongoDB Search (mongot) with proper resource requirements..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  # no need to specify source.mongodbResourceRef if MongoDBSearch CR has the same name as MongoDB CR
  # the operator infer it automatically
  resourceRequirements:
    limits:
      cpu: "3"
      memory: 5Gi
    requests:
      cpu: "2"
      memory: 3Gi
EOF

log_info "Waiting for MongoDBSearch resource to reach Running phase..."
# Using mdbs/ (plural) as per MongoDB guide
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdbs/${MDB_RESOURCE_NAME}" -n ${NAMESPACE} --timeout=300s

log_success "MongoDB Search deployed and running"

# Step 4: Verify Complete Stack
log_step "Step 4: Verifying Complete Stack"
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

# Step 5: Get Access Information
log_step "Step 5: Access Information"
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

# Step 6: How to monitor (3 key commands)
log_step "Step 6: Monitoring Commands"
echo "1) Watch CR status (phase should become Running):"
echo "   kubectl get mdbs/${MDB_RESOURCE_NAME} -n ${NAMESPACE} -w"
echo "   # Look for: PHASE=Running"
echo ""
echo "2) Watch pods readiness (containers should be 1/1 Ready):"
echo "   kubectl get pods -n ${NAMESPACE} -w"
echo "   # Look for: mdb-rs-search-<n> pods Ready 1/1"
echo ""
echo "3) Enterprise Operator logs (check for reconcile errors):"
echo "   kubectl logs -n mongodb-enterprise-operator deploy/mongodb-enterprise-operator -f --tail=200"
echo "   # Look for: no errors, successful reconcile for MongoDBSearch"

log_success "Phase 3 complete! MongoDB Search is running."
echo ""
echo "🎯 Next Steps:"
echo "   1. Add data to your MongoDB cluster"
echo "   2. Create MongoDB Search and Vector Search indexes"
echo "   3. Run queries against your data"
echo "   4. Test vector search functionality"
echo ""
