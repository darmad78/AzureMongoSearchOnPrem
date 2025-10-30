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
MDB_VERSION="8.0.15-ent"

# Step 1: Clean Operator Installation
log_step "Step 1: Ensuring Clean Operator Installation"

# Check if operator namespace exists and clean it if needed
if kubectl get namespace mongodb-enterprise-operator &> /dev/null; then
    log_info "Found existing operator namespace, cleaning it..."
    kubectl delete namespace mongodb-enterprise-operator --ignore-not-found=true
    log_info "Waiting for namespace deletion to complete..."
    while kubectl get namespace mongodb-enterprise-operator &> /dev/null; do
        sleep 2
    done
    log_success "Operator namespace cleaned"
fi

# Reinstall the operator cleanly
log_info "Installing MongoDB Enterprise Operator..."
helm install mongodb-enterprise-operator mongodb/enterprise-operator \
    --namespace mongodb-enterprise-operator \
    --create-namespace \
    --set "watchNamespace=" \
    --wait

log_success "MongoDB Enterprise Operator installed successfully"

# Fix WATCH_NAMESPACE to watch all namespaces
log_info "Fixing WATCH_NAMESPACE to watch all namespaces..."
log_warning "This requires manual intervention. Please run the following command:"
echo ""
echo "kubectl edit deployment mongodb-enterprise-operator -n mongodb-enterprise-operator"
echo ""
echo "In the editor, find the WATCH_NAMESPACE section and change it from:"
echo "  - name: WATCH_NAMESPACE"
echo "    valueFrom:"
echo "      fieldRef:"
echo "        apiVersion: v1"
echo "        fieldPath: metadata.namespace"
echo ""
echo "To:"
echo "  - name: WATCH_NAMESPACE"
echo "    value: \"\""
echo ""
echo "Then save and exit (in vim: Esc, then :wq, Enter)"
echo ""
read -p "Press Enter after you've made the change and the deployment has restarted..."

log_info "Verifying WATCH_NAMESPACE fix..."
WATCH_NS=$(kubectl get deployment mongodb-enterprise-operator -n mongodb-enterprise-operator -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="WATCH_NAMESPACE")].value}')
if [ "$WATCH_NS" = "" ]; then
    log_success "WATCH_NAMESPACE is correctly set to empty string"
else
    log_error "WATCH_NAMESPACE is still set to: $WATCH_NS"
    log_error "Please fix this manually before continuing"
    exit 1
fi

# Fix RBAC permissions for cluster-wide access
log_info "Setting up cluster-wide RBAC permissions..."
log_info "Creating/updating ClusterRole with all necessary permissions..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mongodb-enterprise-operator-cluster
rules:
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
  - watch
  - create
  - update
  - delete
- apiGroups:
  - ""
  resources:
  - secrets
  - configmaps
  verbs:
  - get
  - list
  - create
  - update
  - delete
  - watch
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - create
  - get
  - list
  - watch
  - delete
  - update
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - list
  - watch
  - delete
  - deletecollection
- apiGroups:
  - mongodb.com
  resources:
  - mongodb
  - mongodb/finalizers
  - mongodbusers
  - mongodbusers/finalizers
  - opsmanagers
  - opsmanagers/finalizers
  - mongodbmulticluster
  - mongodbmulticluster/finalizers
  - mongodb/status
  - mongodbusers/status
  - opsmanagers/status
  - mongodbmulticluster/status
  verbs:
  - '*'
- apiGroups:
  - ""
  resources:
  - persistentvolumeclaims
  verbs:
  - get
  - delete
  - list
  - watch
  - patch
  - update
- apiGroups:
  - ""
  resources:
  - namespaces
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: mongodb-enterprise-operator-cluster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: mongodb-enterprise-operator-cluster
subjects:
- kind: ServiceAccount
  name: mongodb-enterprise-operator
  namespace: mongodb-enterprise-operator
EOF

log_success "Cluster-wide RBAC permissions configured"

