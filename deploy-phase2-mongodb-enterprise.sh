#!/bin/bash
set -e

# Phase 2: Deploy MongoDB Enterprise with Ops Manager
# This deploys MongoDB Enterprise using the Ops Manager credentials from Phase 1

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
║                Phase 2: MongoDB Enterprise Setup           ║
║              Using Ops Manager Credentials                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
MDB_RESOURCE_NAME="mdb-rs"
MDB_VERSION="8.2.0-ent"

# Step 1: Get Ops Manager Credentials
log_step "Step 1: Getting Ops Manager Credentials"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Enter Ops Manager Credentials                 ║
╚══════════════════════════════════════════════════════════════╝

Please enter the credentials you obtained from Phase 1:

EOF
echo -e "${NC}"

# Get VM IP for Ops Manager URL
VM_IP=$(hostname -I | awk '{print $1}')
OPS_MANAGER_URL="http://${VM_IP}:8080"

# Prompt for credentials
read -p "Enter Organization ID: " ORG_ID
read -p "Enter Project ID: " PROJECT_ID
read -p "Enter Public API Key: " PUBLIC_KEY
read -sp "Enter Private API Key: " PRIVATE_KEY
echo ""

log_success "Credentials collected"

# Step 2: Create Ops Manager Configuration
log_step "Step 2: Creating Ops Manager Configuration"
log_info "Creating Ops Manager configuration with provided credentials..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: ${NAMESPACE}
data:
  projectName: "${PROJECT_ID}"
  orgId: "${ORG_ID}"
  baseUrl: "${OPS_MANAGER_URL}"
---
apiVersion: v1
kind: Secret
metadata:
  name: om-credentials
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  publicKey: "${PUBLIC_KEY}"
  privateKey: "${PRIVATE_KEY}"
EOF

log_success "Ops Manager configuration created"

# Step 3: Deploy MongoDB Enterprise
log_step "Step 3: Deploying MongoDB Enterprise"
log_info "Deploying MongoDB Enterprise replica set..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
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
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdb/${MDB_RESOURCE_NAME}" -n ${NAMESPACE} --timeout=600s

log_success "MongoDB Enterprise deployed and running"

# Step 4: Create MongoDB Users
log_step "Step 4: Creating MongoDB Users"
log_info "Creating MongoDB users for search functionality..."

# Admin user
kubectl create secret generic mdb-admin-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="admin-user-password-CHANGE-ME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-admin
  namespace: ${NAMESPACE}
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
kubectl create secret generic "${MDB_RESOURCE_NAME}-search-sync-source-password" \
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

# Regular user
kubectl create secret generic mdb-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="mdb-user-password-CHANGE-ME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-user
  namespace: ${NAMESPACE}
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

# Step 5: Verify MongoDB Deployment
log_step "Step 5: Verifying MongoDB Deployment"
log_info "Checking MongoDB deployment status..."

echo "MongoDB resource:"
kubectl get "mdb/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "MongoDB pods:"
kubectl get pods -n ${NAMESPACE} -l app=mongodb-rs-svc
echo ""

log_success "Phase 2 complete! MongoDB Enterprise is running."
echo ""
echo "🔗 Next Steps:"
echo "   1. MongoDB Enterprise is ready"
echo "   2. Users are created with proper roles"
echo "   3. Run Phase 3: ./deploy-phase3-mongodb-search.sh"
echo ""
