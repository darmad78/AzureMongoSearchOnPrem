#!/bin/bash
set -e

# MongoDB Enterprise + Search Stack Deployment
# Uses Cloud Manager (cloud.mongodb.com) for operator management
# Deploys MongoDB Enterprise + mongot + Backend + Frontend + Ollama

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
║  MongoDB Enterprise Stack with Cloud Manager                ║
║  MongoDB + mongot + Backend + Frontend + Ollama             ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-mongodb}"
MONGODB_VERSION="${MONGODB_VERSION:-8.2.1-ent}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SecureAdmin123!}"
USER_PASSWORD="${USER_PASSWORD:-SecureUser456!}"

# Cloud Manager Credentials (set via environment or prompt)
if [ -z "$CM_ORG_ID" ] || [ -z "$CM_PROJECT_ID" ] || [ -z "$CM_PUBLIC_KEY" ] || [ -z "$CM_PRIVATE_KEY" ]; then
    echo -e "${YELLOW}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Cloud Manager Credentials Required             ║
╚══════════════════════════════════════════════════════════════╝

To use MongoDB Enterprise Operator, you need Cloud Manager credentials.

Get them from: https://cloud.mongodb.com/
  1. Login or sign up (free tier available)
  2. Create/select a project
  3. Go to: Project Settings → Access Manager → API Keys
  4. Create API Key with "Project Owner" role
  5. Copy the credentials below

EOF
    echo -e "${NC}"
    
    read -p "Enter Organization ID: " CM_ORG_ID
    read -p "Enter Project ID: " CM_PROJECT_ID
    read -p "Enter Public API Key: " CM_PUBLIC_KEY
    read -sp "Enter Private API Key: " CM_PRIVATE_KEY
    echo ""
fi

log_info "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  MongoDB Version: ${MONGODB_VERSION}"
echo "  Cloud Manager Org: ${CM_ORG_ID}"
echo "  Cloud Manager Project: ${CM_PROJECT_ID}"
echo ""

# Step 1: Clean existing deployment
log_step "Step 1: Cleaning Existing Resources"
log_info "Removing old Docker containers and volumes..."
docker compose down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

log_info "Checking for existing Kubernetes cluster..."
if kind get clusters 2>/dev/null | grep -q "mongodb-cluster"; then
    log_info "Reusing existing kind cluster 'mongodb-cluster'"
else
    log_info "Creating new kind cluster 'mongodb-cluster'..."
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
    hostPort: 27017
    protocol: TCP
EOF
    log_info "Waiting for cluster to be ready..."
    sleep 10
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
fi

log_info "Deleting existing namespace if present..."
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --wait=true 2>/dev/null || true
sleep 5

log_success "Cleanup complete"

# Step 2: Create namespace
log_step "Step 2: Creating Namespace"
kubectl create namespace ${NAMESPACE}
log_success "Namespace '${NAMESPACE}' created"

# Step 3: Install MongoDB Enterprise Kubernetes Operator
log_step "Step 3: Installing MongoDB Enterprise Kubernetes Operator"
log_info "Adding MongoDB Helm repository..."
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

log_info "Installing Enterprise Operator..."
helm install enterprise-operator mongodb/enterprise-operator \
  --namespace ${NAMESPACE} \
  --set operator.watchNamespace="${NAMESPACE}" \
  --wait --timeout=5m

log_success "MongoDB Enterprise Operator installed"

# Step 4: Configure Cloud Manager Connection
log_step "Step 4: Configuring Cloud Manager Connection"

kubectl create secret generic cloud-manager-credentials \
  -n ${NAMESPACE} \
  --from-literal="publicKey=${CM_PUBLIC_KEY}" \
  --from-literal="privateKey=${CM_PRIVATE_KEY}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloud-manager-config
  namespace: ${NAMESPACE}
data:
  projectName: "k8s-mongodb-project"
  orgId: "${CM_ORG_ID}"
  baseUrl: "https://cloud.mongodb.com"
EOF

log_success "Cloud Manager connection configured"

# Step 5: Deploy MongoDB Enterprise
log_step "Step 5: Deploying MongoDB Enterprise (3-node Replica Set)"

kubectl create secret generic mongodb-admin-password \
  -n ${NAMESPACE} \
  --from-literal=password="${ADMIN_PASSWORD}"

kubectl create secret generic mongodb-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="${USER_PASSWORD}"

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
  credentials: cloud-manager-credentials
  cloudManager:
    configMapRef:
      name: cloud-manager-config
  security:
    authentication:
      enabled: true
      modes: ["SCRAM"]
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
  - port: 27017
    targetPort: 27017
    nodePort: 30002
EOF

log_info "Waiting for MongoDB to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running mdb/mongodb-rs -n ${NAMESPACE} --timeout=600s || log_warning "MongoDB may still be initializing..."

