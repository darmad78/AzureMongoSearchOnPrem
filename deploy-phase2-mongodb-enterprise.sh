#!/bin/bash
set -e

# Phase 2: Deploy MongoDB Enterprise with Ops Manager
# This deploys MongoDB Enterprise using the Ops Manager credentials from Phase 1

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
║                Phase 2: MongoDB Enterprise Setup           ║
║              Using Ops Manager Credentials                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
MDB_RESOURCE_NAME="mdb-rs"
MDB_VERSION="8.2.1-ent"

# Step 0: Pre-flight Cleanup - Remove Old Operator Traces
log_step "Step 0: Pre-flight Cleanup - Removing Old Operator Traces"

# Check for old mongodb-kubernetes-operator
log_info "Checking for old MongoDB Kubernetes Operator..."
OLD_OPERATOR_PODS=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i "mongodb-kubernetes-operator" || echo "")
if [ -n "${OLD_OPERATOR_PODS}" ]; then
    log_warning "Found old MongoDB Kubernetes Operator pods:"
    # Process each pod/namespace (avoiding subshell issues)
    while IFS=' ' read -r ns name; do
        [ -z "${ns}" ] && continue
        log_warning "  - ${name} in namespace ${ns}"
        # Try to uninstall via Helm if it exists
        if command -v helm &> /dev/null; then
            log_info "Attempting to uninstall via Helm from namespace ${ns}..."
            HELM_RELEASES=$(helm list -n ${ns} 2>/dev/null | grep -i mongodb | awk '{print $1}' || echo "")
            if [ -n "${HELM_RELEASES}" ]; then
                echo "${HELM_RELEASES}" | while IFS= read -r release; do
                    [ -z "${release}" ] && continue
                    log_info "Uninstalling Helm release: ${release} from namespace ${ns}..."
                    helm uninstall ${release} -n ${ns} 2>/dev/null || true
                done
            fi
        fi
        # Delete the namespace
        log_info "Deleting namespace ${ns}..."
        kubectl delete namespace ${ns} --ignore-not-found=true || true
    done <<< "${OLD_OPERATOR_PODS}"
    log_success "Old operator removed"
else
    log_success "No old MongoDB Kubernetes Operator found"
fi

# Delete leftover validation webhooks (critical!)
log_info "Checking for leftover validation webhooks..."
WEBHOOKS=$(kubectl get validatingwebhookconfigurations -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i "mongodb" || echo "")
if [ -n "${WEBHOOKS}" ]; then
    log_warning "Found MongoDB-related webhooks that may block the new operator:"
    while IFS= read -r webhook; do
        [ -z "${webhook}" ] && continue
        log_warning "  - ${webhook}"
        log_info "Deleting webhook: ${webhook}..."
        kubectl delete validatingwebhookconfiguration ${webhook} --ignore-not-found=true || true
    done <<< "${WEBHOOKS}"
    log_success "Webhooks cleaned up"
else
    log_success "No conflicting webhooks found"
fi

# Delete old MongoDB CRDs (if they exist)
log_info "Checking for old MongoDB CRDs..."
OLD_CRDS=$(kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E "mongodbs\.mongodb\.com|mongodbcommunity\.mongodb\.com" || echo "")
if [ -n "${OLD_CRDS}" ]; then
    log_warning "Found old MongoDB CRDs:"
    while IFS= read -r crd; do
        [ -z "${crd}" ] && continue
        log_warning "  - ${crd}"
        log_info "Deleting CRD: ${crd}..."
        kubectl delete crd ${crd} --ignore-not-found=true || true
    done <<< "${OLD_CRDS}"
    log_success "Old CRDs cleaned up"
    log_info "Waiting for CRD deletion to propagate..."
    sleep 5
else
    log_success "No conflicting CRDs found"
fi

