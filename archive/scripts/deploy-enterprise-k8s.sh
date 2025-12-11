#!/bin/bash
set -e

# MongoDB Enterprise + Search Direct Deployment to Kubernetes
# NO Ops Manager, NO Kubernetes Operator
# Pure MongoDB Enterprise StatefulSet + mongot + Application Stack

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
║   MongoDB Enterprise + Search Stack (Direct Deployment)     ║
║   NO Ops Manager | NO Operator | Pure StatefulSets          ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-mongodb}"
MONGODB_VERSION="${MONGODB_VERSION:-8.2.1-ubuntu2204}"
MONGOT_VERSION="${MONGOT_VERSION:-2.1.2}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SecureAdmin123!}"
USER_PASSWORD="${USER_PASSWORD:-SecureUser456!}"

log_info "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  MongoDB Enterprise: ${MONGODB_VERSION}"
echo "  MongoDB Search (mongot): ${MONGOT_VERSION}"
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
  - containerPort: 30003
    hostPort: 27080
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

# Step 3: Create MongoDB Keyfile Secret
log_step "Step 3: Creating MongoDB Security"
log_info "Generating replica set keyfile..."
KEYFILE=$(openssl rand -base64 756 | tr -d '\n')
kubectl create secret generic mongodb-keyfile \
  -n ${NAMESPACE} \
  --from-literal=keyfile="${KEYFILE}"

kubectl create secret generic mongodb-admin-password \
  -n ${NAMESPACE} \
  --from-literal=password="${ADMIN_PASSWORD}"

kubectl create secret generic mongodb-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="${USER_PASSWORD}"

log_success "Security credentials created"

# Step 4: Deploy MongoDB Enterprise StatefulSet
log_step "Step 4: Deploying MongoDB Enterprise (3-node Replica Set)"

kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-svc
  namespace: ${NAMESPACE}
spec:
  clusterIP: None
  selector:
    app: mongodb
  ports:
  - port: 27017
    targetPort: 27017
    name: mongodb
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-external
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: mongodb
  ports:
  - port: 27017
    targetPort: 27017
    nodePort: 30002
    name: mongodb
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
spec:
  serviceName: mongodb-svc
  replicas: 3
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      securityContext:
        fsGroup: 999
        runAsUser: 0
      initContainers:
      - name: setup-keyfile
        image: busybox
        command:
        - sh
        - -c
        - |
          cp /tmp/keyfile/keyfile /data/keyfile/mongodb.key
          chmod 400 /data/keyfile/mongodb.key
          chown 999:999 /data/keyfile/mongodb.key
          chown -R 999:999 /data/db
        volumeMounts:
        - name: keyfile
          mountPath: /tmp/keyfile
          readOnly: true
        - name: keyfile-dir
          mountPath: /data/keyfile
        - name: mongodb-data
          mountPath: /data/db
      containers:
      - name: mongodb
        image: mongodb/mongodb-enterprise-server:${MONGODB_VERSION}
        command:
        - bash
        - -c
        - |
          set -e
          echo "Starting MongoDB Enterprise..."
          
          # Start MongoDB with search parameters
          exec mongod \
            --replSet rs0 \
            --bind_ip_all \
            --auth \
            --keyFile /data/keyfile/mongodb.key \
            --setParameter searchIndexManagementHostAndPort=mongot-svc.${NAMESPACE}.svc.cluster.local:27080 \
            --setParameter mongotHost=mongot-svc.${NAMESPACE}.svc.cluster.local:27080
        ports:
        - containerPort: 27017
          name: mongodb
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
        - name: keyfile-dir
          mountPath: /data/keyfile
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
      volumes:
      - name: keyfile
        secret:
          secretName: mongodb-keyfile
          defaultMode: 0400
      - name: keyfile-dir
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
EOF

log_info "Waiting for MongoDB pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=mongodb -n ${NAMESPACE} --timeout=300s

log_success "MongoDB Enterprise pods running"

# Step 5: Initialize Replica Set
log_step "Step 5: Initializing Replica Set"

