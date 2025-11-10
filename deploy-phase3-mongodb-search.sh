#!/bin/bash

set -e

# Phase 3: Deploy MongoDB Search
# This deploys MongoDB Search (mongot) using the MongoDBSearch Custom Resource

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
║        Deploying via MongoDBSearch Custom Resource         ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
MDB_RESOURCE_NAME="mdb-rs"

# Step 0: Verify Kubernetes Operator is Installed
log_step "Step 0: Verifying Kubernetes Operator is Installed"
log_info "Checking if MongoDB Kubernetes Operator is installed..."

# Check if unified operator deployment exists
OPERATOR_DEPLOYMENT=$(kubectl get deployment mongodb-kubernetes-operator -n ${NAMESPACE} -o name 2>/dev/null || echo "")
if [ -z "${OPERATOR_DEPLOYMENT}" ]; then
    log_warning "MongoDB Kubernetes Operator (unified) not found in ${NAMESPACE} namespace."
    log_info "Checking if Helm repo is available..."
    
    # Check if Helm repo is added
    if ! helm repo list | grep -q mongodb; then
        log_info "Adding MongoDB Helm repository..."
        helm repo add mongodb https://mongodb.github.io/helm-charts >/dev/null 2>&1 || true
        helm repo update mongodb >/dev/null 2>&1 || true
    fi
    
    log_info "Installing MongoDB Kubernetes Operator (unified operator)..."
    helm upgrade --install \
        --create-namespace \
        --namespace ${NAMESPACE} \
        mongodb-kubernetes \
        mongodb/mongodb-kubernetes \
        --wait --timeout=5m
    
    log_success "MongoDB Kubernetes Operator installed"
else
    log_success "MongoDB Kubernetes Operator found"
fi

# Verify unified operator is running
log_info "Verifying unified operator is running..."
OPERATOR_READY=$(kubectl get deployment mongodb-kubernetes-operator -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "${OPERATOR_READY}" != "1" ]; then
    log_info "Operator not ready yet, waiting up to 60 seconds..."
    TIMEOUT=60
    ELAPSED=0
    while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
        OPERATOR_READY=$(kubectl get deployment mongodb-kubernetes-operator -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "${OPERATOR_READY}" = "1" ]; then
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done
    
    if [ "${OPERATOR_READY}" != "1" ]; then
        log_error "Unified operator is not ready after ${TIMEOUT}s (readyReplicas=${OPERATOR_READY})"
        log_info "Checking operator pods..."
        kubectl get pods -n ${NAMESPACE} | grep mongodb-kubernetes-operator || true
        log_info "Checking operator logs..."
        kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=mongodb-kubernetes-operator --tail=20 || true
        exit 1
    fi
fi

log_success "Unified operator is running and ready"
log_info "The unified operator watches: mongodb, opsmanagers, mongodbusers, mongodbcommunity, and mongodbsearch resources"

# Step 1: Verify MongoDB is Ready
log_step "Step 1: Verifying MongoDB is Ready"
log_info "Checking MongoDB Enterprise status..."