# Clean up old deprecated enterprise-operator (but keep mongodb namespace - we'll use it)
log_info "Cleaning up deprecated Enterprise Operator (if needed)..."
if kubectl get namespace mongodb-enterprise-operator &> /dev/null; then
    log_warning "Found deprecated Enterprise Operator namespace."
    
    # First, try to uninstall via Helm if it exists
    if command -v helm &> /dev/null; then
        log_info "Checking for Enterprise Operator Helm releases..."
        HELM_RELEASES=$(helm list -n mongodb-enterprise-operator 2>/dev/null | grep -i "enterprise\|mongodb" | awk '{print $1}' || echo "")
        if [ -n "${HELM_RELEASES}" ]; then
            while IFS= read -r release; do
                [ -z "${release}" ] && continue
                log_info "Uninstalling Helm release: ${release} from namespace mongodb-enterprise-operator..."
                helm uninstall ${release} -n mongodb-enterprise-operator --ignore-not-found=true 2>/dev/null || true
            done <<< "${HELM_RELEASES}"
            log_info "Waiting for Helm uninstall to complete..."
            sleep 5
        fi
    fi
    
    # Delete the namespace (this will cascade delete all resources)
    log_info "Deleting deprecated Enterprise Operator namespace..."
    kubectl delete namespace mongodb-enterprise-operator --ignore-not-found=true || true
    log_info "Waiting for deprecated namespace to be deleted..."
    TIMEOUT=120
    ELAPSED=0
    while kubectl get namespace mongodb-enterprise-operator &> /dev/null 2>&1 && [ ${ELAPSED} -lt ${TIMEOUT} ]; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    
    if kubectl get namespace mongodb-enterprise-operator &> /dev/null 2>&1; then
        log_warning "Namespace deletion taking longer than expected. Proceeding anyway..."
    else
        log_success "Deprecated Enterprise Operator namespace cleaned"
    fi
fi

# Also check for enterprise-operator pods in any namespace
log_info "Checking for Enterprise Operator pods in any namespace..."
ENTERPRISE_OPERATOR_PODS=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i "mongodb-enterprise-operator" || echo "")
if [ -n "${ENTERPRISE_OPERATOR_PODS}" ]; then
    log_warning "Found Enterprise Operator pods still running:"
    while IFS=' ' read -r ns name; do
        [ -z "${ns}" ] && continue
        log_warning "  - ${name} in namespace ${ns}"
        log_info "Deleting pod ${name} in namespace ${ns}..."
        kubectl delete pod ${name} -n ${ns} --ignore-not-found=true || true
    done <<< "${ENTERPRISE_OPERATOR_PODS}"
    log_info "Waiting for pods to be deleted..."
    sleep 5
fi

log_success "Pre-flight cleanup complete"

# Step 1: Install Unified MongoDB Controllers for Kubernetes Operator
log_step "Step 1: Installing Unified MongoDB Controllers for Kubernetes Operator"

# The old Enterprise Operator is deprecated. We now use the unified operator.
log_info "Installing MongoDB Controllers for Kubernetes Operator (unified operator)..."

# Check if Helm repo is added
if ! helm repo list | grep -q mongodb; then
    log_info "Adding MongoDB Helm repository..."
    helm repo add mongodb https://mongodb.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update >/dev/null 2>&1 || true
fi

# Install the unified operator in the mongodb namespace (as per the guide)
log_info "Installing unified MongoDB Controllers for Kubernetes Operator..."
helm upgrade --install \
    --create-namespace \
    --namespace ${NAMESPACE} \
    mongodb-kubernetes \
    mongodb/mongodb-kubernetes \
    --wait --timeout=5m

log_success "MongoDB Controllers for Kubernetes Operator installed successfully"

# Verify unified operator is running and watching the correct resources
log_info "Verifying unified operator is running..."
OPERATOR_READY=$(kubectl get deployment mongodb-kubernetes-operator -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "${OPERATOR_READY}" != "1" ]; then
    log_error "Unified operator is not ready (readyReplicas=${OPERATOR_READY})"
    log_info "Checking operator pods..."
    kubectl get pods -n ${NAMESPACE} | grep mongodb-kubernetes-operator || true
    log_info "Checking operator logs..."
    kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=mongodb-kubernetes-operator --tail=20 || true
    exit 1
fi

log_success "Unified operator is running and ready"
log_info "The unified operator automatically watches: mongodb, opsmanagers, mongodbusers, mongodbcommunity, and mongodbsearch resources"

# Step 2: Get Ops Manager Credentials
log_step "Step 2: Getting Ops Manager Credentials"
echo -e "${YELLOW}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║              Enter Ops Manager Credentials                 ║
╚══════════════════════════════════════════════════════════════╝

