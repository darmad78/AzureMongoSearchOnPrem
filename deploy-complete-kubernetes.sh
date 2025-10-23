#!/bin/bash
set -e

# Complete MongoDB Enterprise Search Application Deployment
# Deploys entire stack to Kubernetes: MongoDB Enterprise, Backend, Frontend, Ollama, Search

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
║    MongoDB Enterprise Complete Stack Deployment             ║
║    MongoDB + Search + Backend + Frontend + Ollama           ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-mongodb}"
MONGODB_VERSION="${MONGODB_VERSION:-8.0.3-ent}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SecureAdmin123!}"
USER_PASSWORD="${USER_PASSWORD:-SecureUser456!}"
SEARCH_PASSWORD="${SEARCH_PASSWORD:-SecureSearch789!}"

log_info "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  MongoDB Version: ${MONGODB_VERSION}"
echo ""

# Step 1: Clean existing deployment
log_step "Step 1: Cleaning Existing Resources"
log_info "Removing old Docker containers and volumes..."
docker compose down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker volume prune -f 2>/dev/null || true

log_info "Removing existing Kubernetes clusters..."
kind delete cluster --name mongodb-cluster 2>/dev/null || true
kind delete clusters --all 2>/dev/null || true
sleep 3
log_success "Cleanup complete"

# Step 2: Create Kubernetes cluster
log_step "Step 2: Creating Kubernetes Cluster"
log_info "Creating kind cluster 'mongodb-cluster'..."

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
    hostPort: 8080
    protocol: TCP
  - containerPort: 30003
    hostPort: 27017
    protocol: TCP
EOF

log_info "Waiting for cluster to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=300s

log_success "Kubernetes cluster created and ready"
kubectl get nodes

# Step 3: Create namespace
log_step "Step 3: Creating Namespace"
kubectl create namespace ${NAMESPACE}
log_success "Namespace '${NAMESPACE}' created"

# Step 4: Install MongoDB Enterprise Operator
log_step "Step 4: Installing MongoDB Enterprise Operator"
log_info "Adding MongoDB Helm repository..."
helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

log_info "Installing Enterprise Operator..."
helm install enterprise-operator mongodb/enterprise-operator \
  --namespace ${NAMESPACE} \
  --set operator.watchNamespace="${NAMESPACE}" \
  --wait --timeout=5m

log_success "MongoDB Enterprise Operator installed"

# Step 5: Deploy Ops Manager
log_step "Step 5: Deploying MongoDB Ops Manager"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ops-manager-config
  namespace: ${NAMESPACE}
data:
  projectName: "mongodb-project"
  orgId: "mongodb-org"
  baseUrl: "http://ops-manager-svc.${NAMESPACE}.svc.cluster.local:8080"
---
apiVersion: v1
kind: Secret
metadata:
  name: ops-manager-credentials
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  user: "opsmanager"
  publicApiKey: "ops-manager-key"
  adminUser: "admin"
  adminPassword: "admin123"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-manager
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-manager
  template:
    metadata:
      labels:
        app: ops-manager
    spec:
      containers:
      - name: ops-manager
        image: quay.io/mongodb/mongodb-enterprise-ops-manager-ubi:latest
        ports:
        - containerPort: 8080
        env:
        - name: OM_ADMIN_EMAIL
          value: admin@example.com
        - name: OM_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ops-manager-credentials
              key: adminPassword
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
        volumeMounts:
        - name: ops-manager-data
          mountPath: /data
      volumes:
      - name: ops-manager-data
        persistentVolumeClaim:
          claimName: ops-manager-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ops-manager-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ops-manager
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
  type: LoadBalancer
EOF

log_info "Waiting for Ops Manager to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/ops-manager -n ${NAMESPACE} || log_warning "Ops Manager may still be starting..."
log_success "Ops Manager deployed"

# Step 6: Deploy MongoDB Enterprise
log_step "Step 6: Deploying MongoDB Enterprise (3-node Replica Set)"

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
  credentials: ops-manager-credentials
  opsManager:
    configMapRef:
      name: ops-manager-config
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
EOF

log_info "Waiting for MongoDB to be ready..."
kubectl wait --for=jsonpath='{.status.phase}'=Running mdb/mongodb-rs -n ${NAMESPACE} --timeout=600s || log_warning "MongoDB may still be initializing..."
log_success "MongoDB Enterprise deployed"