log_success "MongoDB Enterprise deployed"

# Step 6: Create MongoDB Users
log_step "Step 6: Creating MongoDB Users"

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
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: search-sync-user
  namespace: ${NAMESPACE}
spec:
  username: search-sync
  db: admin
  mongodbResourceRef:
    name: mongodb-rs
  passwordSecretKeyRef:
    name: mongodb-user-password
    key: password
  roles:
    - name: searchCoordinator
      db: admin
EOF

log_success "MongoDB users created"

# Step 7: Deploy MongoDB Search (mongot)
log_step "Step 7: Deploying MongoDB Search (mongot)"

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: mongodb-rs
  namespace: ${NAMESPACE}
spec:
  resourceRequirements:
    requests:
      cpu: "2"
      memory: "3Gi"
    limits:
      cpu: "3"
      memory: "5Gi"
EOF

log_info "Waiting for MongoDB Search to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running mdbs/mongodb-rs -n ${NAMESPACE} --timeout=300s || log_warning "Search may still be initializing..."

log_success "MongoDB Search deployed"

# Step 8: Deploy Ollama
log_step "Step 8: Deploying Ollama (Local LLM)"

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

# Step 9: Deploy Backend
log_step "Step 9: Deploying Backend (FastAPI + AI)"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: ${NAMESPACE}
data:
  MONGODB_URL: "mongodb://appuser:${USER_PASSWORD}@mongodb-rs-svc.${NAMESPACE}.svc.cluster.local:27017/searchdb?replicaSet=mongodb-rs&authSource=admin"
  LLM_PROVIDER: "ollama"
  OLLAMA_URL: "http://ollama-svc.${NAMESPACE}.svc.cluster.local:11434"
  OLLAMA_MODEL: "llama2"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: python:3.11-slim
        command: ["/bin/bash", "-c"]
        args:
          - |
            apt-get update && apt-get install -y git ffmpeg
            git clone https://github.com/darmad78/RAGOnPremMongoDB.git /app
            cd /app/backend
            pip install --no-cache-dir -r requirements.txt
            uvicorn main:app --host 0.0.0.0 --port 8000
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: backend-config
        resources:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: backend
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30001
EOF

log_success "Backend deployed"

# Step 10: Deploy Frontend
log_step "Step 10: Deploying Frontend (React + Vite)"

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: node:18-alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            apk add --no-cache git
            git clone https://github.com/darmad78/RAGOnPremMongoDB.git /app
            cd /app/frontend
            npm install
            npm run dev -- --host 0.0.0.0
        ports:
        - containerPort: 5173
        env:
        - name: VITE_API_URL
          value: "http://localhost:8000"
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
  name: frontend-svc
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 5173
    targetPort: 5173
    nodePort: 30000
EOF

log_success "Frontend deployed"

# Step 11: Summary
log_step "Deployment Complete!"

echo -e "\n${GREEN}🎉 MongoDB Enterprise + Search Stack is Deployed!${NC}\n"

echo "📊 Deployment Summary:"
echo "   ✅ MongoDB Enterprise: 3-node replica set (Cloud Manager)"
echo "   ✅ MongoDB Search (mongot): Managed by operator"
echo "   ✅ Backend: FastAPI + AI models"
echo "   ✅ Frontend: React + Vite"
echo "   ✅ Ollama: Local LLM server"
echo ""

echo "🔗 Access URLs (from your VM):"
echo "   Frontend:  http://localhost:5173"
echo "   Backend:   http://localhost:8000"
echo "   MongoDB:   mongodb://appuser:${USER_PASSWORD}@localhost:27017/searchdb?replicaSet=mongodb-rs&authSource=admin"
echo ""

echo "☁️  Cloud Manager:"
echo "   View your cluster at: https://cloud.mongodb.com/v2/${CM_ORG_ID}#/clusters"
echo ""

echo "📋 Useful Commands:"
echo "   # Check all pods"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "   # Check MongoDB resource"
echo "   kubectl get mdb -n ${NAMESPACE}"
echo ""
echo "   # Check MongoDB Search resource"
echo "   kubectl get mdbs -n ${NAMESPACE}"
echo ""
echo "   # View backend logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=backend -f"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it mongodb-rs-0 -n ${NAMESPACE} -- mongosh -u admin -p ${ADMIN_PASSWORD} --authenticationDatabase admin"
echo ""

echo "🎯 Next Steps:"
echo "   1. Wait for all pods to be Running (5-10 minutes)"
echo "   2. Check Cloud Manager to see your cluster"
echo "   3. Access the frontend at http://localhost:5173"
echo "   4. Upload documents and test search"
echo ""

log_info "Monitor deployment:"
echo "   kubectl get pods -n ${NAMESPACE} -w"
echo ""

log_success "Deployment script completed successfully!"