Please enter the credentials you obtained from Phase 1:

EOF
echo -e "${NC}"

echo -e "${BLUE}📋 How to get each credential:${NC}"
echo ""
echo -e "${YELLOW}1. Organization ID:${NC}"
echo "   • Open Ops Manager: http://${VM_IP}:8080"
echo "   • After login, look at the URL: http://${VM_IP}:8080/v2/org/YOUR_ORG_ID/"
echo "   • Or go to Organization Settings → General"
echo ""
echo -e "${YELLOW}2. Project ID:${NC}"
echo "   • Go to your 'Search Project'"
echo "   • Look at the URL: http://${VM_IP}:8080/v2/org/YOUR_ORG_ID/project/YOUR_PROJECT_ID/"
echo "   • Or go to Project Settings → General"
echo ""
echo -e "${YELLOW}3. API Keys (Public & Private):${NC}"
echo "   • Go to Project Settings → Access Manager → API Keys"
echo "   • Click 'Generate New API Key'"
echo "   • Set permissions:"
echo "     - Project Owner (full access)"
echo "     - Or at minimum:"
echo "       • Project Read Only"
echo "       • Project Data Access Read Only"
echo "       • Project Owner"
echo "   • Copy both Public and Private keys"
echo ""

# Get VM IP for Ops Manager URL
log_info "Detecting VM IP address..."
VM_IP=$(hostname -I | awk '{print $1}')

# Validate VM IP or ask user to enter it
if [ -z "${VM_IP}" ] || ! echo "${VM_IP}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
  echo -e "${YELLOW}⚠️  Could not auto-detect VM IP address.${NC}"
  echo ""
  echo -e "${BLUE}Please enter the internal IP address where Ops Manager is running:${NC}"
  echo -e "${YELLOW}Example: 10.128.0.10${NC}"
  read -p "VM Internal IP: " VM_IP
  
  # Validate the entered IP
  while [ -z "${VM_IP}" ] || ! echo "${VM_IP}" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; do
    echo -e "${RED}❌ Invalid IP address format. Please try again.${NC}"
    read -p "VM Internal IP: " VM_IP
  done
fi

OPS_MANAGER_URL="http://${VM_IP}:8080"
log_success "Using Ops Manager URL: ${OPS_MANAGER_URL}"