# Verify RBAC permissions
log_info "Verifying RBAC permissions..."
kubectl auth can-i list mongodb --as=system:serviceaccount:mongodb-enterprise-operator:mongodb-enterprise-operator --all-namespaces
kubectl auth can-i list namespaces --as=system:serviceaccount:mongodb-enterprise-operator:mongodb-enterprise-operator
kubectl auth can-i list statefulsets --as=system:serviceaccount:mongodb-enterprise-operator:mongodb-enterprise-operator --all-namespaces

log_info "Restarting operator to pick up new RBAC permissions..."
kubectl rollout restart deployment/mongodb-enterprise-operator -n mongodb-enterprise-operator
kubectl rollout status deployment/mongodb-enterprise-operator -n mongodb-enterprise-operator --timeout=120s

log_success "Operator restarted with cluster-wide permissions"

# Step 2: Get Ops Manager Credentials
log_step "Step 2: Getting Ops Manager Credentials"
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

# Check for environment variables first
if [ -z "$ORG_ID" ] || [ -z "$PROJECT_ID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Environment variables not found. Please enter Ops Manager credentials:${NC}"
    echo ""
    
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
else
    log_info "Using credentials from environment variables"
    echo "Organization ID: $ORG_ID"
    echo "Project ID: $PROJECT_ID"
    echo "Public API Key: $PUBLIC_KEY"
    echo "Private API Key: [HIDDEN]"
    echo ""
fi

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

# Check IP Access List
log_info "Checking Ops Manager IP Access List..."
MINIKUBE_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
log_warning "IMPORTANT: Ensure Ops Manager IP Access List includes the minikube node IP"
echo ""
echo "📋 Add this IP to Ops Manager IP Access List:"
echo "   • Go to Ops Manager: http://${VM_IP}:8080"
echo "   • Organization Settings → Access Manager → IP Access List"
echo "   • Add IP: ${MINIKUBE_NODE_IP}/32"
echo "   • Or add range: 192.168.49.0/24"
echo ""
read -p "Press Enter after adding the IP to the access list..."

# Wait for MongoDB pods to be created and get their IPs
log_info "Waiting for MongoDB pods to be created..."
kubectl wait --for=condition=Ready pod -l app=mongodb-enterprise-database -n ${NAMESPACE} --timeout=300s || true

# Get MongoDB pod IPs for IP access list
log_info "Getting MongoDB pod IPs for Ops Manager IP Access List..."
MONGODB_POD_IPS=$(kubectl get pods -n ${NAMESPACE} -l app=mongodb-enterprise-database -o jsonpath='{.items[*].status.podIP}')
if [ -n "$MONGODB_POD_IPS" ]; then
    log_warning "CRITICAL: Add these MongoDB pod IPs to Ops Manager IP Access List:"
    echo ""
    echo "📋 MongoDB Pod IPs to add:"
    for ip in $MONGODB_POD_IPS; do
        echo "   • $ip/32"
    done
    echo ""
    echo "   • Go to Ops Manager: http://${VM_IP}:8080"
    echo "   • Organization Settings → Access Manager → IP Access List"
    echo "   • Add each IP above with /32 subnet"
    echo "   • Or add the entire pod network range if known"
    echo ""
    read -p "Press Enter after adding the MongoDB pod IPs to the access list..."
else
    log_warning "MongoDB pods not yet created. You may need to add pod IPs manually later."
fi

# Configure Ops Manager URL
log_info "Configuring Ops Manager URL..."
log_warning "IMPORTANT: Fix Ops Manager configuration file"
echo ""
echo "📋 Fix Ops Manager Configuration:"
echo "   • The config file shows port 8888, but we need 8080"
echo "   • Check the config file: /opt/mongodb/mms/conf/conf-mms.properties"
echo "   • Look for 'mms.centralUrl' and change port from 8888 to 8080"
echo "   • Or check: /opt/mongodb/mms/conf/conf-mms.properties"
echo "   • Restart Ops Manager after making changes"
echo ""
echo "   • Also configure in web interface:"
echo "   • Go to Ops Manager: http://${VM_IP}:8080"
echo "   • Organization Settings → General"
echo "   • Set 'URL to Access Ops Manager' to: http://${VM_IP}:8080"
echo ""
read -p "Press Enter after configuring the Ops Manager URL..."

# Optional: front OM with nginx on :80 if 8080 DNAT is detected or forced
if sudo nft list ruleset | grep -qi 'tcp dport 8080 dnat' || [ "${OM_PROXY_80:-false}" = "true" ]; then
  log_info "Setting up nginx reverse proxy on :80 → :8080..."
  sudo apt-get update -y && sudo apt-get install -y nginx
  sudo tee /etc/nginx/sites-available/ops-manager >/dev/null <<'NGINX'
server {
  listen 80 default_server;
  server_name _;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
  }
}
NGINX
  sudo ln -sf /etc/nginx/sites-available/ops-manager /etc/nginx/sites-enabled/default
  sudo systemctl restart nginx
  log_warning "Open TCP:80 in GCP firewall before accessing the UI externally."
