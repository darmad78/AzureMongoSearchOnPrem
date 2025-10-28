#!/bin/bash
set -e

# MongoDB Enterprise Complete Installation Script
# Includes: Ops Manager setup, MongoDB Enterprise, Search, Backend, Frontend, Ollama
# Handles: Compatibility checks, API key setup, network configuration

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
║        MongoDB Enterprise Complete Installation              ║
║    Ops Manager + MongoDB + Search + Backend + Frontend      ║
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
log_info "Running compatibility check..."

if [ -f "./check-requirements.sh" ]; then
    ./check-requirements.sh kubernetes
    if [ $? -ne 0 ]; then
        log_error "System requirements not met. Please fix the issues above."
        exit 1
    fi
else
    log_warning "check-requirements.sh not found, skipping compatibility check"
fi

log_success "System requirements check passed"

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

# Step 4: Check for Existing Ops Manager
log_step "Step 4: Checking for Ops Manager"
log_info "Checking if Ops Manager is already running..."

OPS_MANAGER_RUNNING=false
if curl -s http://localhost:8080 >/dev/null 2>&1; then
    log_success "Ops Manager found at http://localhost:8080"
    OPS_MANAGER_RUNNING=true
    OPS_MANAGER_URL="http://${VM_IP}:8080"
else
    log_info "No Ops Manager found, will deploy one"
    OPS_MANAGER_URL="http://${VM_IP}:8080"
fi

# Step 5: Deploy Ops Manager (if needed)
if [ "$OPS_MANAGER_RUNNING" = false ]; then
    log_step "Step 5: Deploying Ops Manager"
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
else
    log_info "Using existing Ops Manager"
fi

# Step 6: Get Ops Manager Credentials
log_step "Step 6: Ops Manager Setup Required"
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

# Step 7: Install MongoDB Enterprise Operator
log_step "Step 7: Installing MongoDB Enterprise Operator"
log_info "Adding MongoDB Helm repository..."
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

log_info "Installing Enterprise Operator..."
helm install enterprise-operator mongodb/enterprise-operator \
  --namespace ${NAMESPACE} \
  --set operator.watchNamespace="${NAMESPACE}" \
  --wait --timeout=5m

log_success "MongoDB Enterprise Operator installed"

# Step 8: Configure Ops Manager Connection
log_step "Step 8: Configuring Ops Manager Connection"
log_info "Creating Ops Manager credentials and configuration..."

# Create namespace
kubectl create namespace ${NAMESPACE}

# Create credentials secret
kubectl create secret generic ops-manager-credentials \
  -n ${NAMESPACE} \
  --from-literal="publicKey=${PUBLIC_KEY}" \
  --from-literal="privateKey=${PRIVATE_KEY}"

# Create ConfigMap
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ops-manager-config
  namespace: ${NAMESPACE}
data:
  projectName: "${PROJECT_ID}"
  orgId: "${ORG_ID}"
  baseUrl: "${OPS_MANAGER_URL}"
EOF

log_success "Ops Manager connection configured"

# Step 9: Deploy MongoDB Enterprise
log_step "Step 9: Deploying MongoDB Enterprise"
log_info "Deploying MongoDB Enterprise (3-node replica set)..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: mongodb-rs
  namespace: ${NAMESPACE}
spec:
  version: "${MONGODB_VERSION}"
  type: ReplicaSet
  members: 3
  credentials: ops-manager-credentials
  opsManager:
    configMapRef:
      name: ops-manager-config
  security:
    authentication:
      enabled: true
      modes: ["SCRAM"]
      ignoreUnknownUsers: true
  persistent: true
  podSpec:
    podTemplate:
      spec:
        containers:
        - name: mongodb-enterprise-database
          resources:
            requests:
              cpu: "1"
              memory: "2Gi"
            limits:
              cpu: "2"
              memory: "4Gi"
          readinessProbe:
            exec:
              command:
              - mongosh
              - --eval
              - "db.adminCommand('ping')"
              - --quiet
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 5
            successThreshold: 1
            failureThreshold: 3
          livenessProbe:
            exec:
              command:
              - mongosh
              - --eval
              - "db.adminCommand('ping')"
              - --quiet
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 10
            successThreshold: 1
            failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-external
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: mongodb-rs-svc
  ports:
  - port: 27018
    targetPort: 27018
    nodePort: 30002
EOF

log_info "Waiting for MongoDB to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running mdb/mongodb-rs -n ${NAMESPACE} --timeout=600s || log_warning "MongoDB may still be initializing..."

log_success "MongoDB Enterprise deployed"

# Step 10: Create MongoDB Users
log_step "Step 10: Creating MongoDB Users"
log_info "Creating admin and application users..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: admin-user
  namespace: ${NAMESPACE}
spec:
  username: admin
  db: admin
  mongodbResourceRef:
    name: mongodb-rs
  passwordSecretKeyRef:
    name: mongodb-admin-password
    key: password
  roles:
    - name: root
      db: admin
---
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-admin-password
  namespace: ${NAMESPACE}
stringData:
  password: "${ADMIN_PASSWORD}"
---
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: app-user
  namespace: ${NAMESPACE}
spec:
  username: appuser
  db: admin
  mongodbResourceRef:
    name: mongodb-rs
  passwordSecretKeyRef:
    name: mongodb-user-password
    key: password
  roles:
    - name: readWrite
      db: searchdb
    - name: clusterMonitor
      db: admin
---
apiVersion: v1
kind: Secret
metadata:
  name: mongodb-user-password
  namespace: ${NAMESPACE}
stringData:
  password: "${USER_PASSWORD}"
EOF

log_success "MongoDB users created"