# Check for environment variables first
if [ -z "$ORG_ID" ] || [ -z "$PROJECT_ID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
    echo -e "${YELLOW}Environment variables not found. Please enter Ops Manager credentials:${NC}"
    echo ""
    
    # Prompt for credentials
    echo -e "${YELLOW}Enter Organization ID (found in URL after /v2/org/):${NC}"
    read -p "Organization ID: " ORG_ID
    echo ""

    echo -e "${YELLOW}Enter Project ID (found in URL after /project/):${NC}"
    read -p "Project ID: " PROJECT_ID
    echo ""

    echo -e "${YELLOW}Enter Public API Key (from Project Settings → Access Manager → API Keys):${NC}"
    read -p "Public API Key: " PUBLIC_KEY
    echo ""

    echo -e "${YELLOW}Enter Private API Key (from same API Keys page):${NC}"
    read -sp "Private API Key: " PRIVATE_KEY
    echo ""
else
    log_info "Using credentials from environment variables"
    echo "Organization ID: $ORG_ID"
    echo "Project ID: $PROJECT_ID"
    echo "Public API Key: $PUBLIC_KEY"
    echo "Private API Key: [HIDDEN]"
    echo ""
fi

# Validate inputs
if [ -z "$ORG_ID" ] || [ -z "$PROJECT_ID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$PRIVATE_KEY" ]; then
    log_error "One or more credentials are missing. Please run the script again."
    exit 1
fi

log_info "Validating credentials format..."
if [[ ! "$ORG_ID" =~ ^[0-9a-fA-F]{24}$ ]]; then
    log_warning "Organization ID format looks unusual. Expected 24-character hex string."
fi
if [[ ! "$PROJECT_ID" =~ ^[0-9a-fA-F]{24}$ ]]; then
    log_warning "Project ID format looks unusual. Expected 24-character hex string."
fi

log_success "Credentials collected"

# Check IP Access List
log_info "Checking Ops Manager IP Access List..."
MINIKUBE_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
log_warning "IMPORTANT: Ensure Ops Manager IP Access List includes the minikube node IP"
echo ""
echo "📋 Add this IP to Ops Manager IP Access List:"
echo "   • Go to Ops Manager: http://${VM_IP}:8080"
echo "   • Organization Settings → Access Manager → IP Access List"
echo "   • Add IP: ${MINIKUBE_NODE_IP}/32"
echo "   • Or add range: 192.168.49.0/24"
echo ""
read -p "Press Enter after adding the IP to the access list..."

# Wait for MongoDB pods to be created and get their IPs
log_info "Waiting for MongoDB pods to be created..."
kubectl wait --for=condition=Ready pod -l app=mongodb-enterprise-database -n ${NAMESPACE} --timeout=300s || true

# Get MongoDB pod IPs for IP access list
log_info "Getting MongoDB pod IPs for Ops Manager IP Access List..."
MONGODB_POD_IPS=$(kubectl get pods -n ${NAMESPACE} -l app=mongodb-enterprise-database -o jsonpath='{.items[*].status.podIP}')
if [ -n "$MONGODB_POD_IPS" ]; then
    log_warning "CRITICAL: Add these MongoDB pod IPs to Ops Manager IP Access List:"
    echo ""
    echo "📋 MongoDB Pod IPs to add:"
    for ip in $MONGODB_POD_IPS; do
        echo "   • $ip/32"
    done
    echo ""
    echo "   • Go to Ops Manager: http://${VM_IP}:8080"
    echo "   • Organization Settings → Access Manager → IP Access List"
    echo "   • Add each IP above with /32 subnet"
    echo "   • Or add the entire pod network range if known"
    echo ""
    read -p "Press Enter after adding the MongoDB pod IPs to the access list..."
else
    log_warning "MongoDB pods not yet created. You may need to add pod IPs manually later."
fi

# Configure Ops Manager URL
log_info "Configuring Ops Manager URL..."
log_warning "IMPORTANT: Fix Ops Manager configuration file"
echo ""
echo "📋 Fix Ops Manager Configuration:"
echo "   • The config file shows port 8888, but we need 8080"
echo "   • Check the config file: /opt/mongodb/mms/conf/conf-mms.properties"
echo "   • Look for 'mms.centralUrl' and change port from 8888 to 8080"
echo "   • Or check: /opt/mongodb/mms/conf/conf-mms.properties"
echo "   • Restart Ops Manager after making changes"
echo ""
echo "   • Also configure in web interface:"
echo "   • Go to Ops Manager: http://${VM_IP}:8080"
echo "   • Organization Settings → General"
echo "   • Set 'URL to Access Ops Manager' to: http://${VM_IP}:8080"
echo ""
read -p "Press Enter after configuring the Ops Manager URL..."

# Optional: front OM with nginx on :80 if 8080 DNAT is detected or forced
if sudo nft list ruleset | grep -qi 'tcp dport 8080 dnat' || [ "${OM_PROXY_80:-false}" = "true" ]; then
  log_info "Setting up nginx reverse proxy on :80 → :8080..."
  sudo apt-get update -y && sudo apt-get install -y nginx
  sudo tee /etc/nginx/sites-available/ops-manager >/dev/null <<'NGINX'
server {
  listen 80 default_server;
  server_name _;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $remote_addr;
  }
}
NGINX
  sudo ln -sf /etc/nginx/sites-available/ops-manager /etc/nginx/sites-enabled/default
  sudo systemctl restart nginx
  log_warning "Open TCP:80 in GCP firewall before accessing the UI externally."
fi

# Install MongoDB version from repository
log_info "Installing MongoDB Enterprise 8.2+ RHEL 8 from repository..."

# Auto-detect latest 8.2+ Enterprise binary (x86_64 preferred, fallback to aarch64)
LATEST_BIN=$(ls -1 \
  backend/opsmanagerfiles/mongodb-linux-x86_64-enterprise-rhel8*-8.2*.tgz \
  backend/opsmanagerfiles/mongodb-linux-x86_64-enterprise-rhel80-8.2*.tgz \
  backend/opsmanagerfiles/mongodb-linux-aarch64-enterprise-rhel8-8.2*.tgz \
  2>/dev/null | sort -V | tail -n1)

