#!/bin/bash
set -e

# Phase 5: Deploy Backend & Frontend
# Deploys the Python FastAPI backend and React frontend to Kubernetes

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
║           Phase 5: Backend & Frontend Deployment           ║
║          Python FastAPI + React Application                ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
BACKEND_IMAGE="azuremongosearch-backend:latest"
FRONTEND_IMAGE="document-search-frontend:fixed-v1"
BACKEND_PORT=8888
FRONTEND_PORT=5173

# Get VM IP for displaying access information
VM_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "${VM_IP}")

log_info "Configuration:"
echo "  📦 Namespace: ${NAMESPACE}"
echo "  🐳 Backend Image: ${BACKEND_IMAGE}"
echo "  🐳 Frontend Image: ${FRONTEND_IMAGE}"
echo "  🔌 Backend Port: ${BACKEND_PORT}"
echo "  🔌 Frontend Port: ${FRONTEND_PORT}"
echo "  🖥️  VM IP: ${VM_IP}"
echo ""

# Step 1: Verify Prerequisites
log_step "Step 1: Verifying Prerequisites"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed. Please run Phase 1 first."
    exit 1
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    log_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check kubectl connectivity
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl is not connected to a Kubernetes cluster. Please run Phase 1 first."
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
    log_error "Namespace ${NAMESPACE} does not exist. Please run Phase 2 first."
    exit 1
fi

# Check if MongoDB is deployed
if ! kubectl get svc -n ${NAMESPACE} | grep -q "mdb-rs-svc\|mongodb-rs-svc"; then
    log_error "MongoDB service not found. Please run Phase 2 first."
    exit 1
fi

# Check if Ollama is deployed
if ! kubectl get svc -n ${NAMESPACE} | grep -q ollama-svc; then
    log_error "Ollama service not found. Please run Phase 4 first."
    exit 1
fi

log_success "All prerequisites met"

# Step 2: Build Backend Docker Image
log_step "Step 2: Building Backend Docker Image"

if [ ! -d "./backend" ]; then
    log_error "Backend directory not found. Please ensure you're in the project root."
    exit 1
fi

log_info "Building backend image: ${BACKEND_IMAGE}"
docker build -t ${BACKEND_IMAGE} ./backend

if [ $? -eq 0 ]; then
    log_success "Backend image built successfully"
else
    log_error "Failed to build backend image"
    exit 1
fi

# Step 3: Build Frontend Docker Image
log_step "Step 3: Building Frontend Docker Image"

if [ ! -d "./frontend" ]; then
    log_error "Frontend directory not found. Please ensure you're in the project root."
    exit 1
fi

log_info "Building frontend image: ${FRONTEND_IMAGE}"
docker build -t ${FRONTEND_IMAGE} ./frontend

if [ $? -eq 0 ]; then
    log_success "Frontend image built successfully"
else
    log_error "Failed to build frontend image"
    exit 1
fi

# Step 4: Load Images to Kubernetes (for minikube)
log_step "Step 4: Loading Images to Kubernetes"

# Check if we're using minikube
if kubectl config current-context | grep -q minikube; then
    log_info "Detected minikube cluster, loading images..."
    
    log_info "Loading backend image to minikube..."
    minikube image load ${BACKEND_IMAGE}
    
    log_info "Loading frontend image to minikube..."
    minikube image load ${FRONTEND_IMAGE}
    
    log_success "Images loaded to minikube"
else
    log_info "Not using minikube, skipping image load (assuming images are accessible)"
fi

# Step 5: Get MongoDB Connection Details
log_step "Step 5: Retrieving MongoDB Connection Details"

# Get MongoDB service details - check which service name is used
if kubectl get svc -n ${NAMESPACE} mdb-rs-svc &> /dev/null; then
    MONGODB_SERVICE="mdb-rs-svc.${NAMESPACE}.svc.cluster.local"
    REPLICA_SET_NAME="mdb-rs"
else
    MONGODB_SERVICE="mongodb-rs-svc.${NAMESPACE}.svc.cluster.local"
    REPLICA_SET_NAME="mongodb-rs"
fi

