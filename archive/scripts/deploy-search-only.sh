#!/bin/bash

# MongoDB Search (mongot) Only Deployment
# Deploys lightweight mongot pods to Kubernetes that connect to external MongoDB

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_step() {
    echo -e "\n${BLUE}🚀 $1${NC}"
    echo "=================================================="
}

# Configuration
K8S_CTX="${K8S_CTX:-$(kubectl config current-context 2>/dev/null || echo '')}"
MDB_NS="${MDB_NS:-mongodb}"
SEARCH_NAME="${SEARCH_NAME:-mdbs}"

# External MongoDB configuration
# These should point to your Docker Compose MongoDB
EXTERNAL_MONGO_HOST_0="${EXTERNAL_MONGO_HOST_0:-host.docker.internal:27017}"
EXTERNAL_MONGO_HOST_1="${EXTERNAL_MONGO_HOST_1:-}"
EXTERNAL_MONGO_HOST_2="${EXTERNAL_MONGO_HOST_2:-}"
EXTERNAL_REPLICA_SET="${EXTERNAL_REPLICA_SET:-rs0}"

# Passwords
SEARCH_SYNC_PASSWORD="${SEARCH_SYNC_PASSWORD:-}"

# Resource limits (lightweight for mongot only)
SEARCH_CPU_LIMIT="${SEARCH_CPU_LIMIT:-2}"
SEARCH_MEMORY_LIMIT="${SEARCH_MEMORY_LIMIT:-3Gi}"
SEARCH_CPU_REQUEST="${SEARCH_CPU_REQUEST:-1}"
SEARCH_MEMORY_REQUEST="${SEARCH_MEMORY_REQUEST:-2Gi}"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      MongoDB Search (mongot) Lightweight Deployment         ║"
echo "║        Connects to External MongoDB (Docker Compose)        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Validate inputs
if [ -z "$K8S_CTX" ]; then
    log_error "No Kubernetes context found. Please set K8S_CTX environment variable."
    exit 1
fi

if [ -z "$SEARCH_SYNC_PASSWORD" ]; then
    log_error "SEARCH_SYNC_PASSWORD is required."
    log_info "Set it with: export SEARCH_SYNC_PASSWORD='your-password'"
    exit 1
fi

log_info "Kubernetes Context: $K8S_CTX"
log_info "Namespace: $MDB_NS"
log_info "External MongoDB: $EXTERNAL_MONGO_HOST_0"
log_info "Replica Set: $EXTERNAL_REPLICA_SET"

# Check prerequisites
log_step "Checking Prerequisites"

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v helm &> /dev/null; then
    log_error "helm not found. Please install Helm."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster."
    exit 1
fi

log_success "Prerequisites met"

# Install MongoDB Kubernetes Operator
log_step "Installing MongoDB Kubernetes Operator"

helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update mongodb

helm upgrade --install --kube-context "${K8S_CTX}" \
    --create-namespace \
    --namespace="${MDB_NS}" \
    mongodb-kubernetes \
    mongodb/mongodb-kubernetes

log_success "Operator installed"

# Wait for operator to be ready
log_info "Waiting for operator to be ready..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/mongodb-kubernetes-operator -n "${MDB_NS}" --context="${K8S_CTX}"

# Create namespace if needed
kubectl create namespace "${MDB_NS}" --dry-run=client -o yaml --context="${K8S_CTX}" | kubectl apply -f -

# Extract keyfile from Docker volume
log_step "Syncing MongoDB Keyfile"

log_info "Extracting keyfile from Docker Compose MongoDB..."
KEYFILE_CONTENT=$(docker exec mongodb-enterprise cat /data/keyfile/mongodb.key 2>/dev/null || echo "")

if [ -z "$KEYFILE_CONTENT" ]; then
    log_warning "Could not extract keyfile from Docker. Generating new one..."
    log_warning "You'll need to restart Docker Compose MongoDB with this keyfile!"
    KEYFILE_CONTENT=$(openssl rand -base64 756)
    
    # Save to temp file
    echo "$KEYFILE_CONTENT" > /tmp/mongodb.key
    log_info "Keyfile saved to /tmp/mongodb.key"
    log_warning "Copy this to your Docker MongoDB: docker cp /tmp/mongodb.key mongodb-enterprise:/data/keyfile/mongodb.key"
fi

# Create keyfile secret
kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
    create secret generic "${EXTERNAL_REPLICA_SET}-keyfile" \
    --from-literal=keyfile="${KEYFILE_CONTENT}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_success "Keyfile synced"

# Create search sync user password secret
log_step "Creating Search User Secrets"

kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
    create secret generic "${EXTERNAL_REPLICA_SET}-search-sync-source-password" \
    --from-literal=password="${SEARCH_SYNC_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

log_success "Search user secrets created"