if [ -z "$LATEST_BIN" ]; then
    log_error "No MongoDB Enterprise 8.2+ RHEL8 tgz found in backend/opsmanagerfiles/"
    log_error "Please place an 8.2.x tgz (e.g., mongodb-linux-x86_64-enterprise-rhel8-8.2.1.tgz) in that folder."
    exit 1
fi

MONGODB_BINARY="$LATEST_BIN"

if echo "$MONGODB_BINARY" | grep -q "aarch64"; then
    log_warning "Using ARM64 binary - ensure Ops Manager host is ARM64 compatible"
else
    log_info "Using x86_64 binary: $(basename "$MONGODB_BINARY")"
fi

log_info "Copying MongoDB binary to Ops Manager..."
sudo cp "$MONGODB_BINARY" /opt/mongodb/mms/mongodb-releases/
sudo chown mongodb-mms:mongodb-mms \
  "/opt/mongodb/mms/mongodb-releases/$(basename "$MONGODB_BINARY")"

log_success "MongoDB RHEL 8 version installed in Ops Manager"

# Step 3: Create Namespace
log_step "Step 3: Creating MongoDB Namespace"
log_info "Creating mongodb namespace..."

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
log_success "MongoDB namespace created"

# Create required ServiceAccount for MongoDB pods
log_info "Creating ServiceAccount for MongoDB pods..."
kubectl create serviceaccount mongodb-enterprise-database-pods -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
log_success "ServiceAccount created"

# Step 4: Create Ops Manager Configuration
log_step "Step 4: Creating Ops Manager Configuration"
log_info "Creating Ops Manager configuration with provided credentials..."

# Determine the base URL - use VM IP directly since Ops Manager runs on VM
# The operator needs to be able to reach Ops Manager from within pods
BASE_URL_VALUE="${OPS_MANAGER_URL}"
log_info "Using VM IP for Ops Manager baseUrl: ${BASE_URL_VALUE}"
log_info "Note: Ops Manager must be accessible from Kubernetes pods at this address"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: ${NAMESPACE}
data:
  projectName: "${PROJECT_ID}"
  orgId: "${ORG_ID}"
  baseUrl: "${BASE_URL_VALUE}"
  authType: DIGEST
---
apiVersion: v1
kind: Secret
metadata:
  name: om-credentials
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  publicKey: "${PUBLIC_KEY}"
  privateKey: "${PRIVATE_KEY}"
EOF

log_success "Ops Manager configuration created"

# Step 5: Deploy MongoDB Enterprise
log_step "Step 5: Deploying MongoDB Enterprise"
log_info "Deploying MongoDB Enterprise replica set..."

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: ${MDB_RESOURCE_NAME}
  namespace: ${NAMESPACE}
spec:
  members: 3
  version: ${MDB_VERSION}
  type: ReplicaSet
  credentials: om-credentials
  opsManager:
    configMapRef:
      name: om-project
  security:
    authentication:
      enabled: true
      ignoreUnknownUsers: true
      modes:
      - SCRAM
  podSpec:
    podTemplate:
      spec:
        containers:
        - name: mongodb-enterprise-database
          env:
          - name: HOME
            value: /tmp
          - name: MONGOSH_FORCE_DISABLE_TELEMETRY
            value: "false"
          lifecycle:
            postStart:
              exec:
                command:
                - /bin/sh
                - -c
                - |
                  # Clean up any existing mongosh config that might have forceDisableTelemetry=true
                  if [ -d /tmp/.mongodb/mongosh ]; then
                    echo "Cleaning up mongosh config directory to prevent telemetry conflicts..."
                    rm -rf /tmp/.mongodb/mongosh 2>/dev/null || true
                    echo "Mongosh config cleanup complete"
                  fi
          resources:
            limits:
              cpu: "2"
              memory: 2Gi
            requests:
              cpu: "1"
              memory: 1Gi
EOF

