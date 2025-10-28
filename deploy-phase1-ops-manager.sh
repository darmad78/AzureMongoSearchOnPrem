#!/bin/bash
set -e

# Phase 1: Deploy Self-Hosted Ops Manager
# This deploys Ops Manager in Kubernetes, then guides you through web UI setup

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
║                    Phase 1: Ops Manager Setup              ║
║              Self-Hosted Ops Manager in Kubernetes         ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
OPS_MANAGER_NAMESPACE="ops-manager"

# Step 1: Clean Environment
log_step "Step 1: Cleaning Environment"
log_info "Removing old deployments..."

# Clean Kubernetes
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --wait=true 2>/dev/null || true
kubectl delete namespace ${OPS_MANAGER_NAMESPACE} --ignore-not-found=true --wait=true 2>/dev/null || true

# Clean kind clusters
kind delete cluster --name mongodb-cluster 2>/dev/null || true
kind delete clusters --all 2>/dev/null || true

sleep 5
log_success "Environment cleaned"

# Step 2: Create Kubernetes Cluster
log_step "Step 2: Creating Kubernetes Cluster"
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
    hostPort: 8080
    protocol: TCP
  - containerPort: 30001
    hostPort: 27017
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

# Step 3: Install MongoDB Kubernetes Operator
log_step "Step 3: Installing MongoDB Kubernetes Operator"
log_info "Installing MongoDB Kubernetes Operator..."

helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update

helm install mongodb-kubernetes mongodb/mongodb-kubernetes \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --wait

log_success "MongoDB Kubernetes Operator installed"

# Step 4: Deploy Ops Manager Application
log_step "Step 4: Deploying Ops Manager Application"
log_info "Deploying Ops Manager application..."

kubectl create namespace ${OPS_MANAGER_NAMESPACE}

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-data-pvc
  namespace: ${OPS_MANAGER_NAMESPACE}
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
  name: ops-manager
  namespace: ${OPS_MANAGER_NAMESPACE}
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
        image: quay.io/mongodb/mongodb-enterprise-ops-manager-ubi:8.0.15
        ports:
        - containerPort: 8080
        env:
        - name: MMS_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MMS_INITDB_ROOT_PASSWORD
          value: "admin123"
        - name: MMS_INITDB_DATABASE
          value: "mms"
        volumeMounts:
        - name: ops-manager-data
          mountPath: /data
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
        readinessProbe:
          httpGet:
            path: /api/public/v1.0/status
            port: 8080
          initialDelaySeconds: 120
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /api/public/v1.0/status
            port: 8080
          initialDelaySeconds: 180
          periodSeconds: 30
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
      volumes:
      - name: ops-manager-data
        persistentVolumeClaim:
          claimName: ops-manager-data-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ops-manager-svc
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  selector:
    app: ops-manager
  ports:
  - port: 8080
    targetPort: 8080
  type: NodePort
EOF

log_info "Waiting for Ops Manager to be ready..."
kubectl wait --for=condition=Available deployment/ops-manager -n ${OPS_MANAGER_NAMESPACE} --timeout=600s
log_success "Ops Manager deployed"

# Step 5: Get Ops Manager Access Information
log_step "Step 5: Ops Manager Access Information"
log_info "Getting Ops Manager access details..."

OPS_MANAGER_PORT=$(kubectl get svc ops-manager-svc -n ${OPS_MANAGER_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
OPS_MANAGER_URL="http://${VM_IP}:${OPS_MANAGER_PORT}"

echo ""
echo "🎉 Ops Manager is now running!"
echo ""
echo "📋 Access Information:"
echo "   URL: ${OPS_MANAGER_URL}"
echo "   VM IP: ${VM_IP}"
echo "   Port: ${OPS_MANAGER_PORT}"
echo ""

# Step 6: Web UI Setup Instructions
log_step "Step 6: Web UI Setup Instructions"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Ops Manager Web UI Setup Required             ║
╚══════════════════════════════════════════════════════════════╝

Please complete the following steps in Ops Manager:

1. Open Ops Manager in your browser:
   http://YOUR_VM_IP:8080

2. Click "Sign Up" to register the first user

3. Create your first organization:
   - Organization Name: "MongoDB Search Demo"
   - Note the Organization ID (you'll need this)

4. Create your first project:
   - Project Name: "Search Project"
   - Note the Project ID (you'll need this)

5. Go to Project Settings → Access Manager → API Keys

6. Create a new API Key:
   - Description: "Kubernetes Operator"
   - Role: "Project Owner"
   - Note the Public Key and Private Key (you'll need these)

7. Add your VM IP to API Access List:
   - Go to Organization Settings → API Access List
   - Add your VM IP address

8. Save these credentials for Phase 2:
   - Organization ID: [COPY THIS]
   - Project ID: [COPY THIS]
   - Public API Key: [COPY THIS]
   - Private API Key: [COPY THIS]

Once you have these credentials, run:
   ./deploy-phase2-mongodb-enterprise.sh

EOF
echo -e "${NC}"

log_success "Phase 1 complete! Ops Manager is running and ready for setup."
echo ""
echo "🔗 Next Steps:"
echo "   1. Complete the web UI setup above"
echo "   2. Save your credentials"
echo "   3. Run Phase 2: ./deploy-phase2-mongodb-enterprise.sh"
echo ""
