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
log_step() { echo -e "\n${YELLOW}🚀 $1${NC}\n=================================================="; }

# Configuration
K8S_CLUSTER_NAME="mongodb-cluster"
OPS_MANAGER_NAMESPACE="ops-manager"
MONGODB_OPERATOR_NAMESPACE="mongodb"
VM_IP=$(hostname -I | awk '{print $1}') # Auto-detect VM's IP

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

# Step 2: Install MongoDB Enterprise Operator ONLY
log_step "Step 2: Installing MongoDB Enterprise Operator"
log_info "Cleaning existing MongoDB operator installations..."

# Uninstall existing operators
helm uninstall mongodb-kubernetes -n mongodb 2>/dev/null || true
helm uninstall mongodb-kubernetes -n mongodb-enterprise-operator 2>/dev/null || true

# Clean up any remaining resources
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

# Step 3: Deploy MongoDB Enterprise Advanced Database
log_step "Step 3: Deploying MongoDB Enterprise Advanced Database"
log_info "Deploying MongoDB Enterprise Advanced database for Ops Manager..."

kubectl create namespace ${OPS_MANAGER_NAMESPACE} || true
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ops-manager-db
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ops-manager-db
  template:
    metadata:
      labels:
        app: ops-manager-db
    spec:
      containers:
      - name: mongodb
        image: mongodb/mongodb-enterprise-server:latest
        ports:
        - containerPort: 27017
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: "admin123"
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
  name: ops-manager-db-svc
  namespace: ${OPS_MANAGER_NAMESPACE}
spec:
  selector:
    app: ops-manager-db
  ports:
  - port: 27017
    targetPort: 27017
  type: ClusterIP
EOF

log_info "Waiting for MongoDB Enterprise Advanced database to be ready..."
kubectl wait --for=condition=Available deployment/ops-manager-db -n ${OPS_MANAGER_NAMESPACE} --timeout=300s
log_success "MongoDB Enterprise Advanced database deployed"

# Step 4: Create Custom Ops Manager Configuration
log_step "Step 4: Creating Custom Ops Manager Configuration"
log_info "Creating custom mms.conf with correct MongoDB URI..."

# Check if mms-config already exists and delete it
if kubectl get configmap mms-config -n ${OPS_MANAGER_NAMESPACE} &> /dev/null; then
    log_info "Removing existing mms-config ConfigMap..."
    kubectl delete configmap mms-config -n ${OPS_MANAGER_NAMESPACE}
fi

# Create the mms-config ConfigMap
kubectl create configmap mms-config -n ${OPS_MANAGER_NAMESPACE} --from-literal=mms.conf="
# MongoDB Ops Manager Configuration
mongoUri=mongodb://admin:admin123@ops-manager-db-svc:27017/mms?authSource=admin

# Log directory
LOG_PATH=\"\${APP_DIR}/logs\"

# Optionally run Ops Manager server as another user. Reminder, if changing MMS_USER,
# make sure the ownership of the Ops Manager installation directory tree is also
# updated to MMS_USER.
MMS_USER=

# JDK location (Note JRE not sufficient for JSPs, full JDK required)
JAVA_HOME=\"\${APP_DIR}/jdk\"

# The path to the encryption key used to safeguard data
ENC_KEY_PATH=\${HOME}/.mongodb-mms/gen.key

######################################################
# Ops Manager Website
######################################################
# Port defaults. If changing this default port, you must also update the port
# of 'mms.centralUrl' in conf/conf-mms.properties.
BASE_PORT=8080
BASE_SSL_PORT=8443

# Shared between migrations, preflights, web server and backup daemon
JAVA_MMS_COMMON_OPTS=\"\${JAVA_MMS_COMMON_OPTS} -Duser.timezone=GMT -Djavax.net.ssl.sessionCacheSize=1\"
# Use /dev/urandom (unlimited and unblocking entropy source)
JAVA_MMS_COMMON_OPTS=\"\${JAVA_MMS_COMMON_OPTS} -Djava.security.egd=file:/dev/urandom\"
# Set snappy tmp folder to \${APP_DIR}/tmp so that backup doesn't require exec option enabled on /tmp by default
JAVA_MMS_COMMON_OPTS=\"\${JAVA_MMS_COMMON_OPTS} -Dorg.xerial.snappy.tempdir=\${APP_DIR}/tmp\"
# Include reference to basic fontconfig.properties file to enable font access with Adopt JDK
JAVA_MMS_COMMON_OPTS=\"\${JAVA_MMS_COMMON_OPTS} -Dsun.awt.fontconfig=\${APP_DIR}/conf/fontconfig.properties\"