# Step 7: Create MongoDB Users
log_step "Step 7: Creating MongoDB Users"

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
EOF

log_success "MongoDB users created"

# Step 8: Deploy MongoDB Search (mongot)
log_step "Step 8: Deploying MongoDB Search (Vector Search)"

kubectl create secret generic search-password \
  -n ${NAMESPACE} \
  --from-literal=password="${SEARCH_PASSWORD}"

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: search-user
  namespace: ${NAMESPACE}
spec:
  username: searchuser
  db: admin
  mongodbResourceRef:
    name: mongodb-rs
  passwordSecretKeyRef:
    name: search-password
    key: password
  roles:
    - name: clusterMonitor
      db: admin
    - name: readAnyDatabase
      db: admin
---
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

# Step 9: Deploy Ollama
log_step "Step 9: Deploying Ollama (Local LLM)"

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
      storage: 10Gi
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
        resources:
          requests:
            cpu: "500m"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
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
    - protocol: TCP
      port: 11434
      targetPort: 11434
EOF

log_success "Ollama deployed"

# Step 10: Deploy Backend
log_step "Step 10: Deploying Backend (FastAPI + AI)"

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
            apt-get update && apt-get install -y git
            git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git /app
            cd /app/backend
            pip install -r requirements.txt
            uvicorn main:app --host 0.0.0.0 --port 8000
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: backend-config
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"
            memory: "3Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: backend
  ports:
    - protocol: TCP
      port: 8000
      targetPort: 8000
  type: LoadBalancer
EOF

log_success "Backend deployed"

# Step 11: Deploy Frontend
log_step "Step 11: Deploying Frontend (React + Vite)"

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
            git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git /app
            cd /app/frontend
            npm install
            npm run dev -- --host 0.0.0.0
        ports:
        - containerPort: 5173
        env:
        - name: VITE_API_URL
          value: "http://backend-svc.${NAMESPACE}.svc.cluster.local:8000"
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "1"
            memory: "1Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: frontend
  ports:
    - protocol: TCP
      port: 5173
      targetPort: 5173
  type: LoadBalancer
EOF

log_success "Frontend deployed"

# Step 12: Summary
log_step "Deployment Complete!"

echo -e "\n${GREEN}🎉 MongoDB Enterprise Complete Stack is Deployed!${NC}\n"

echo "📊 Deployment Summary:"
echo "   Namespace: ${NAMESPACE}"
echo "   MongoDB Enterprise: 3-node replica set"
echo "   MongoDB Search: Vector search enabled"
echo "   Ops Manager: Monitoring & management"
echo "   Backend: FastAPI + AI models"
echo "   Frontend: React + Vite"
echo "   Ollama: Local LLM server"
echo ""

echo "🔗 Access Information:"
echo ""
echo "   Get service URLs:"
echo "   kubectl get services -n ${NAMESPACE}"
echo ""

echo "   MongoDB Connection:"
echo "   mongodb://appuser:${USER_PASSWORD}@mongodb-rs-svc.${NAMESPACE}.svc.cluster.local:27017/searchdb?replicaSet=mongodb-rs&authSource=admin"
echo ""

echo "   Port-forward services to access locally:"
echo "   kubectl port-forward -n ${NAMESPACE} service/frontend-svc 5173:5173"
echo "   kubectl port-forward -n ${NAMESPACE} service/backend-svc 8000:8000"
echo "   kubectl port-forward -n ${NAMESPACE} service/ops-manager-svc 8080:8080"
echo ""

echo "📋 Useful Commands:"
echo "   # Check all pods"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "   # Check MongoDB status"
echo "   kubectl get mdb -n ${NAMESPACE}"
echo "   kubectl get mdbs -n ${NAMESPACE}"
echo ""
echo "   # View logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=backend"
echo "   kubectl logs -n ${NAMESPACE} -l app=frontend"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it mongodb-rs-0 -n ${NAMESPACE} -- mongosh -u admin -p ${ADMIN_PASSWORD} --authenticationDatabase admin"
echo ""

echo "🎯 Next Steps:"
echo "   1. Wait for all pods to be Running (may take 5-10 minutes)"
echo "   2. Port-forward the frontend service"
echo "   3. Access the application in your browser"
echo "   4. Upload documents and test search"
echo ""

log_info "Monitor deployment:"
echo "   kubectl get pods -n ${NAMESPACE} -w"
echo ""

log_success "Deployment script completed successfully!"