kubectl exec -n ${NAMESPACE} mongodb-0 -- mongosh --eval '
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongodb-0.mongodb-svc.${NAMESPACE}.svc.cluster.local:27017" },
    { _id: 1, host: "mongodb-1.mongodb-svc.${NAMESPACE}.svc.cluster.local:27017" },
    { _id: 2, host: "mongodb-2.mongodb-svc.${NAMESPACE}.svc.cluster.local:27017" }
  ]
})
' || log_warning "Replica set may already be initialized"

log_info "Waiting for replica set to stabilize..."
sleep 15

log_success "Replica set initialized"

# Step 6: Create MongoDB Users
log_step "Step 6: Creating MongoDB Users"

kubectl exec -n ${NAMESPACE} mongodb-0 -- mongosh --eval "
db.getSiblingDB('admin').createUser({
  user: 'admin',
  pwd: '${ADMIN_PASSWORD}',
  roles: [
    { role: 'root', db: 'admin' },
    { role: 'clusterAdmin', db: 'admin' }
  ]
})
" || log_warning "Admin user may already exist"

sleep 5

kubectl exec -n ${NAMESPACE} mongodb-0 -- mongosh -u admin -p "${ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
db.getSiblingDB('admin').createUser({
  user: 'appuser',
  pwd: '${USER_PASSWORD}',
  roles: [
    { role: 'readWrite', db: 'searchdb' },
    { role: 'clusterMonitor', db: 'admin' }
  ]
})

db.getSiblingDB('searchdb').createCollection('documents')
" || log_warning "App user may already exist"

log_success "MongoDB users created"

# Step 7: Deploy MongoDB Search (mongot)
log_step "Step 7: Deploying MongoDB Search (mongot)"

kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: mongot-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: mongot
  ports:
  - port: 27080
    targetPort: 27080
    name: mongot
  - port: 27097
    targetPort: 27097
    name: mongot-metrics
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongot
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mongot
  template:
    metadata:
      labels:
        app: mongot
    spec:
      containers:
      - name: mongot
        image: mongodb/mongodb-enterprise-search:latest
        ports:
        - containerPort: 27080
          name: mongot
        - containerPort: 27097
          name: metrics
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
EOF

log_info "Waiting for mongot to be ready..."
kubectl wait --for=condition=Available deployment/mongot -n ${NAMESPACE} --timeout=300s

log_success "MongoDB Search deployed"

# Step 8: Deploy Ollama
log_step "Step 8: Deploying Ollama (Local LLM)"

kubectl apply -f - <<EOF
---
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
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: ${NAMESPACE}
data:
  MONGODB_URL: "mongodb://appuser:${USER_PASSWORD}@mongodb-svc.${NAMESPACE}.svc.cluster.local:27017/searchdb?replicaSet=rs0&authSource=admin"
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
---
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
echo "   ✅ MongoDB Enterprise: 3-node replica set"
echo "   ✅ MongoDB Search (mongot): 2 replicas"
echo "   ✅ Backend: FastAPI + AI models"
echo "   ✅ Frontend: React + Vite"
echo "   ✅ Ollama: Local LLM server"
echo ""

echo "🔗 Access URLs (from your VM):"
echo "   Frontend:  http://localhost:5173"
echo "   Backend:   http://localhost:8000"
echo "   MongoDB:   mongodb://appuser:${USER_PASSWORD}@localhost:27017/searchdb?replicaSet=rs0&authSource=admin"
echo ""

echo "📋 Useful Commands:"
echo "   # Check all pods"
echo "   kubectl get pods -n ${NAMESPACE}"
echo ""
echo "   # Check services"
echo "   kubectl get svc -n ${NAMESPACE}"
echo ""
echo "   # View backend logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=backend -f"
echo ""
echo "   # View frontend logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=frontend -f"
echo ""
echo "   # Access MongoDB shell"
echo "   kubectl exec -it mongodb-0 -n ${NAMESPACE} -- mongosh -u admin -p ${ADMIN_PASSWORD} --authenticationDatabase admin"
echo ""

echo "🎯 Next Steps:"
echo "   1. Wait for all pods to be Running (check with: kubectl get pods -n ${NAMESPACE})"
echo "   2. Access the frontend at http://localhost:5173"
echo "   3. Upload documents and test search"
echo ""

log_success "Deployment script completed successfully!"