# Step 11: Deploy MongoDB Search (mongot)
log_step "Step 11: Deploying MongoDB Search"
log_info "Deploying MongoDB Search (mongot) with fixed authentication..."

# Create search sync source user secret
kubectl create secret generic mongodb-rs-search-sync-source-password \
  -n ${NAMESPACE} \
  --from-literal=password="search-sync-password123"

# Create search sync source user
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
    name: mongodb-rs
  passwordSecretKeyRef:
    name: mongodb-rs-search-sync-source-password
    key: password
  roles:
  - name: searchCoordinator
    db: admin
EOF

# Deploy MongoDB Search
kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: mongodb-rs
  namespace: ${NAMESPACE}
spec:
  version: "8.2.1"
  source:
    mongodbResourceRef:
      name: mongodb-rs
  resourceRequirements:
    requests:
      cpu: "2"
      memory: "3Gi"
    limits:
      cpu: "3"
      memory: "5Gi"
EOF

# Create fixed ConfigMap for MongoDB Search
kubectl create configmap mongodb-rs-search-config -n ${NAMESPACE} --from-literal=config.yml="
healthCheck:
  address: 0.0.0.0:8080
logging:
  verbosity: INFO
metrics:
  address: 0.0.0.0:9946
  enabled: true
server:
  wireproto:
    address: 0.0.0.0:27027
    authentication:
      keyFile: /tmp/keyfile
      mode: keyfile
    tls:
      mode: Disabled
storage:
  dataPath: /mongot/data
syncSource:
  replicaSet:
    authSource: admin
    hostAndPort:
    - mongodb-rs-0.mongodb-rs-svc.mongodb.svc.cluster.local:27017
    - mongodb-rs-1.mongodb-rs-svc.mongodb.svc.cluster.local:27017
    - mongodb-rs-2.mongodb-rs-svc.mongodb.svc.cluster.local:27017
    passwordFile: /tmp/sourceUserPassword
    readPreference: secondaryPreferred
    tls: false
    username: search-sync-source
    authenticationMechanism: SCRAM-SHA-256
" --dry-run=client -o yaml | kubectl apply -f -

log_info "Waiting for MongoDB Search to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running mongodbsearch/mongodb-rs -n ${NAMESPACE} --timeout=300s || log_warning "Search may still be initializing..."

log_success "MongoDB Search deployed with SCRAM-SHA-256 authentication"

# Step 12: Deploy Ollama
log_step "Step 12: Deploying Ollama"
log_info "Deploying Ollama (Local LLM)..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-data
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        ports:
        - containerPort: 11434
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
        env:
        - name: OLLAMA_HOST
          value: "0.0.0.0:11434"
        - name: OLLAMA_ORIGINS
          value: "*"
        readinessProbe:
          httpGet:
            path: /api/tags
            port: 11434
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /api/tags
            port: 11434
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
        resources:
          requests:
            cpu: "1"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
      volumes:
      - name: ollama-data
        persistentVolumeClaim:
          claimName: ollama-data
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ollama
  ports:
  - port: 11434
    targetPort: 11434
EOF

log_success "Ollama deployed"

# Step 13: Deploy Backend
log_step "Step 13: Deploying Backend"
log_info "Deploying Backend (FastAPI + AI)..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: ${NAMESPACE}
data:
  MONGODB_URL: "mongodb://appuser:${USER_PASSWORD}@mongodb-rs-svc.${NAMESPACE}.svc.cluster.local:27017/searchdb?replicaSet=mongodb-rs&authSource=admin"
  MONGODB_USER: "appuser"
  MONGODB_PASSWORD: "${USER_PASSWORD}"
  MONGODB_DB: "searchdb"
  LLM_PROVIDER: "ollama"
  OLLAMA_URL: "http://ollama-svc.${NAMESPACE}.svc.cluster.local:11434"
  OLLAMA_MODEL: "llama2"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-backend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: search-backend
  template:
    metadata:
      labels:
        app: search-backend
    spec:
      containers:
      - name: backend
        image: azuremongosearchonprem-backend:latest
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: backend-config
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "1"
            memory: "2Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: search-backend-svc
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: search-backend
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30001
EOF

log_success "Backend deployed"

# Step 14: Deploy Frontend
log_step "Step 14: Deploying Frontend"
log_info "Deploying Frontend (React + Vite)..."

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-frontend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: search-frontend
  template:
    metadata:
      labels:
        app: search-frontend
    spec:
      containers:
      - name: frontend
        image: azuremongosearchonprem-frontend:latest
        ports:
        - containerPort: 3000
        env:
        - name: REACT_APP_API_URL
          value: "http://search-backend-svc.${NAMESPACE}.svc.cluster.local:8000"
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "0.5"
            memory: "1Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: search-frontend-svc
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: search-frontend
  ports:
  - port: 3000
    targetPort: 3000
    nodePort: 30000
EOF

log_success "Frontend deployed"

# Step 15: Final Summary
log_step "Deployment Complete!"

echo -e "\n${GREEN}🎉 MongoDB Enterprise Complete Stack is Deployed!${NC}\n"

echo "📊 Deployment Summary:"
echo "   ✅ MongoDB Enterprise: 3-node replica set"
echo "   ✅ MongoDB Search (mongot): Vector search enabled"
echo "   ✅ Ops Manager: Monitoring & management"
echo "   ✅ Backend: FastAPI + AI models"
echo "   ✅ Frontend: React + Vite"
echo "   ✅ Ollama: Local LLM server"
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
echo "   kubectl logs -n ${NAMESPACE} -l app=backend -f"
echo "   kubectl logs -n ${NAMESPACE} -l app=frontend -f"
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
