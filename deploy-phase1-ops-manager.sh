#!/bin/bash
set -e

# Phase 1: Deploy Self-Hosted Ops Manager
# This deploys Ops Manager in Kubernetes following MongoDB's official installation guide

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
log_step() { echo -e "\n${YELLOW}🚀 $1${NC}\n=================================================="; }

# Configuration
K8S_CLUSTER_NAME="mongodb-cluster"
OPS_MANAGER_NAMESPACE="ops-manager"
MONGODB_OPERATOR_NAMESPACE="mongodb"
VM_IP=$(hostname -I | awk '{print $1}')

echo -e "╔══════════════════════════════════════════════════════════════╗"
echo -e "║                    Phase 1: Ops Manager Setup              ║"
echo -e "╚══════════════════════════════════════════════════════════════╝"
echo "VM IP: ${VM_IP}"
echo ""

# Step 1: Verify Prerequisites
log_step "Step 1: Verifying Prerequisites"
log_info "Checking kubectl connectivity..."

if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl is not connected to a Kubernetes cluster"
    exit 1
fi

log_success "kubectl is connected to Kubernetes cluster"

# Step 2: Install MongoDB Enterprise Operator
log_step "Step 2: Installing MongoDB Enterprise Operator"
log_info "Cleaning existing MongoDB operator installations..."

helm uninstall mongodb-kubernetes -n mongodb 2>/dev/null || true
helm uninstall mongodb-kubernetes -n mongodb-enterprise-operator 2>/dev/null || true

kubectl delete namespace mongodb-enterprise-operator 2>/dev/null || true

log_info "Adding MongoDB Helm repository..."

helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update

log_info "Installing MongoDB Kubernetes Operator..."
helm install mongodb-kubernetes mongodb/mongodb-kubernetes \
    --namespace mongodb-enterprise-operator \
    --create-namespace \
    --wait

log_success "MongoDB Kubernetes Operator installed"

# Step 3: Deploy MongoDB Application Database (for Ops Manager)
log_step "Step 3: Deploying MongoDB Application Database"
log_info "Creating namespace and MongoDB instance for Ops Manager..."

kubectl create namespace ${OPS_MANAGER_NAMESPACE} || true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-manager-appdb
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-manager-appdb
  template:
    metadata:
      labels:
        app: ops-manager-appdb
    spec:
      containers:
      - name: mongodb
        image: mongo:8.0
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: "admin123"
        volumeMounts:
        - name: appdb-data
          mountPath: /data/appdb
        resources:
          requests:
            cpu: "1"
            memory: "4Gi"
          limits:
            cpu: "2"
            memory: "8Gi"
      volumes:
      - name: appdb-data
        persistentVolumeClaim:
          claimName: ops-manager-appdb-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-appdb-pvc
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ops-manager-appdb-svc
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  selector:
    app: ops-manager-appdb
  ports:
  - port: 27017
    targetPort: 27017
  type: ClusterIP
EOF

log_info "Waiting for MongoDB Application Database to be ready..."
kubectl wait --for=condition=Available deployment/ops-manager-appdb -n ${OPS_MANAGER_NAMESPACE} --timeout=300s
log_success "MongoDB Application Database deployed"

# Step 4: Deploy Ops Manager with RPM Installation
log_step "Step 4: Deploying Ops Manager Application"
log_info "Creating Ops Manager deployment with manual RPM installation..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-pvc
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
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
      securityContext:
        runAsUser: 0
      initContainers:
      - name: install-ops-manager
        image: redhat/ubi8:latest
        command: 
          - /bin/bash
          - -c
          - |
            set -e
            echo "Installing Ops Manager dependencies..."
            yum install -y wget curl systemd
            
            echo "Downloading Ops Manager RPM..."
            cd /tmp
            wget -q https://downloads.mongodb.com/on-prem-mms/rpm/mongodb-mms-13.0.0.x86_64.rpm
            
            echo "Installing Ops Manager..."
            rpm -ivh mongodb-mms-13.0.0.x86_64.rpm
            
            echo "Copying Ops Manager to persistent volume..."
            cp -r /opt/mongodb/mms /mnt/ops-manager-data/
        volumeMounts:
        - name: ops-manager-data
          mountPath: /mnt/ops-manager-data
      containers:
      - name: ops-manager
        image: redhat/ubi8:latest
        command:
          - /bin/bash
          - -c
          - |
            set -e
            # Update MongoDB connection string in config
            sed -i "s|mongo.mongoUri=.*|mongo.mongoUri=mongodb://admin:admin123@ops-manager-appdb-svc:27017/mms?authSource=admin|g" /mnt/ops-manager-data/mms/conf/conf-mms.properties
            
            # Start Ops Manager
            /mnt/ops-manager-data/mms/bin/start.sh
            
            # Keep running
            sleep infinity
        ports:
        - containerPort: 8080
          name: web
        env:
        - name: MMS_HOME
          value: "/mnt/ops-manager-data/mms"
        volumeMounts:
        - name: ops-manager-data
          mountPath: /mnt/ops-manager-data
        resources:
          requests:
            cpu: "2"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
        readinessProbe:
          httpGet:
            path: /api/public/v1.0/status
            port: 8080
          initialDelaySeconds: 180
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 5
        livenessProbe:
          httpGet:
            path: /api/public/v1.0/status
            port: 8080
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
      volumes:
      - name: ops-manager-data
        persistentVolumeClaim:
          claimName: ops-manager-pvc
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
    name: web
  type: NodePort
EOF

log_info "Waiting for Ops Manager to be ready (this may take several minutes)..."
kubectl wait --for=condition=Available deployment/ops-manager -n ${OPS_MANAGER_NAMESPACE} --timeout=900s || log_warning "Timeout waiting for Ops Manager"

# Step 5: Verify Deployment
log_step "Step 5: Verifying Deployment"
log_info "Checking pod status..."

kubectl get pods -n ${OPS_MANAGER_NAMESPACE}

log_info "Checking Ops Manager logs..."
kubectl logs -n ${OPS_MANAGER_NAMESPACE} -l app=ops-manager --tail=30

log_success "Ops Manager deployment complete"

# Step 6: Get Ops Manager Access Information
log_step "Step 6: Ops Manager Access Information"

OPS_MANAGER_PORT=$(kubectl get svc ops-manager-svc -n ${OPS_MANAGER_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
OPS_MANAGER_URL="http://${VM_IP}:${OPS_MANAGER_PORT}"

echo -e "${GREEN}🎉 Ops Manager is deployed!${NC}"
echo -e "${BLUE}📋 Access Information:${NC}"
echo "   URL: ${OPS_MANAGER_URL}"
echo "   VM IP: ${VM_IP}"
echo "   Port: ${OPS_MANAGER_PORT}"
echo ""

# Step 7: Web UI Setup Instructions
log_step "Step 7: Complete Web UI Setup"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Ops Manager Web UI Setup Required             ║
╚══════════════════════════════════════════════════════════════╝

Please open the Ops Manager URL in your browser and complete:

1.  **Open Ops Manager**: Navigate to the URL above
2.  **Sign Up**: Create the first admin user
3.  **Create Organization**: Name it "MongoDB Search Demo"
4.  **Create Project**: Name it "Search Project"
5.  **Generate API Keys**: 
    - Go to Project Settings → Access Manager → API Keys
    - Generate new API Key (Public and Private)
6.  **Add VM IP to API Access List**: Add your VM's IP to allow Kubernetes Operator communication
7.  **Save Credentials**: Keep Organization ID, Project ID, and API Keys for Phase 2

EOF
echo -e "${NC}"

log_success "Phase 1 deployment complete!"