# Verify and ensure environment variables are set correctly
log_info "Verifying environment variables are set in MongoDB CR..."
ENV_CHECK=$(kubectl get mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.podSpec.podTemplate.spec.containers[0].env[?(@.name=="HOME")].value}' 2>/dev/null || echo "")
if [ -z "${ENV_CHECK}" ] || [ "${ENV_CHECK}" != "/tmp" ]; then
  log_warning "Environment variables not found or incorrect. Patching MongoDB CR..."
  kubectl patch mongodb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} --type='json' -p='[
    {
      "op": "add",
      "path": "/spec/podSpec/podTemplate/spec/containers/0/env",
      "value": [
        {"name": "HOME", "value": "/tmp"},
        {"name": "MONGOSH_FORCE_DISABLE_TELEMETRY", "value": "false"}
      ]
    }
  ]' || kubectl patch mongodb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} --type='json' -p='[
    {
      "op": "replace",
      "path": "/spec/podSpec/podTemplate/spec/containers/0/env",
      "value": [
        {"name": "HOME", "value": "/tmp"},
        {"name": "MONGOSH_FORCE_DISABLE_TELEMETRY", "value": "false"}
      ]
    }
  ]'
  log_success "MongoDB CR patched with correct environment variables"
else
  log_success "Environment variables verified in MongoDB CR"
fi

# Step 5.5: Automatically create deployment in Ops Manager via API
log_step "Step 5.5: Creating deployment in Ops Manager"
log_info "Automatically registering MongoDB deployment with Ops Manager..."

# Get credentials from secret
PUBLIC_API_KEY=$(kubectl get secret om-credentials -n ${NAMESPACE} -o jsonpath='{.data.publicApiKey}' | base64 -d)
PRIVATE_API_KEY=$(kubectl get secret om-credentials -n ${NAMESPACE} -o jsonpath='{.data.privateApiKey}' | base64 -d)

if [ -z "${PUBLIC_API_KEY}" ] || [ -z "${PRIVATE_API_KEY}" ]; then
  log_warning "API keys not found. Deployment must be created manually in Ops Manager UI."
  log_warning "Go to ${OPS_MANAGER_URL} and create a Replica Set deployment named '${MDB_RESOURCE_NAME}' with 3 members."