# JVM configurations
MMS_HEAP_SIZE=\${MMS_HEAP_SIZE:-8096}
JAVA_MMS_UI_OPTS=\"\${JAVA_MMS_UI_OPTS} \${JAVA_MMS_COMMON_OPTS} -Xss512k -Xmx\${MMS_HEAP_SIZE}m -Xms\${MMS_HEAP_SIZE}m -XX:ReservedCodeCacheSize=128m -XX:-OmitStackTraceInFastThrow\"

# Set snappy tmp folder to \${APP_DIR}/tmp so that ServerMain doesn't require exec option enabled on /tmp by default
JAVA_MMS_UI_OPTS=\"\${JAVA_MMS_UI_OPTS} -Dorg.xerial.snappy.tempdir=\${APP_DIR}/tmp\"

# A command to prefix the mongod binary. Depending on your production environment it
# may be necessary to use \"numactl --interleave=all\" as the value.
# For more details, see:
# http://docs.mongodb.org/manual/administration/production-notes/#mongodb-on-numa-hardware
JAVA_DAEMON_OPTS=\"\${JAVA_DAEMON_OPTS} \${JAVA_MMS_COMMON_OPTS} -DMONGO.BIN.PREFIX=\"
"

# Verify the ConfigMap was created successfully
if kubectl get configmap mms-config -n ${OPS_MANAGER_NAMESPACE} &> /dev/null; then
    log_success "Custom Ops Manager configuration created"
else
    log_error "Failed to create mms-config ConfigMap"
    exit 1
fi

# Step 4.5: Create conf-mms.properties ConfigMap
log_step "Step 4.5: Creating conf-mms.properties Configuration"
log_info "Creating conf-mms.properties with correct MongoDB URI..."

# Check if conf-mms-properties already exists and delete it
if kubectl get configmap conf-mms-properties -n ${OPS_MANAGER_NAMESPACE} &> /dev/null; then
    log_info "Removing existing conf-mms-properties ConfigMap..."
    kubectl delete configmap conf-mms-properties -n ${OPS_MANAGER_NAMESPACE}
fi

# Create the conf-mms-properties ConfigMap
kubectl create configmap conf-mms-properties -n ${OPS_MANAGER_NAMESPACE} --from-literal=conf-mms.properties="
# Ops Manager MongoDB storage settings
# The following MongoURI parameters are for configuring the MongoDB storage
# configured to expect a local standalone instance of MongoDB running on
# For more advanced configurations of the backing MongoDB store, such as
# documentation at https://docs.opsmanager.mongodb.com/current/tutorial/prepare-backing-mongodb-instances/
mongo.mongoUri=mongodb://admin:admin123@ops-manager-db-svc:27017/mms?authSource=admin
mongo.ssl=false
# MongoDB SSL Settings (Optional)
# used by the Ops Manager server to connect to its MongoDB backing stores. These
# settings are only applied to the mongoUri connection above when
# \`mongo.ssl\` is set to true.
# CAFile - the certificate of the CA that issued the MongoDB server certificate(s)
#             (needed when MongoDB is running with --sslCAFile)
mongodb.ssl.CAFile=
mongodb.ssl.PEMKeyFile=
mongodb.ssl.PEMKeyFilePassword=
# to its MongoDB backing stores.
# mms.kerberos.principal: The principal we used to authenticate with MongoDB. This should be the exact same user
# on the mongoUri above.
# See https://docs.opsmanager.mongodb.com/current/reference/configuration/
"

# Verify the ConfigMap was created successfully
if kubectl get configmap conf-mms-properties -n ${OPS_MANAGER_NAMESPACE} &> /dev/null; then
    log_success "conf-mms.properties configuration created"
else
    log_error "Failed to create conf-mms-properties ConfigMap"
    exit 1
fi

# Step 5: Deploy Ops Manager Application
log_step "Step 5: Deploying Ops Manager Application"
log_info "Creating Ops Manager encryption key..."
kubectl create secret generic ops-manager-key -n ${OPS_MANAGER_NAMESPACE} --from-literal=encryption-key="$(openssl rand -base64 32)" --dry-run=client -o yaml | kubectl apply -f -

