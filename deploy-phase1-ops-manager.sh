#!/bin/bash
set -e

# Phase 1: Deploy Ops Manager on VM + MongoDB in Kubernetes
# Follows MongoDB's official installation guide

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

log_info "Checking if running as root..."
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use: sudo bash script.sh)"
    exit 1
fi

log_success "Running as root"

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
log_step "Step 3: Deploying MongoDB Application Database"
log_info "Creating namespace and MongoDB instance for Ops Manager..."

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

# Step 4: Install Ops Manager on VM
log_step "Step 4: Installing Ops Manager on VM"
log_info "Installing prerequisites..."

yum install -y wget curl mongodb-org-tools || true

log_info "Downloading Ops Manager RPM..."
cd /tmp
wget -q https://downloads.mongodb.com/on-prem-mms/rpm/mongodb-mms-13.0.0.x86_64.rpm

log_info "Installing Ops Manager RPM..."
rpm -ivh mongodb-mms-13.0.0.x86_64.rpm

log_success "Ops Manager installed"

# Step 5: Configure Ops Manager
log_step "Step 5: Configuring Ops Manager"

# Get MongoDB service IP
MONGODB_IP=$(kubectl get svc ops-manager-appdb-svc -n ${OPS_MANAGER_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
log_info "MongoDB Application Database IP: ${MONGODB_IP}"

# Update conf-mms.properties with correct MongoDB connection
CONF_FILE="/opt/mongodb/mms/conf/conf-mms.properties"
log_info "Updating ${CONF_FILE}..."

# Backup original
cp ${CONF_FILE} ${CONF_FILE}.backup

# Update MongoDB URI
sed -i "s|mongo.mongoUri=.*|mongo.mongoUri=mongodb://admin:admin123@${MONGODB_IP}:27017/mms?authSource=admin|g" ${CONF_FILE}
sed -i "s|mongo.ssl=.*|mongo.ssl=false|g" ${CONF_FILE}

log_success "Ops Manager configuration updated"

# Step 6: Start Ops Manager
log_step "Step 6: Starting Ops Manager Service"
log_info "Starting mongodb-mms service..."

systemctl enable mongodb-mms
systemctl start mongodb-mms

log_info "Waiting for Ops Manager to start..."
sleep 10

if systemctl is-active --quiet mongodb-mms; then
    log_success "Ops Manager service started"
else
    log_error "Failed to start Ops Manager service"
    systemctl status mongodb-mms
    exit 1
fi

# Step 7: Verify Deployment
log_step "Step 7: Verifying Deployment"
log_info "Checking Ops Manager status..."

systemctl status mongodb-mms --no-pager

log_info "Checking Ops Manager logs..."
tail -20 /opt/mongodb/mms/logs/mms.log

log_success "Ops Manager deployed"

# Step 8: Get Access Information
log_step "Step 8: Ops Manager Access Information"

OPS_MANAGER_URL="http://${VM_IP}:8080"

echo -e "${GREEN}🎉 Ops Manager is installed and running!${NC}"
echo -e "${BLUE}📋 Access Information:${NC}"
echo "   URL: ${OPS_MANAGER_URL}"
echo "   VM IP: ${VM_IP}"
echo "   Port: 8080"
echo ""

# Step 9: Web UI Setup Instructions
log_step "Step 9: Complete Web UI Setup"
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
   tail -f /opt/mongodb/mms/logs/mms.log

To check service status:
   systemctl status mongodb-mms

EOF
echo -e "${NC}"

log_success "Phase 1 deployment complete!"
log_info "Next steps: Open ${OPS_MANAGER_URL} in your browser"