else
  # Create authentication header (Digest authentication)
  AUTH_HEADER=$(printf "%s:%s" "${PUBLIC_API_KEY}" "${PRIVATE_API_KEY}" | base64)
  
  # Attempt to automatically create deployment in Ops Manager via API
  log_info "Attempting to automatically create deployment in Ops Manager..."
  
  # Get current automation config using the agent endpoint (more direct)
  # Note: Using PROJECT_ID (not ORG_ID) as automation config is project-scoped
  CURRENT_CONFIG=$(curl -s --digest \
    -u "${PUBLIC_API_KEY}:${PRIVATE_API_KEY}" \
    "${OPS_MANAGER_URL}/agents/api/automation/conf/v1/${PROJECT_ID}" \
    -H "Content-Type: application/json" || echo "")
  
  if [ -z "${CURRENT_CONFIG}" ] || echo "${CURRENT_CONFIG}" | grep -q '"error"'; then
    log_warning "Could not fetch automation config from Ops Manager API."
    log_warning "Deployment must be created manually in Ops Manager UI: ${OPS_MANAGER_URL}"
    read -p "Press ENTER once you have created the deployment, or Ctrl+C to exit..."
  else
    # Check if deployment already exists
    if echo "${CURRENT_CONFIG}" | grep -q "\"name\":\"${MDB_RESOURCE_NAME}\""; then
      log_success "Deployment '${MDB_RESOURCE_NAME}' already exists in Ops Manager"
    else
      log_info "Deployment not found. Automatically creating deployment in Ops Manager via API..."
      
      # Parse current config and add new processes and replica set
      # We'll use Python/jq if available, or construct JSON manually
      if command -v python3 >/dev/null 2>&1; then
        log_info "Using Python to construct automation config..."
        
        # Create automation config update
        # Write current config to temp file for Python to read
        TEMP_CONFIG_FILE=$(mktemp)
        echo "${CURRENT_CONFIG}" > "${TEMP_CONFIG_FILE}"
        
        # Read the config in Python and construct the update
        UPDATED_CONFIG=$(python3 <<EOF
import json
import sys

# Read current config from file
config_file = "${TEMP_CONFIG_FILE}"
with open(config_file, "r") as f:
    current = json.load(f)

# Create process definitions for each member (using correct structure)
processes = []
for i in range(3):
    hostname = "${MDB_RESOURCE_NAME}-${i}.${MDB_RESOURCE_NAME}-svc.${NAMESPACE}.svc.cluster.local"
    process = {
        "name": "${MDB_RESOURCE_NAME}-${i}",
        "processType": "mongod",
        "version": "${MDB_VERSION}",
        "featureCompatibilityVersion": "8.0",
        "hostname": hostname,
        "args2_6": {
            "net": {
                "port": 27017,
                "tls": {
                    "mode": "disabled"
                }
            },
            "replication": {
                "replSetName": "${MDB_RESOURCE_NAME}"
            },
            "storage": {
                "dbPath": "/data"
            },
            "systemLog": {
                "destination": "file",
                "path": "/var/log/mongodb-mms-automation/mongodb.log"
            }
        }
    }
    processes.append(process)

# Replace processes array (don't extend - replace empty array)
current["cluster"]["processes"] = processes

# Update auth section if needed (ensure auth is not disabled)
if "auth" in current["cluster"]:
    current["cluster"]["auth"]["disabled"] = False
    if "deploymentAuthMechanisms" not in current["cluster"]["auth"]:
        current["cluster"]["auth"]["deploymentAuthMechanisms"] = ["SCRAM-SHA-256"]
    if "autoAuthMechanisms" not in current["cluster"]["auth"]:
        current["cluster"]["auth"]["autoAuthMechanisms"] = ["SCRAM-SHA-256"]

# Create replica set definition (members use process name, not full hostname)
replica_set = {
    "_id": "${MDB_RESOURCE_NAME}",
    "members": [
        {"_id": i, "host": "${MDB_RESOURCE_NAME}-${i}", "priority": 1, "votes": 1}
        for i in range(3)
    ]
}

# Replace replicaSets array
current["cluster"]["replicaSets"] = [replica_set]

# Output updated config
print(json.dumps(current))
EOF
)
        
        if [ -n "${UPDATED_CONFIG}" ] && echo "${UPDATED_CONFIG}" | grep -q "${MDB_RESOURCE_NAME}"; then
          # Write updated config to temp file (like user's script approach)
          echo "${UPDATED_CONFIG}" > "${TEMP_CONFIG_FILE}"
          
          # POST updated config to Ops Manager using the agent endpoint (same as user's script)
          log_info "Posting automation config to Ops Manager..."
          RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT \
            --digest \
            -u "${PUBLIC_API_KEY}:${PRIVATE_API_KEY}" \
            "${OPS_MANAGER_URL}/agents/api/automation/conf/v1/${PROJECT_ID}" \
            -H "Content-Type: application/json" \
            --data "@${TEMP_CONFIG_FILE}" || echo "")
          
          HTTP_CODE=$(echo "${RESPONSE}" | tail -n1)
          if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ]; then
            log_success "Deployment '${MDB_RESOURCE_NAME}' successfully created in Ops Manager!"
            log_info "Waiting for automation agent to receive new configuration..."
            sleep 10
          else
            log_warning "Failed to create deployment via API (HTTP ${HTTP_CODE})."
            log_warning "Response: $(echo "${RESPONSE}" | head -n -1)"
            log_warning "Please create the deployment manually in Ops Manager UI: ${OPS_MANAGER_URL}"
            read -p "Press ENTER once you have created the deployment, or Ctrl+C to exit..."
          fi
        else
          log_warning "Failed to construct automation config. Please create deployment manually."
          read -p "Press ENTER once you have created the deployment, or Ctrl+C to exit..."
        fi
        
        # Cleanup temp file
        rm -f "${TEMP_CONFIG_FILE}" 2>/dev/null || true
      else
        log_warning "Python3 not available. Cannot automatically create deployment."
        log_warning "Please install Python3 or create the deployment manually:"
        log_warning "Go to: ${OPS_MANAGER_URL}"
        log_warning "Create Replica Set '${MDB_RESOURCE_NAME}' with 3 members"
        read -p "Press ENTER once you have created the deployment, or Ctrl+C to exit..."
      fi
    fi
  fi
fi

