#!/bin/bash
set -e

# Phase 1: Deploy Ops Manager on VM + MongoDB in Kubernetes
# With proper networking via kubectl port-forward

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
OPS_MANAGER_NAMESPACE="ops-manager"
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

# Step 3: Create Ops Manager Application Database in Kubernetes
log_step "Step 3: Deploying MongoDB Application Database in Kubernetes"
log_info "Creating namespace and MongoDB instance..."

kubectl create namespace ${OPS_MANAGER_NAMESPACE} || true

kubectl apply -f - <<EOF
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
          mountPath: /data/db
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

# Step 4: Setup Port Forward for K8s MongoDB
log_step "Step 4: Setting up port-forward to K8s MongoDB"
log_info "Creating port-forward (27017:27017)..."

# Kill any existing port-forwards
pkill -f "kubectl port-forward.*ops-manager-appdb-svc" 2>/dev/null || true

# Start port-forward in background
kubectl port-forward -n ${OPS_MANAGER_NAMESPACE} svc/ops-manager-appdb-svc 27017:27017 > /tmp/port-forward.log 2>&1 &
PORT_FORWARD_PID=$!

log_info "Waiting for port-forward to establish..."
sleep 5

if kill -0 $PORT_FORWARD_PID 2>/dev/null; then
    log_success "Port-forward established (PID: $PORT_FORWARD_PID)"
else
    log_error "Port-forward failed to start"
    cat /tmp/port-forward.log
    exit 1
fi

# Step 5: Install Ops Manager on VM
log_step "Step 5: Installing Ops Manager on VM"

# Check if already installed and remove
if dpkg -l 2>/dev/null | grep -q mongodb-mms; then
    log_warning "Ops Manager already installed, removing old version..."
    sudo dpkg -r mongodb-mms || true
    sudo apt-get autoremove -y
fi

log_info "Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y wget curl

log_info "Downloading Ops Manager Debian package..."
cd /tmp
rm -f mongodb-mms-8.0.15.500.20251015T2126Z.amd64.deb
wget -q https://downloads.mongodb.com/on-prem-mms/deb/mongodb-mms-8.0.15.500.20251015T2126Z.amd64.deb

log_info "Installing Ops Manager..."
sudo dpkg -i mongodb-mms-8.0.15.500.20251015T2126Z.amd64.deb

log_success "Ops Manager installed"

# Step 6: Configure Ops Manager
log_step "Step 6: Configuring Ops Manager"
log_info "Updating MongoDB connection to use port-forward (localhost:27017)..."

CONF_FILE="/opt/mongodb/mms/conf/conf-mms.properties"

# Backup original
sudo cp ${CONF_FILE} ${CONF_FILE}.backup

# Update MongoDB URI to use localhost via port-forward
sudo sed -i "s|mongo.mongoUri=.*|mongo.mongoUri=mongodb://admin:admin123@127.0.0.1:27017/mms?authSource=admin|g" ${CONF_FILE}
sudo sed -i "s|mongo.ssl=.*|mongo.ssl=false|g" ${CONF_FILE}

log_success "Ops Manager configuration updated"

# Step 7: Clear old migration logs
log_step "Step 7: Clearing migration logs"
sudo rm -f /opt/mongodb/mms/logs/mms-migration.log
log_success "Migration logs cleared"

# Step 8: Start Ops Manager
log_step "Step 8: Starting Ops Manager Service"
log_info "Starting mongodb-mms service..."

sudo service mongodb-mms start

log_info "Waiting for Ops Manager to start (30 seconds)..."
sleep 30

if sudo service mongodb-mms status | grep -q running; then
    log_success "Ops Manager service started"
else
    log_warning "Ops Manager may still be starting..."
fi

# Step 9: Verify Deployment
log_step "Step 9: Verifying Deployment"
log_info "Checking Ops Manager status..."

sudo service mongodb-mms status --no-pager || true

log_info "Testing Ops Manager connectivity..."
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    log_success "Ops Manager is accessible"
else
    log_warning "Ops Manager not yet responding, checking logs..."
    sudo tail -20 /opt/mongodb/mms/logs/mms-migration.log || true
fi

# Step 10: Get Access Information
log_step "Step 10: Ops Manager Access Information"

OPS_MANAGER_URL="http://${VM_IP}:8080"

echo -e "${GREEN}🎉 Ops Manager setup complete!${NC}"
echo -e "${BLUE}📋 Access Information:${NC}"
echo "   URL: ${OPS_MANAGER_URL}"
echo "   VM IP: ${VM_IP}"
echo "   Port: 8080"
echo ""
echo -e "${BLUE}📋 Port-Forward Information:${NC}"
echo "   MongoDB via port-forward: localhost:27017"
echo "   Port-forward PID: $PORT_FORWARD_PID"
echo "   To stop port-forward: kill $PORT_FORWARD_PID"
echo ""

# Step 11: Web UI Setup Instructions
log_step "Step 11: Complete Web UI Setup"
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
5.  **Configure Settings**: 
    - Set Base URL to http://<VM_IP>:8080
6.  **Generate API Keys**: 
    - Go to Project Settings → Access Manager → API Keys
    - Generate new API Key (Public and Private)
7.  **Add VM IP to API Access List**: Add your VM's IP to allow communication
8.  **Save Credentials**: Keep Organization ID, Project ID, and API Keys for Phase 2

To check Ops Manager logs:
   sudo tail -f /opt/mongodb/mms/logs/mms.log

To check MongoDB migration:
   sudo tail -f /opt/mongodb/mms/logs/mms-migration.log

To check service status:
   sudo service mongodb-mms status

EOF
echo -e "${NC}"

log_success "Phase 1 deployment complete!"
log_info "Port-forward running in background. Open ${OPS_MANAGER_URL} in your browser"