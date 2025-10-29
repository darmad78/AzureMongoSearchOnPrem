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
MDB_VERSION="8.2.1-ent"

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

echo -e "${BLUE}📋 How to get each credential:${NC}"
echo ""
echo -e "${YELLOW}1. Organization ID:${NC}"
echo "   • Open Ops Manager: http://${VM_IP}:8080"
echo "   • After login, look at the URL: http://${VM_IP}:8080/v2/org/YOUR_ORG_ID/"
echo "   • Or go to Organization Settings → General"
echo ""
echo -e "${YELLOW}2. Project ID:${NC}"
echo "   • Go to your 'Search Project'"
echo "   • Look at the URL: http://${VM_IP}:8080/v2/org/YOUR_ORG_ID/project/YOUR_PROJECT_ID/"
echo "   • Or go to Project Settings → General"
echo ""
echo -e "${YELLOW}3. API Keys (Public & Private):${NC}"
echo "   • Go to Project Settings → Access Manager → API Keys"
echo "   • Click 'Generate New API Key'"
echo "   • Set permissions:"
echo "     - Project Owner (full access)"
echo "     - Or at minimum:"
echo "       • Project Read Only"
echo "       • Project Data Access Read Only"
echo "       • Project Owner"
echo "   • Copy both Public and Private keys"
echo ""

# Get VM IP for Ops Manager URL
VM_IP=$(hostname -I | awk '{print $1}')
OPS_MANAGER_URL="http://${VM_IP}:8080"

# Prompt for credentials
echo -e "${YELLOW}Enter Organization ID (found in URL after /v2/org/):${NC}"
read -p "Organization ID: " ORG_ID
echo ""

echo -e "${YELLOW}Enter Project ID (found in URL after /project/):${NC}"
read -p "Project ID: " PROJECT_ID
echo ""

echo -e "${YELLOW}Enter Public API Key (from Project Settings → Access Manager → API Keys):${NC}"
read -p "Public API Key: " PUBLIC_KEY
echo ""

echo -e "${YELLOW}Enter Private API Key (from same API Keys page):${NC}"
read -sp "Private API Key: " PRIVATE_KEY
echo ""

# Validate inputs
if [ -z "$ORG_ID" ] || [ -z "$PROJECT_ID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
    log_error "One or more credentials are missing. Please run the script again."
    exit 1
fi

log_info "Validating credentials format..."
if [[ ! "$ORG_ID" =~ ^[0-9a-fA-F]{24}$ ]]; then
    log_warning "Organization ID format looks unusual. Expected 24-character hex string."
fi
if [[ ! "$PROJECT_ID" =~ ^[0-9a-fA-F]{24}$ ]]; then
    log_warning "Project ID format looks unusual. Expected 24-character hex string."
fi

log_success "Credentials collected"

# Step 2: Create Namespace
log_step "Step 2: Creating MongoDB Namespace"
log_info "Creating mongodb namespace..."

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
log_success "MongoDB namespace created"

# Step 3: Create Ops Manager Configuration
log_step "Step 3: Creating Ops Manager Configuration"
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

# Step 4: Deploy MongoDB Enterprise
log_step "Step 4: Deploying MongoDB Enterprise"
log_info "Deploying MongoDB Enterprise replica set..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBMulti
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  type: ReplicaSet
  version: ${MDB_VERSION}
  credentials: om-credentials
  opsManager:
    configMapRef:
      name: om-project
  security:
    authentication:
      enabled: true
      ignoreUnknownUsers: true
      modes:
      - SCRAM
  clusterSpecList:
    clusterSpecs:
    - clusterName: ${MDB_RESOURCE_NAME}
      members: 3
      exposedExternally: false
      statefulSet:
        spec:
          template:
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
kubectl wait --for=jsonpath='{.status.phase}'=Running "mongodbmulti/${MDB_RESOURCE_NAME}" -n ${NAMESPACE} --timeout=600s

log_success "MongoDB Enterprise deployed and running"

# Step 5: Create MongoDB Users
log_step "Step 5: Creating MongoDB Users"
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
  mongodbMultiResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-admin-user-password
    key: password
  roles:
  - name: root
    db: admin
EOF

# Application user
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
  mongodbMultiResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-user-password
    key: password
  roles:
  - name: readWrite
    db: admin
EOF

log_success "MongoDB users created"

# Step 6: Verify MongoDB Deployment
log_step "Step 6: Verifying MongoDB Deployment"
log_info "Checking MongoDB deployment status..."

echo "MongoDB resource:"
kubectl get "mongodbmulti/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
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
