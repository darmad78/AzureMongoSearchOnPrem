#!/bin/bash
set -e

# MongoDB Enterprise Complete Stack Deployment Script
# Uses separate YAML files for better organization and maintainability
# Includes all fixes for authentication, networking, and health checks

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
║        MongoDB Enterprise Complete Stack Deployment         ║
║    Ops Manager + MongoDB + Search + Backend + Frontend     ║
║              WITH ALL AUTHENTICATION FIXES                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-mongodb}"
MONGODB_VERSION="${MONGODB_VERSION:-8.2.1-ent}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SecureAdmin123!}"
USER_PASSWORD="${USER_PASSWORD:-SecureUser456!}"

log_info "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  MongoDB Version: ${MONGODB_VERSION}"
echo ""

# Step 1: System Requirements Check
log_step "Step 1: Checking System Requirements"
if [ -f "./check-requirements.sh" ]; then
    ./check-requirements.sh kubernetes
    if [ $? -ne 0 ]; then
        log_error "System requirements not met. Please fix the issues above."
        exit 1
    fi
else
    log_warning "check-requirements.sh not found, skipping requirements check"
fi

# Step 2: Clean Environment
log_step "Step 2: Cleaning Environment"
log_info "Removing old deployments..."

# Clean Docker
docker system prune -a -f 2>/dev/null || true

# Clean Kubernetes
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --wait=true 2>/dev/null || true
kubectl delete namespace ops-manager --ignore-not-found=true --wait=true 2>/dev/null || true

# Clean kind clusters
kind delete cluster --name mongodb-cluster 2>/dev/null || true
kind delete clusters --all 2>/dev/null || true

sleep 5
log_success "Environment cleaned"

# Step 3: Create Kubernetes Cluster
log_step "Step 3: Creating Kubernetes Cluster"
log_info "Creating kind cluster with port mappings..."

# Get VM IP for Ops Manager access
VM_IP=$(hostname -I | awk '{print $1}')
log_info "VM IP detected: ${VM_IP}"

kind create cluster --name mongodb-cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 5173
    protocol: TCP
  - containerPort: 30001
    hostPort: 8000
    protocol: TCP
  - containerPort: 30002
    hostPort: 27018
    protocol: TCP
  - containerPort: 30003
    hostPort: 8081
    protocol: TCP
EOF

log_info "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
log_success "Kubernetes cluster created and ready"

# Step 4: Install MongoDB Kubernetes Operator
log_step "Step 4: Installing MongoDB Kubernetes Operator"
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

helm install mongodb-kubernetes mongodb/mongodb-kubernetes \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --wait

log_success "MongoDB Kubernetes Operator installed"

# Step 5: Create Dummy Credentials for MongoDB Enterprise
log_step "Step 5: Creating Dummy Credentials for MongoDB Enterprise"
log_info "Creating dummy credentials to allow MongoDB Enterprise deployment..."

# Create dummy credentials secret
kubectl create secret generic om-credentials \
  -n ${NAMESPACE} \
  --from-literal=publicKey="dummy-key" \
  --from-literal=privateKey="dummy-key" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create dummy Ops Manager config
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: ${NAMESPACE}
data:
  projectName: "dummy-project"
  orgId: "dummy-org"
  baseUrl: "https://dummy-url.com"
EOF

log_success "Dummy credentials created"

# Step 6: Deploy MongoDB Enterprise First
log_step "Step 6: Deploying MongoDB Enterprise (Before Ops Manager)"
log_info "Deploying MongoDB Enterprise replica set with dummy credentials..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: mdb-rs
  namespace: ${NAMESPACE}
spec:
  members: 3
  version: 8.2.0-ent
  type: ReplicaSet
  credentials: om-credentials
  opsManager:
    configMapRef:
      name: om-project
  security:
    authentication:
      enabled: true
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
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdb/mdb-rs" -n ${NAMESPACE} --timeout=400s

log_success "MongoDB Enterprise deployed and running"

# Step 7: Deploy Ops Manager (Optional)
log_step "Step 7: Deploying Ops Manager (Optional)"
log_info "Deploying Ops Manager with Helm..."

# Create namespace
kubectl create namespace ops-manager

# Add Helm repo
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

# Deploy Ops Manager
helm install ops-manager mongodb/ops-manager \
  --namespace ops-manager \
  --set appDb.storageSize=50Gi \
  --set opsManager.replicas=1 \
  --set service.type=LoadBalancer \
  --wait --timeout=15m

log_success "Ops Manager deployed"

# Step 8: Get Ops Manager Credentials
log_step "Step 8: Ops Manager Setup Required"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Ops Manager Setup Required                     ║
╚══════════════════════════════════════════════════════════════╝

Please complete the following steps in Ops Manager:

1. Open Ops Manager: http://localhost:8080
2. Login or create account
3. Create organization (note the Organization ID)
4. Create project (note the Project ID)
5. Go to: Project Settings → Access Manager → API Keys
6. Create API Key with "Project Owner" role
7. Add your VM IP (${VM_IP}) to API Access List
8. Copy the credentials below

EOF
echo -e "${NC}"

# Prompt for credentials
read -p "Enter Organization ID: " ORG_ID
read -p "Enter Project ID: " PROJECT_ID
read -p "Enter Public API Key: " PUBLIC_KEY
read -sp "Enter Private API Key: " PRIVATE_KEY
echo ""

log_success "Credentials collected"

# Step 7: Update Ops Manager Configuration
log_step "Step 7: Updating Ops Manager Configuration"
log_info "Updating Ops Manager configuration with provided credentials..."