MONGODB_STATUS=$(kubectl get mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [ "$MONGODB_STATUS" != "Running" ]; then
    # Fallback: check StatefulSet readiness and pod readiness
    STS_READY=$(kubectl get sts ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    STS_REPLICAS=$(kubectl get sts ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

    if [ "$STS_READY" = "3" ] && [ "$STS_READY" = "$STS_REPLICAS" ]; then
        log_warning "MongoDB CR phase is '$MONGODB_STATUS' but StatefulSet reports ${STS_READY}/${STS_REPLICAS} ready. Proceeding."
    else
        log_error "MongoDB not ready (phase=$MONGODB_STATUS, sts=${STS_READY}/${STS_REPLICAS})."
        log_info "Recent events (mongodb namespace):"
        kubectl get events -n ${NAMESPACE} --sort-by=.lastTimestamp | tail -n 40 || true
        log_info "Describe MongoDB CR for details: kubectl describe mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE}"
        exit 1
    fi
fi

log_success "MongoDB Enterprise is running or pods are Ready; continuing"

# Step 2: Ensure Search Sync User and Secret
log_step "Step 2: Creating Search Sync User and Secret"
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

# Step 3: Deploy MongoDB Search (mongot) via MongoDBSearch CR
log_step "Step 3: Deploying MongoDB Search (mongot)"
log_info "Applying MongoDBSearch Custom Resource (as per the guide)..."

# This is the method from the guide.
# The Enterprise Operator will see this CR and automatically
# configure Ops Manager to deploy the 'mongot' process.
kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  # The operator will automatically link this to the MongoDB CR
  # of the same name ('${MDB_RESOURCE_NAME}') in the same namespace.
  
  # Resource values taken from the guide:
  resourceRequirements:
    limits:
      cpu: "3"
      memory: 5Gi
    requests:
      cpu: "2"
      memory: 3Gi
EOF

log_success "MongoDBSearch CR applied."
log_info "Waiting for MongoDBSearch resource to reach 'Running' phase..."

# Wait for the MongoDBSearch resource to become ready
if ! kubectl wait --for=jsonpath='{.status.phase}'=Running \
  "mdbs/${MDB_RESOURCE_NAME}" -n ${NAMESPACE} --timeout=400s; then
    log_error "MongoDBSearch failed to become ready."
    log_info "Describe the MongoDBSearch CR for details:"
    kubectl describe mdbs ${MDB_RESOURCE_NAME} -n ${NAMESPACE}
    log_info "Check operator logs:"
    kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=mongodb-kubernetes-operator --tail=50
    exit 1
fi

log_success "MongoDB Search CR is now Running."

# Step 4: Verify Complete Stack
log_step "Step 4: Verifying Complete Stack"
log_info "Checking all components status..."

echo "MongoDB Enterprise:"
kubectl get "mdb/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "MongoDB Search CR:"
kubectl get "mdbs/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "Search Pods (e.g., mdb-rs-search-0):"
kubectl get pods -n ${NAMESPACE} | grep --color=auto 'search' || echo "  No search pods yet (or still starting)."
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
echo "   ✅ MongoDB Search (mongot): Vector search enabled (via MongoDBSearch CR)"
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
echo "   # Check MongoDB and Search status"
echo "   kubectl get mdb -n ${NAMESPACE}"
echo "   kubectl get mdbs -n ${NAMESPACE}"
echo ""
echo "   # View logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=mongodb-rs-svc -f"
echo "   kubectl logs -n ${NAMESPACE} <your-search-pod-name> -f"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it ${MDB_RESOURCE_NAME}-0 -n ${NAMESPACE} -- mongosh -u mdb-admin -p admin-user-password-CHANGE-ME --authenticationDatabase admin"
echo ""

# Step 6: How to monitor (3 key commands)
log_step "Step 6: Monitoring Commands"
echo "1) Check the MongoDBSearch CR status:"
echo "   kubectl get mdbs ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -w"
echo "   # Look for: PHASE = Running"
echo ""
echo "2) Watch search pods (should be created by the operator):"
echo "   kubectl get pods -n ${NAMESPACE} -w | grep --color=auto 'search'"
echo "   # Look for: <name>-search-0  Ready 1/1  Running"
echo ""
echo "3) Check Ops Manager automation status:"
OM_CONFIG_UI=$(kubectl get configmap om-project -n ${NAMESPACE} -o jsonpath='{.data.baseUrl}' 2>/dev/null || echo "http://${VM_IP}:${OPS_MANAGER_PORT}")
echo "   # View Ops Manager UI: ${OM_CONFIG_UI}/#/deployment/view"
echo "   # Look for the search process in the deployment view"
echo ""
echo "4) Check automation agent logs (for search deployment):"
echo "   kubectl logs -n ${NAMESPACE} ${MDB_RESOURCE_NAME}-0 -c mongodb-agent --tail=50 | grep -i search"
echo "   # Look for 'search' process deployment messages"

log_success "Phase 3 complete! MongoDB Search is running."
echo ""
echo "🎯 Next Steps:"
echo "   1. Add data to your MongoDB cluster"
echo "   2. Create MongoDB Search and Vector Search indexes"
echo "   3. Run queries against your data"
echo "   4. Test vector search functionality"
echo ""