log_info "Deploying Ops Manager application..."
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
      securityContext:
        runAsUser: 0
      containers:
      - name: ops-manager
        image: quay.io/mongodb/mongodb-enterprise-ops-manager-ubi:8.0.15
        command: ["/bin/sh"]
        args: ["-c", "export MMS_MONGODB_URI=mongodb://admin:admin123@ops-manager-db-svc:27017/mms?authSource=admin && /mongodb-ops-manager/bin/start-mongodb-mms --enc-key-path /data/encryption-key && sleep infinity"]        ports:
        - containerPort: 8080
        env:
        - name: MMS_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MMS_INITDB_ROOT_PASSWORD
          value: "admin123"
        - name: MMS_INITDB_DATABASE
          value: "mms"
        - name: MMS_MONGODB_URI
          value: "mongodb://admin:admin123@ops-manager-db-svc:27017/mms?authSource=admin"
        volumeMounts:
        - name: ops-manager-data
          mountPath: /data
        - name: encryption-key
          mountPath: /data/encryption-key
          subPath: encryption-key
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
      - name: encryption-key
        secret:
          secretName: ops-manager-key
      - name: mms-config
        configMap:
          name: mms-config
      - name: conf-mms-properties
        configMap:
          name: conf-mms-properties
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

# Step 6: Verify Deployment
log_step "Step 6: Verifying Deployment"
log_info "Checking pod status..."

# Check if all pods are running
if kubectl get pods -n ${OPS_MANAGER_NAMESPACE} | grep -q "Running"; then
    log_success "All pods are running"
else
    log_warning "Some pods may not be ready yet"
fi

# Check if mms-config is properly mounted
if kubectl exec -n ${OPS_MANAGER_NAMESPACE} -l app=ops-manager -- ls /mongodb-ops-manager/conf/mms.conf &> /dev/null; then
    log_success "mms.conf is properly mounted"
else
    log_warning "mms.conf may not be mounted correctly"
fi

# Check if conf-mms.properties is properly mounted
if kubectl exec -n ${OPS_MANAGER_NAMESPACE} -l app=ops-manager -- ls /mongodb-ops-manager/conf/conf-mms.properties &> /dev/null; then
    log_success "conf-mms.properties is properly mounted"
else
    log_warning "conf-mms.properties may not be mounted correctly"
fi

# Check Ops Manager logs for any errors
log_info "Checking Ops Manager logs for errors..."
if kubectl logs -n ${OPS_MANAGER_NAMESPACE} -l app=ops-manager --tail=20 | grep -i error; then
    log_warning "Found errors in Ops Manager logs"
else
    log_success "No errors found in Ops Manager logs"
fi

log_success "Ops Manager deployed"

# Step 7: Get Ops Manager Access Information
log_step "Step 7: Ops Manager Access Information"
log_info "Getting Ops Manager access details..."

OPS_MANAGER_PORT=$(kubectl get svc ops-manager-svc -n ${OPS_MANAGER_NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}')
OPS_MANAGER_URL="http://${VM_IP}:${OPS_MANAGER_PORT}"

echo -e "${GREEN}🎉 Ops Manager is running!${NC}"
echo -e "${BLUE}📋 Access Information:${NC}"
echo "   URL: ${OPS_MANAGER_URL}"
echo "   VM IP: ${VM_IP}"
echo "   Port: ${OPS_MANAGER_PORT}"
echo ""

# Step 8: Web UI Setup Instructions
log_step "Step 8: Web UI Setup Instructions"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Ops Manager Web UI Setup Required             ║
╚══════════════════════════════════════════════════════════════╝
Please open the Ops Manager URL in your browser and complete the initial setup:

1.  **Open Ops Manager**: Go to the URL provided above (e.g., http://10.128.0.10:30856)
2.  **Sign Up**: Create the first admin user for Ops Manager.
3.  **Create Organization**: Name it "MongoDB Search Demo".
4.  **Create Project**: Name it "Search Project".
5.  **Generate API Keys**:
    - Navigate to Project Settings → Access Manager → API Keys.
    - Generate a new API Key (Public and Private Key).
6.  **Add VM IP to API Access List**:
    - In the same API Keys section, ensure your VM's public IP address (${VM_IP}) is added to the API Access List. This is crucial for the Kubernetes Operator to communicate with Ops Manager.
7.  **Save Credentials**: Keep the Organization ID, Project ID, Public API Key, and Private API Key safe. You will need these for Phase 2.

Once you have completed the web UI setup and saved your credentials, you can proceed to Phase 2.
EOF
echo -e "${NC}"
log_success "Phase 1 (Ops Manager) deployment complete. Proceed with Web UI setup."
EOF

# Make the script executable
chmod +x deploy-phase1-ops-manager.sh

log_success "Phase 1 script updated with conf-mms.properties fix"