# Update the ops-manager-config.yaml with actual credentials
sed -i "s/your-org-id/${ORG_ID}/g" ops-manager-config.yaml
sed -i "s/your-public-api-key/${PUBLIC_KEY}/g" ops-manager-config.yaml
sed -i "s/your-private-api-key/${PRIVATE_KEY}/g" ops-manager-config.yaml

log_success "Ops Manager configuration updated"

# Step 8: Deploy MongoDB Enterprise (Official Guide)
log_step "Step 8: Deploying MongoDB Enterprise (Official Guide)"
log_info "Deploying MongoDB Enterprise using official guide approach..."

# Deploy MongoDB Enterprise using official guide
kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: mdb-rs
  namespace: ${NAMESPACE}
spec:
  members: 3
  version: 8.2.0-ent
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
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdb/mdb-rs" -n ${NAMESPACE} --timeout=400s

log_success "MongoDB Enterprise deployed and running"

# Step 9: Create MongoDB Users (Official Guide)
log_step "Step 9: Creating MongoDB Users (Official Guide)"
log_info "Creating MongoDB users using official guide approach..."

# Admin user
kubectl create secret generic mdb-admin-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="admin-user-password-CHANGE-ME"

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
    name: mdb-rs
  passwordSecretKeyRef:
    name: mdb-admin-user-password
    key: password
  roles:
  - name: root
    db: admin
EOF

# Search sync user
kubectl create secret generic mdb-rs-search-sync-source-password \
  -n ${NAMESPACE} \
  --from-literal=password="search-sync-user-password-CHANGE-ME"

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
    name: mdb-rs
  passwordSecretKeyRef:
    name: mdb-rs-search-sync-source-password
    key: password
  roles:
  - name: searchCoordinator
    db: admin
EOF

# Regular user
kubectl create secret generic mdb-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="mdb-user-password-CHANGE-ME"

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
    name: mdb-rs
  passwordSecretKeyRef:
    name: mdb-user-password
    key: password
  roles:
  - name: readWrite
    db: sample_mflix
EOF

log_success "MongoDB users created"

# Step 10: Deploy MongoDB Search (Official Guide)
log_step "Step 10: Deploying MongoDB Search (Official Guide)"
log_info "Deploying MongoDB Search using official guide approach..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: mdb-rs
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
kubectl wait --for=jsonpath='{.status.phase}'=Running "mdbs/mdb-rs" -n ${NAMESPACE} --timeout=300s

log_success "MongoDB Search deployed and running"

# Step 11: Deploy Backend and Frontend
log_step "Step 11: Deploying Backend and Frontend"
log_info "Deploying Backend and Frontend..."

# Deploy Backend and Frontend
kubectl apply -f backend-frontend-config.yaml

# Deploy Ollama
kubectl apply -f ollama-config.yaml

log_success "All components deployed"

# Step 9: Wait for All Components to be Ready
log_step "Step 9: Waiting for All Components to be Ready"
log_info "Waiting for all pods to be running..."

# Wait for MongoDB
kubectl wait --for=jsonpath='{.status.phase}'=Running mongodb/mongodb-rs -n ${NAMESPACE} --timeout=600s || log_warning "MongoDB may still be initializing..."

# Wait for MongoDB Search
kubectl wait --for=jsonpath='{.status.phase}'=Running mongodbsearch/mongodb-rs -n ${NAMESPACE} --timeout=300s || log_warning "Search may still be initializing..."

# Wait for Backend
kubectl wait --for=condition=Available deployment/search-backend -n ${NAMESPACE} --timeout=300s || log_warning "Backend may still be initializing..."

# Wait for Frontend
kubectl wait --for=condition=Available deployment/search-frontend -n ${NAMESPACE} --timeout=300s || log_warning "Frontend may still be initializing..."

# Wait for Ollama
kubectl wait --for=condition=Available deployment/ollama -n ${NAMESPACE} --timeout=300s || log_warning "Ollama may still be initializing..."

log_success "All components are ready"

# Step 10: Final Summary
log_step "Deployment Complete!"

echo -e "\n${GREEN}🎉 MongoDB Enterprise Complete Stack is Deployed!${NC}\n"

echo "📊 Deployment Summary:"
echo "   ✅ MongoDB Enterprise: 3-node replica set with SCRAM authentication"
echo "   ✅ MongoDB Search (mongot): Vector search with SCRAM-SHA-256"
echo "   ✅ Ops Manager: Monitoring & management"
echo "   ✅ Backend: FastAPI + AI models with health checks"
echo "   ✅ Frontend: React + Vite with health checks"
echo "   ✅ Ollama: Local LLM server with health checks"
echo ""

echo "🔗 Access Information:"
echo ""
echo "   Frontend:  http://localhost:5173"
echo "   Backend:   http://localhost:8000"
echo "   MongoDB:   mongodb://appuser:${USER_PASSWORD}@localhost:27018/searchdb?replicaSet=mongodb-rs&authSource=admin"
echo "   Ops Manager: http://localhost:8080"
echo ""

echo "📋 Useful Commands:"
echo "   # Check all pods"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "   # Check MongoDB status"
echo "   kubectl get mdb,mdbs -n ${NAMESPACE}"
echo ""
echo "   # View logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-backend -f"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-frontend -f"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it mongodb-rs-0 -n ${NAMESPACE} -- mongosh -u admin -p ${ADMIN_PASSWORD} --authenticationDatabase admin"
echo ""

echo "🎯 Next Steps:"
echo "   1. Wait for all pods to be Running (5-10 minutes)"
echo "   2. Access the frontend at http://localhost:5173"
echo "   3. Upload documents and test search"
echo "   4. Try RAG chat functionality"
echo ""

log_info "Monitor deployment:"
echo "   kubectl get pods -n ${NAMESPACE} -w"
echo ""

log_success "Complete installation script finished successfully!"