log_info "Waiting for MongoDB resource to reach Running phase..."
# Note: This will wait indefinitely if deployment doesn't exist in Ops Manager
# Consider adding a timeout or check if pods are running
TIMEOUT=600
ELAPSED=0
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  PHASE=$(kubectl get mdb ${MDB_RESOURCE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "${PHASE}" = "Running" ]; then
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  if [ $((ELAPSED % 30)) -eq 0 ]; then
    log_info "Still waiting for MongoDB to be Running (current phase: ${PHASE}, elapsed: ${ELAPSED}s)..."
    log_info "If stuck in Pending, check if deployment exists in Ops Manager UI: ${OPS_MANAGER_URL}"
  fi
done

if [ "${PHASE}" != "Running" ]; then
  log_warning "MongoDB did not reach Running phase within ${TIMEOUT}s."
  log_warning "Current phase: ${PHASE}"
  log_warning "This is likely because the deployment doesn't exist in Ops Manager."
  log_warning "Please create the deployment manually in Ops Manager UI: ${OPS_MANAGER_URL}"
  log_warning "Deployment name: ${MDB_RESOURCE_NAME}, Members: 3, Version: ${MDB_VERSION}"
else
  log_success "MongoDB Enterprise deployed and running"
fi

# Step 5.75: Configure MongoDB server parameter for telemetry
log_step "Step 5.75: Configuring MongoDB server telemetry parameter"
log_info "Setting forceDisableTelemetry to false on MongoDB server..."

# Wait for the primary to be ready
PRIMARY_POD=""
for i in {0..10}; do
  PRIMARY_POD=$(kubectl get pods -n ${NAMESPACE} -l app=mongodb-rs-svc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "${PRIMARY_POD}" ]; then
    break
  fi
  sleep 2
done

if [ -n "${PRIMARY_POD}" ]; then
  log_info "Setting forceDisableTelemetry parameter via primary pod: ${PRIMARY_POD}"
  # Find mongosh binary path in the pod
  MONGOSH_PATH=$(kubectl exec -n ${NAMESPACE} ${PRIMARY_POD} -- find /var/lib/mongodb-mms-automation -name mongosh -type f 2>/dev/null | head -n1)
  
  if [ -n "${MONGOSH_PATH}" ]; then
    kubectl exec -n ${NAMESPACE} ${PRIMARY_POD} -- ${MONGOSH_PATH} \
      --eval 'db.adminCommand({ setParameter: 1, forceDisableTelemetry: false })' \
      -u mdb-admin -p 'admin-user-password-CHANGE-ME' --authenticationDatabase admin \
      --quiet 2>/dev/null && log_success "MongoDB server parameter forceDisableTelemetry set to false" || \
      log_warning "Could not set forceDisableTelemetry parameter. You may need to configure this in Ops Manager UI."
  else
    log_warning "Could not find mongosh binary. SetParameter will be configured by Ops Manager automation agent."
  fi
else
  log_warning "Could not find primary pod. The forceDisableTelemetry parameter will be configured by Ops Manager automation agent."
fi

# Step 6: Create MongoDB Users
log_step "Step 6: Creating MongoDB Users"
log_info "Creating MongoDB users for search functionality..."

# Admin user
kubectl create secret generic mdb-admin-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="admin-user-password-CHANGE-ME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-admin
  namespace: ${NAMESPACE}
spec:
  username: mdb-admin
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-admin-user-password
    key: password
  roles:
  - name: root
    db: admin
EOF

# Application user
kubectl create secret generic mdb-user-password \
  -n ${NAMESPACE} \
  --from-literal=password="mdb-user-password-CHANGE-ME" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-user
  namespace: ${NAMESPACE}
spec:
  username: mdb-user
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: mdb-user-password
    key: password
  roles:
  - name: readWrite
    db: admin
EOF

log_success "MongoDB users created"

# Step 7: Verify MongoDB Deployment
log_step "Step 7: Verifying MongoDB Deployment"
log_info "Checking MongoDB deployment status..."

echo "MongoDB resource:"
kubectl get "mdb/${MDB_RESOURCE_NAME}" -n ${NAMESPACE}
echo ""
echo "MongoDB pods:"
kubectl get pods -n ${NAMESPACE} -l app=mongodb-rs-svc
echo ""

log_success "Phase 2 complete! MongoDB Enterprise is running."
echo ""
echo "🔗 Next Steps:"
echo "   1. MongoDB Enterprise is ready"
echo "   2. Users are created with proper roles"
echo "   3. Run Phase 3: ./deploy-phase3-mongodb-search.sh"
echo ""