# Build host list
HOST_LIST=""
if [ -n "$EXTERNAL_MONGO_HOST_0" ]; then
    HOST_LIST="          - ${EXTERNAL_MONGO_HOST_0}"
fi
if [ -n "$EXTERNAL_MONGO_HOST_1" ]; then
    HOST_LIST="${HOST_LIST}\n          - ${EXTERNAL_MONGO_HOST_1}"
fi
if [ -n "$EXTERNAL_MONGO_HOST_2" ]; then
    HOST_LIST="${HOST_LIST}\n          - ${EXTERNAL_MONGO_HOST_2}"
fi

# Deploy MongoDBSearch resource
log_step "Deploying MongoDB Search (mongot) Pods"

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${SEARCH_NAME}
spec:
  source:
    external:
      hostAndPorts:
$(echo -e "$HOST_LIST")
      keyfileSecretRef:
        name: ${EXTERNAL_REPLICA_SET}-keyfile
        key: keyfile
    username: search-sync-source
    passwordSecretRef:
      name: ${EXTERNAL_REPLICA_SET}-search-sync-source-password
      key: password
  resourceRequirements:
    limits:
      cpu: "${SEARCH_CPU_LIMIT}"
      memory: ${SEARCH_MEMORY_LIMIT}
    requests:
      cpu: "${SEARCH_CPU_REQUEST}"
      memory: ${SEARCH_MEMORY_REQUEST}
EOF

# Wait for search to be ready
log_info "Waiting for MongoDB Search to be ready..."
kubectl --context "${K8S_CTX}" -n "${MDB_NS}" wait \
    --for=jsonpath='{.status.phase}'=Running mdbs/${SEARCH_NAME} --timeout=300s || true

log_success "MongoDB Search deployed"

# Create LoadBalancer service for external access
log_step "Creating External Access Service"

kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SEARCH_NAME}-external
spec:
  type: LoadBalancer
  selector:
    app: ${SEARCH_NAME}-search-svc
  ports:
    - name: mongot
      port: 27027
      targetPort: 27027
EOF

log_info "Waiting for external IP assignment..."
sleep 10

EXTERNAL_IP=""
for i in {1..24}; do
    EXTERNAL_IP=$(kubectl get service "${SEARCH_NAME}-external" \
        --context "${K8S_CTX}" -n "${MDB_NS}" \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
        break
    fi
    
    log_info "Still waiting for external IP... ($i/24)"
    sleep 5
done

if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ]; then
    log_warning "External IP not assigned yet. Check later with:"
    log_info "kubectl get service ${SEARCH_NAME}-external -n ${MDB_NS}"
else
    log_success "External IP assigned: $EXTERNAL_IP"
fi

# Summary
log_step "Deployment Complete!"

echo -e "\n${GREEN}🎉 MongoDB Search (mongot) is deployed!${NC}"
echo ""
echo "📊 Deployment Summary:"
echo "   Kubernetes Context: $K8S_CTX"
echo "   Namespace: $MDB_NS"
echo "   MongoDBSearch Resource: $SEARCH_NAME"
echo "   External MongoDB: $EXTERNAL_MONGO_HOST_0"
echo ""

if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
    echo "🔗 mongot External Access:"
    echo "   IP: $EXTERNAL_IP:27027"
    echo ""
    echo "⚙️  Next Steps:"
    echo ""
    echo "1. Update your docker-compose.override.yml:"
    echo "   services:"
    echo "     mongodb:"
    echo "       environment:"
    echo "         MONGOT_HOST: \"$EXTERNAL_IP:27027\""
    echo ""
    echo "2. Restart Docker Compose MongoDB:"
    echo "   docker compose restart mongodb"
    echo ""
    echo "3. Create the search sync user in MongoDB:"
    echo "   docker exec -it mongodb-enterprise mongosh -u admin -p password123 --authenticationDatabase admin"
    echo "   use admin"
    echo "   db.createUser({"
    echo "     user: \"search-sync-source\","
    echo "     pwd: \"${SEARCH_SYNC_PASSWORD}\","
    echo "     roles: [{ role: \"searchCoordinator\", db: \"admin\" }]"
    echo "   })"
    echo ""
    echo "4. Test native \$vectorSearch in your backend!"
else
    log_warning "External IP not ready. Complete setup manually:"
    log_info "1. Get external IP: kubectl get service ${SEARCH_NAME}-external -n ${MDB_NS}"
    log_info "2. Update docker-compose.override.yml with MONGOT_HOST"
fi

echo ""
echo "📋 Useful Commands:"
echo "   # View search pods"
echo "   kubectl get pods -n ${MDB_NS} -l app=${SEARCH_NAME}-search-svc"
echo ""
echo "   # View search resource status"
echo "   kubectl get mdbs -n ${MDB_NS}"
echo ""
echo "   # View logs"
echo "   kubectl logs -n ${MDB_NS} -l app=${SEARCH_NAME}-search-svc"
echo ""

