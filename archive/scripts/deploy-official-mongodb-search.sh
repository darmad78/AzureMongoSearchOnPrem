#!/bin/bash
set -e

# MongoDB Enterprise Search Deployment - Official Guide
# Based on: https://www.mongodb.com/docs/kubernetes/operator/search/

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
║        MongoDB Enterprise Search - Official Guide          ║
║              Kubernetes Operator Deployment                ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Step 1: Set Environment Variables
log_step "Step 1: Setting Environment Variables"
log_info "Setting up environment variables for MongoDB Search deployment..."

# Set environment variables
export K8S_CTX="kind-mongodb-cluster"
export MDB_NS="mongodb"
export MDB_RESOURCE_NAME="mdb-rs"
export OPS_MANAGER_PROJECT_NAME="mongodb-search-project"
export OPS_MANAGER_API_URL="https://cloud-qa.mongodb.com"
export OPS_MANAGER_API_USER="your-api-user"
export OPS_MANAGER_API_KEY="your-api-key"
export OPS_MANAGER_ORG_ID="your-org-id"
export MDB_VERSION="8.2.0-ent"
export MDB_ADMIN_USER_PASSWORD="admin-user-password-CHANGE-ME"
export MDB_USER_PASSWORD="mdb-user-password-CHANGE-ME"
export MDB_SEARCH_SYNC_USER_PASSWORD="search-sync-user-password-CHANGE-ME"
export OPERATOR_HELM_CHART="mongodb/mongodb-kubernetes"
export OPERATOR_ADDITIONAL_HELM_VALUES=""
export MDB_CONNECTION_STRING="mongodb://mdb-user:${MDB_USER_PASSWORD}@${MDB_RESOURCE_NAME}-svc.${MDB_NS}.svc.cluster.local:27017/?replicaSet=${MDB_RESOURCE_NAME}"

log_success "Environment variables set"

# Step 2: Add MongoDB Helm Repository
log_step "Step 2: Adding MongoDB Helm Repository"
log_info "Adding MongoDB Helm repository..."

helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update mongodb
helm search repo mongodb/mongodb-kubernetes

log_success "MongoDB Helm repository added"

# Step 3: Install MongoDB Kubernetes Operator
log_step "Step 3: Installing MongoDB Kubernetes Operator"
log_info "Installing MongoDB Kubernetes Operator..."

helm upgrade --install --debug --kube-context "${K8S_CTX}" \
  --create-namespace \
  --namespace="${MDB_NS}" \
  mongodb-kubernetes \
  ${OPERATOR_ADDITIONAL_HELM_VALUES:+--set ${OPERATOR_ADDITIONAL_HELM_VALUES}} \
  "${OPERATOR_HELM_CHART}"

log_success "MongoDB Kubernetes Operator installed"

# Step 4: Create Ops Manager Configuration
log_step "Step 4: Creating Ops Manager Configuration"
log_info "Creating Ops Manager configuration..."

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: ${MDB_NS}
data:
  projectName: "${OPS_MANAGER_PROJECT_NAME}"
  orgId: "${OPS_MANAGER_ORG_ID}"
  baseUrl: "${OPS_MANAGER_API_URL}"
---
apiVersion: v1
kind: Secret
metadata:
  name: om-credentials
  namespace: ${MDB_NS}
type: Opaque
stringData:
  publicKey: "${OPS_MANAGER_API_KEY}"
  privateKey: "${OPS_MANAGER_API_KEY}"
EOF

log_success "Ops Manager configuration created"

# Step 5: Deploy MongoDB Enterprise
log_step "Step 5: Deploying MongoDB Enterprise"
log_info "Deploying MongoDB Enterprise replica set..."

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: ${MDB_RESOURCE_NAME}
spec:
  members: 3
  version: ${MDB_VERSION}
  type: ReplicaSet
  opsManager:
    configMapRef:
      name: om-project
  credentials: om-credentials
  security:
    authentication:
      enabled: true
      ignoreUnknownUsers: true
      modes:
      - SCRAM
  agent:
    logLevel: INFO
  podSpec:
    podTemplate:
      spec:
        containers:
        - name: mongodb-enterprise-database
          resources:
            limits:
              cpu: "2"
              memory: 2Gi
            requests:
              cpu: "1"
              memory: 1Gi
EOF

log_info "Waiting for MongoDB resource to reach Running phase..."
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" wait --for=jsonpath='{.status.phase}'=Running "mdb/${MDB_RESOURCE_NAME}" --timeout=400s

log_success "MongoDB Enterprise deployed and running"

# Step 6: Create MongoDB User Secrets
log_step "Step 6: Creating MongoDB User Secrets"
log_info "Creating MongoDB user secrets and users..."

# Admin user
kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
  create secret generic mdb-admin-user-password \
  --from-literal=password="${MDB_ADMIN_USER_PASSWORD}"

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-admin
spec:
  username: mdb-admin
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-admin-user-password
    key: password
  roles:
  - name: root
    db: admin
EOF

# Search sync user
kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
  create secret generic "${MDB_RESOURCE_NAME}-search-sync-source-password" \
  --from-literal=password="${MDB_SEARCH_SYNC_USER_PASSWORD}"

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: search-sync-source-user
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

# Regular user
kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
  create secret generic mdb-user-password \
  --from-literal=password="${MDB_USER_PASSWORD}"

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-user
spec:
  username: mdb-user
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-user-password
    key: password
  roles:
  - name: readWrite
    db: sample_mflix
EOF

log_success "MongoDB users created"

# Step 7: Deploy MongoDB Search
log_step "Step 7: Deploying MongoDB Search"
log_info "Deploying MongoDB Search (mongot)..."

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${MDB_RESOURCE_NAME}
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
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" wait --for=jsonpath='{.status.phase}'=Running "mdbs/${MDB_RESOURCE_NAME}" --timeout=300s

log_success "MongoDB Search deployed and running"

# Step 8: Verify Deployment
log_step "Step 8: Verifying Deployment"
log_info "Checking deployment status..."

echo "MongoDB resource:"
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get "mdb/${MDB_RESOURCE_NAME}"
echo ""
echo "MongoDBSearch resource:"
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get "mdbs/${MDB_RESOURCE_NAME}"
echo ""
echo "Pods running in cluster ${K8S_CTX}:"
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get pods

log_success "Deployment verification complete"

echo ""
echo "🎉 MongoDB Enterprise Search deployment completed successfully!"
echo ""
echo "📋 Next Steps:"
echo "   1. Add data to your MongoDB cluster"
echo "   2. Create MongoDB Search and Vector Search indexes"
echo "   3. Run queries against your data"
echo ""
echo "🔗 Connection String:"
echo "   ${MDB_CONNECTION_STRING}"
echo ""