# Get MongoDB credentials from secrets
log_info "Retrieving MongoDB credentials from secrets..."
if kubectl get secret mdb-user-password -n ${NAMESPACE} &> /dev/null; then
    MONGODB_USER="mdb-user"
    MONGODB_PASSWORD=$(kubectl get secret mdb-user-password -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
elif kubectl get secret mongodb-user-password -n ${NAMESPACE} &> /dev/null; then
    MONGODB_USER="appuser"
    MONGODB_PASSWORD=$(kubectl get secret mongodb-user-password -n ${NAMESPACE} -o jsonpath='{.data.password}' | base64 -d)
else
    log_warning "Could not find MongoDB user credentials secret, using defaults"
    MONGODB_USER="appuser"
    MONGODB_PASSWORD="SecureUser456"
fi

MONGODB_PORT="27017"
MONGODB_DB="searchdb"
MONGODB_URL="mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@${MONGODB_SERVICE}:${MONGODB_PORT}/${MONGODB_DB}?replicaSet=${REPLICA_SET_NAME}&authSource=admin"

log_info "MongoDB connection: ${MONGODB_SERVICE}:${MONGODB_PORT}"
log_info "MongoDB user: ${MONGODB_USER}"
log_success "MongoDB connection details retrieved"

# Ensure MongoDB user has access to searchdb
log_info "Ensuring MongoDB user has access to searchdb database..."
if kubectl get mongodbuser ${MONGODB_USER} -n ${NAMESPACE} &> /dev/null; then
    # Check if searchdb role exists, if not add it
    HAS_SEARCHDB_ROLE=$(kubectl get mongodbuser ${MONGODB_USER} -n ${NAMESPACE} -o jsonpath='{.spec.roles[?(@.db=="searchdb")].db}' 2>/dev/null || echo "")
    if [ -z "$HAS_SEARCHDB_ROLE" ]; then
        log_info "Adding readWrite role on searchdb for ${MONGODB_USER}..."
        kubectl patch mongodbuser ${MONGODB_USER} -n ${NAMESPACE} --type='json' \
            -p='[{"op": "add", "path": "/spec/roles/-", "value": {"db": "searchdb", "name": "readWrite"}}]' || \
            log_warning "Could not add searchdb role, user may need manual configuration"
        sleep 5  # Wait for operator to apply changes
    else
        log_info "MongoDB user already has access to searchdb"
    fi
fi

# Create text index for search functionality
log_info "Creating text index on documents collection for search..."
kubectl run mongo-index-temp --image=mongodb/mongodb-enterprise-server:latest --restart=Never -n ${NAMESPACE} \
    --command -- mongosh "${MONGODB_URL}" --eval 'db.documents.createIndex({ title: "text", body: "text", tags: "text" })' \
    > /dev/null 2>&1 || log_warning "Could not create text index, it may already exist"
sleep 5
kubectl delete pod mongo-index-temp -n ${NAMESPACE} > /dev/null 2>&1 || true
log_success "MongoDB database configuration complete"

# Step 6: Get Ollama Connection Details
log_step "Step 6: Retrieving Ollama Connection Details"

OLLAMA_SERVICE="ollama-svc.${NAMESPACE}.svc.cluster.local"
OLLAMA_PORT="11434"
OLLAMA_URL="http://${OLLAMA_SERVICE}:${OLLAMA_PORT}"

# Get Ollama model from ConfigMap if it exists
OLLAMA_MODEL=$(kubectl get configmap ai-models-config -n ${NAMESPACE} -o jsonpath='{.data.OLLAMA_MODEL}' 2>/dev/null || echo "llama2")

log_info "Ollama connection: ${OLLAMA_SERVICE}:${OLLAMA_PORT}"
log_info "Ollama model: ${OLLAMA_MODEL}"
log_success "Ollama connection details retrieved"

# Step 7: Deploy Backend
log_step "Step 7: Deploying Backend Application"

log_info "Creating backend ConfigMap and Deployment..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: ${NAMESPACE}
data:
  MONGODB_URL: "${MONGODB_URL}"
  MONGODB_USER: "${MONGODB_USER}"
  MONGODB_PASSWORD: "${MONGODB_PASSWORD}"
  MONGODB_DB: "${MONGODB_DB}"
  LLM_PROVIDER: "ollama"
  OLLAMA_URL: "${OLLAMA_URL}"
  OLLAMA_MODEL: "${OLLAMA_MODEL}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-backend
  namespace: ${NAMESPACE}
  labels:
    app: search-backend
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
        image: ${BACKEND_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: ${BACKEND_PORT}
        envFrom:
        - configMapRef:
            name: backend-config
        readinessProbe:
          httpGet:
            path: /
            port: ${BACKEND_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: ${BACKEND_PORT}
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
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: search-backend-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: search-backend
  ports:
  - port: ${BACKEND_PORT}
    targetPort: ${BACKEND_PORT}
    nodePort: 30888
  type: NodePort
EOF

log_success "Backend deployment created"

# Step 8: Wait for Backend to be Ready
log_step "Step 8: Waiting for Backend to be Ready"

log_info "Waiting for backend pod to be created..."
sleep 5

TIMEOUT=120
ELAPSED=0
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  BACKEND_POD=$(kubectl get pods -n ${NAMESPACE} -l app=search-backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "${BACKEND_POD}" ]; then
    log_success "Backend pod created: ${BACKEND_POD}"
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ -z "${BACKEND_POD}" ]; then
  log_error "Backend pod was not created within ${TIMEOUT}s"
  exit 1
fi

log_info "Waiting for backend pod to be ready (this may take a few minutes)..."
echo ""
echo "💡 Monitor progress in another terminal:"
echo "   kubectl get pods -n ${NAMESPACE} -l app=search-backend -w"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-backend -f"
echo ""

kubectl wait --for=condition=Ready pod -l app=search-backend -n ${NAMESPACE} --timeout=300s || {
  log_error "Backend pod did not become ready"
  log_info "Checking pod status..."
  kubectl describe pod -l app=search-backend -n ${NAMESPACE} | tail -30
  log_info "Checking pod logs..."
  kubectl logs -l app=search-backend -n ${NAMESPACE} --tail=50
  exit 1
}

log_success "Backend pod is ready"

# Step 9: Deploy Frontend
log_step "Step 9: Deploying Frontend Application"

# Get backend NodePort for external access
BACKEND_NODE_PORT=$(kubectl get svc search-backend-svc -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
# Use the correct external IP instead of VM_IP which might be internal
EXTERNAL_IP="136.112.200.116"
BACKEND_EXTERNAL_URL="http://${EXTERNAL_IP}:${BACKEND_NODE_PORT}"

log_info "Backend external URL: ${BACKEND_EXTERNAL_URL}"
log_info "Creating frontend Deployment..."

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-frontend
  namespace: ${NAMESPACE}
  labels:
    app: search-frontend
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
        image: ${FRONTEND_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: ${FRONTEND_PORT}
        env:
        - name: VITE_API_URL
          value: "${BACKEND_EXTERNAL_URL}"
        readinessProbe:
          httpGet:
            path: /
            port: ${FRONTEND_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: ${FRONTEND_PORT}
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
            cpu: "1"
            memory: "2Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: search-frontend-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: search-frontend
  ports:
  - port: ${FRONTEND_PORT}
    targetPort: ${FRONTEND_PORT}
    nodePort: 30173
  type: NodePort
EOF

log_success "Frontend deployment created"

# Step 10: Wait for Frontend to be Ready
log_step "Step 10: Waiting for Frontend to be Ready"

log_info "Waiting for frontend pod to be created..."
sleep 5

TIMEOUT=120
ELAPSED=0
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  FRONTEND_POD=$(kubectl get pods -n ${NAMESPACE} -l app=search-frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "${FRONTEND_POD}" ]; then
    log_success "Frontend pod created: ${FRONTEND_POD}"
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ -z "${FRONTEND_POD}" ]; then
  log_error "Frontend pod was not created within ${TIMEOUT}s"
  exit 1
fi

log_info "Waiting for frontend pod to be ready (this may take a few minutes)..."
echo ""
echo "💡 Monitor progress in another terminal:"
echo "   kubectl get pods -n ${NAMESPACE} -l app=search-frontend -w"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-frontend -f"
echo ""

kubectl wait --for=condition=Ready pod -l app=search-frontend -n ${NAMESPACE} --timeout=300s || {
  log_error "Frontend pod did not become ready"
  log_info "Checking pod status..."
  kubectl describe pod -l app=search-frontend -n ${NAMESPACE} | tail -30
  log_info "Checking pod logs..."
  kubectl logs -l app=search-frontend -n ${NAMESPACE} --tail=50
  exit 1
}

log_success "Frontend pod is ready"

# Step 11: Verify Deployment
log_step "Step 11: Verifying Deployment"

log_info "Checking all components..."
echo ""

echo "Backend Deployment:"
kubectl get deployment search-backend -n ${NAMESPACE}
echo ""

echo "Backend Pod:"
kubectl get pods -n ${NAMESPACE} -l app=search-backend
echo ""

echo "Backend Service:"
kubectl get svc search-backend-svc -n ${NAMESPACE}
echo ""

echo "Frontend Deployment:"
kubectl get deployment search-frontend -n ${NAMESPACE}
echo ""

echo "Frontend Pod:"
kubectl get pods -n ${NAMESPACE} -l app=search-frontend
echo ""

echo "Frontend Service:"
kubectl get svc search-frontend-svc -n ${NAMESPACE}
echo ""

# Get access URLs
BACKEND_NODE_PORT=$(kubectl get svc search-backend-svc -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
FRONTEND_NODE_PORT=$(kubectl get svc search-frontend-svc -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')

BACKEND_URL="http://${VM_IP}:${BACKEND_NODE_PORT}"
FRONTEND_URL="http://${VM_IP}:${FRONTEND_NODE_PORT}"

# Test backend connectivity
log_info "Testing backend API..."
if kubectl exec -n ${NAMESPACE} ${BACKEND_POD} -- curl -s http://localhost:${BACKEND_PORT} > /dev/null 2>&1; then
  log_success "Backend API is responding"
else
  log_warning "Could not verify backend API response"
fi

log_success "Phase 5 complete! Backend & Frontend are deployed."
echo ""

# Step 12: Access Information & Next Steps
log_step "Step 12: Access Information & Next Steps"

echo -e "${GREEN}🎉 Backend & Frontend Deployment Summary:${NC}"
echo ""
echo "🔗 Access URLs (via Port Forwarding):"
echo "   Frontend (UI):  http://${EXTERNAL_IP}:30173"
echo "   Backend (API):  http://${EXTERNAL_IP}:30888"
echo ""
echo "🔗 Internal Access URLs:"
echo "   Frontend (UI):  ${FRONTEND_URL}"
echo "   Backend (API):  ${BACKEND_URL}"
echo ""

echo "📋 Deployment Details:"
echo "   ✅ Backend: ${BACKEND_IMAGE}"
echo "      - Namespace: ${NAMESPACE}"
echo "      - Pod: ${BACKEND_POD}"
echo "      - Internal Port: ${BACKEND_PORT}"
echo "      - External Port: ${BACKEND_NODE_PORT}"
echo "      - Service: search-backend-svc"
echo ""
echo "   ✅ Frontend: ${FRONTEND_IMAGE}"
echo "      - Namespace: ${NAMESPACE}"
echo "      - Pod: ${FRONTEND_POD}"
echo "      - Internal Port: ${FRONTEND_PORT}"
echo "      - External Port: ${FRONTEND_NODE_PORT}"
echo "      - Service: search-frontend-svc"
echo ""

echo "🔌 Connected Services:"
echo "   ✅ MongoDB: ${MONGODB_SERVICE}:${MONGODB_PORT}"
echo "   ✅ Ollama: ${OLLAMA_SERVICE}:${OLLAMA_PORT} (${OLLAMA_MODEL})"
echo ""

echo "📋 Useful Commands:"
echo ""
echo "   # Check backend status"
echo "   kubectl get pods -n ${NAMESPACE} -l app=search-backend"
echo ""
echo "   # View backend logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-backend -f"
echo ""
echo "   # Check frontend status"
echo "   kubectl get pods -n ${NAMESPACE} -l app=search-frontend"
echo ""
echo "   # View frontend logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=search-frontend -f"
echo ""
echo "   # Test backend API"
echo "   curl ${BACKEND_URL}"
echo ""
echo "   # Port forward backend (alternative access)"
echo "   kubectl port-forward -n ${NAMESPACE} svc/search-backend-svc ${BACKEND_PORT}:${BACKEND_PORT}"
echo ""
echo "   # Port forward frontend (alternative access)"
echo "   kubectl port-forward -n ${NAMESPACE} svc/search-frontend-svc ${FRONTEND_PORT}:${FRONTEND_PORT}"
echo ""
echo "   # Restart backend"
echo "   kubectl rollout restart deployment/search-backend -n ${NAMESPACE}"
echo ""
echo "   # Restart frontend"
echo "   kubectl rollout restart deployment/search-frontend -n ${NAMESPACE}"
echo ""

echo "🔄 To rebuild and redeploy:"
echo "   1. Make your code changes"
echo "   2. Rebuild images:"
echo "      docker build -t ${BACKEND_IMAGE} ./backend"
echo "      docker build -t ${FRONTEND_IMAGE} ./frontend"
echo "   3. Load to minikube (if using minikube):"
echo "      minikube image load ${BACKEND_IMAGE}"
echo "      minikube image load ${FRONTEND_IMAGE}"
echo "   4. Restart deployments:"
echo "      kubectl rollout restart deployment/search-backend -n ${NAMESPACE}"
echo "      kubectl rollout restart deployment/search-frontend -n ${NAMESPACE}"
echo ""

echo "🎯 Complete Deployment Status:"
echo "   ✅ Phase 1: Ops Manager deployed"
echo "   ✅ Phase 2: MongoDB Enterprise deployed"
echo "   ✅ Phase 3: MongoDB Search deployed"
echo "   ✅ Phase 4: AI Models deployed"
echo "   ✅ Phase 5: Backend & Frontend deployed"
echo ""

echo -e "${GREEN}🚀 Your MongoDB Search application is now fully deployed!${NC}"
echo ""
echo "Open the frontend in your browser:"
echo "   http://${EXTERNAL_IP}:30173"
echo ""
echo "Or use internal access:"
echo "   ${FRONTEND_URL}"
echo ""

if command -v minikube &> /dev/null && kubectl config current-context | grep -q minikube; then
  log_info "For minikube users, you can also use:"
  echo "   minikube service search-frontend-svc -n ${NAMESPACE}"
fi

# Step 13: Setup Persistent Port Forwarding
log_step "Step 13: Setting up Persistent Port Forwarding"

log_info "Creating systemd service for automatic port forwarding..."
CURRENT_USER=$(whoami)

sudo tee /etc/systemd/system/k8s-port-forward.service > /dev/null <<EOF
[Unit]
Description=Kubernetes Port Forward for Search Frontend and Backend
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=/home/${CURRENT_USER}
Environment="KUBECONFIG=/home/${CURRENT_USER}/.kube/config"
ExecStartPre=/bin/sleep 30
ExecStart=/bin/bash -c 'kubectl port-forward -n mongodb svc/search-frontend-svc 30173:5173 --address 0.0.0.0 & kubectl port-forward -n mongodb svc/search-backend-svc 30888:8888 --address 0.0.0.0 & wait'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

log_info "Reloading systemd daemon..."
sudo systemctl daemon-reload

log_info "Enabling service to start on boot..."
sudo systemctl enable k8s-port-forward.service

log_info "Starting port forwarding service..."
sudo systemctl start k8s-port-forward.service

sleep 3

log_success "Port forwarding service installed and started!"
echo ""
echo "📋 Port Forwarding Service Commands:"
echo "   Check status:  sudo systemctl status k8s-port-forward.service"
echo "   View logs:     sudo journalctl -u k8s-port-forward.service -f"
echo "   Restart:       sudo systemctl restart k8s-port-forward.service"
echo ""

log_success "Phase 5 deployment complete! 🎉"