fi

# Install MongoDB version from repository
log_info "Installing MongoDB Enterprise 8.0.15 RHEL 8 from repository..."

# Check if we have the x86_64 version (preferred) or ARM64 version
if [ -f "backend/opsmanagerfiles/mongodb-linux-x86_64-enterprise-rhel80-8.0.15.tgz" ]; then
    MONGODB_BINARY="backend/opsmanagerfiles/mongodb-linux-x86_64-enterprise-rhel80-8.0.15.tgz"
    log_info "Using x86_64 version"
elif [ -f "backend/opsmanagerfiles/mongodb-linux-aarch64-enterprise-rhel8-8.0.15.tgz" ]; then
    MONGODB_BINARY="backend/opsmanagerfiles/mongodb-linux-aarch64-enterprise-rhel8-8.0.15.tgz"
    log_warning "Using ARM64 version - ensure Ops Manager server is ARM64 compatible"
else
    log_error "No MongoDB RHEL 8 binary found in backend/opsmanagerfiles/"
    log_error "Please ensure the repository is cloned with Git LFS or manually download:"
    log_error "  curl -LO https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-enterprise-rhel80-8.0.15.tgz"
    log_error "  mkdir -p backend/opsmanagerfiles/"
    log_error "  mv mongodb-linux-x86_64-enterprise-rhel80-8.0.15.tgz backend/opsmanagerfiles/"
    exit 1
fi

log_info "Copying MongoDB binary to Ops Manager..."
sudo cp "$MONGODB_BINARY" /opt/mongodb/mms/mongodb-releases/
sudo chown mongodb-mms:mongodb-mms /opt/mongodb/mms/mongodb-releases/$(basename "$MONGODB_BINARY")

log_success "MongoDB RHEL 8 version installed in Ops Manager"

# Step 3: Create Namespace
log_step "Step 3: Creating MongoDB Namespace"
log_info "Creating mongodb namespace..."

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
log_success "MongoDB namespace created"

# Create required ServiceAccount for MongoDB pods
log_info "Creating ServiceAccount for MongoDB pods..."
kubectl create serviceaccount mongodb-enterprise-database-pods -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
log_success "ServiceAccount created"

# Step 4: Create Ops Manager Configuration
log_step "Step 4: Creating Ops Manager Configuration"
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
  authType: DIGEST
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

# Step 5: Deploy MongoDB Enterprise
log_step "Step 5: Deploying MongoDB Enterprise"
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

# Step 6: Create MongoDB Users
log_step "Step 6: Creating MongoDB Users"
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
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-user-password
    key: password
  roles:
  - name: readWrite
    db: admin
EOF

log_success "MongoDB users created"

# Step 7: Verify MongoDB Deployment
log_step "Step 7: Verifying MongoDB Deployment"
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
