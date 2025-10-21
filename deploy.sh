#!/bin/bash

# MongoDB Enterprise Advanced - Single Executable Deployment Script
# Automatically detects environment and deploys everything

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

# Configuration file path
CONFIG_FILE="deploy.conf"

# Default configuration
DEFAULT_CONFIG='{
  "environment": {
    "os": "auto",
    "k8s_context": "auto",
    "mongodb_namespace": "mongodb",
    "mongodb_resource_name": "mdb-rs",
    "mongodb_version": "8.2.1-ent"
  },
  "passwords": {
    "admin_password": "",
    "user_password": "",
    "search_sync_password": ""
  },
  "resources": {
    "mongodb_cpu_limit": "2",
    "mongodb_memory_limit": "2Gi",
    "search_cpu_limit": "3",
    "search_memory_limit": "5Gi"
  },
  "ops_manager": {
    "enabled": true,
    "project_name": "search-project"
  }
}'

# Create default config file if it doesn't exist
create_default_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "Creating default configuration file: $CONFIG_FILE"
        echo "$DEFAULT_CONFIG" > "$CONFIG_FILE"
        log_warning "Please edit $CONFIG_FILE and configure your passwords and settings"
        log_warning "Then run this script again"
        exit 0
    fi
}

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file $CONFIG_FILE not found"
        exit 1
    fi
    
    # Parse JSON configuration (basic parsing)
    K8S_CTX=$(grep -o '"k8s_context": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_NS=$(grep -o '"mongodb_namespace": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_RESOURCE_NAME=$(grep -o '"mongodb_resource_name": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_VERSION=$(grep -o '"mongodb_version": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_ADMIN_USER_PASSWORD=$(grep -o '"admin_password": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_USER_PASSWORD=$(grep -o '"user_password": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_SEARCH_SYNC_USER_PASSWORD=$(grep -o '"search_sync_password": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    # Validate required fields
    if [ -z "$MDB_ADMIN_USER_PASSWORD" ] || [ "$MDB_ADMIN_USER_PASSWORD" = "" ]; then
        log_error "admin_password is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [ -z "$MDB_USER_PASSWORD" ] || [ "$MDB_USER_PASSWORD" = "" ]; then
        log_error "user_password is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [ -z "$MDB_SEARCH_SYNC_USER_PASSWORD" ] || [ "$MDB_SEARCH_SYNC_USER_PASSWORD" = "" ]; then
        log_error "search_sync_password is required in $CONFIG_FILE"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt &> /dev/null; then
            OS="ubuntu"
        elif command -v yum &> /dev/null; then
            OS="rhel"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    log_info "Detected OS: $OS"
}

# Detect Kubernetes cluster
detect_kubernetes() {
    if [ "$K8S_CTX" = "auto" ] || [ -z "$K8S_CTX" ]; then
        if command -v kubectl &> /dev/null; then
            # Try to detect current context
            CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
            if [ -n "$CURRENT_CONTEXT" ]; then
                K8S_CTX="$CURRENT_CONTEXT"
                log_info "Auto-detected Kubernetes context: $K8S_CTX"
            else
                log_error "No Kubernetes context found. Please configure k8s_context in $CONFIG_FILE"
                exit 1
            fi
        else
            log_error "kubectl not found. Please install Kubernetes tools first."
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    command -v kubectl &> /dev/null || missing_tools+=("kubectl")
    command -v helm &> /dev/null || missing_tools+=("helm")
    command -v docker &> /dev/null || missing_tools+=("docker")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and run this script again"
        
        if [ "$OS" = "ubuntu" ]; then
            log_info "Run: ./setup-ubuntu-prerequisites.sh"
        fi
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Kubernetes cluster is not accessible"
        log_info "Please ensure your cluster is running and accessible"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Install MongoDB Kubernetes Operator
install_operator() {
    log_step "Installing MongoDB Kubernetes Operator"
    
    # Add Helm repository
    helm repo add mongodb https://mongodb.github.io/helm-charts
    helm repo update mongodb
    
    # Install operator
    helm upgrade --install --kube-context "${K8S_CTX}" \
        --create-namespace \
        --namespace="${MDB_NS}" \
        mongodb-kubernetes \
        mongodb/mongodb-kubernetes
    
    log_success "MongoDB Kubernetes Operator installed"
}

# Deploy Ops Manager
deploy_ops_manager() {
    log_step "Deploying MongoDB Ops Manager"
    
    # Create namespace if it doesn't exist
    kubectl create namespace "${MDB_NS}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Ops Manager ConfigMap
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: om-project
  namespace: ${MDB_NS}
data:
  projectName: "${OPS_MANAGER_PROJECT_NAME:-search-project}"
  orgId: "search-org"
EOF
    
    # Create Ops Manager Credentials Secret
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: om-credentials
  namespace: ${MDB_NS}
type: Opaque
stringData:
  user: "admin"
  publicApiKey: "your-public-api-key"
  privateApiKey: "your-private-api-key"
EOF
    
    # Create Ops Manager Deployment
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb-ops-manager
  namespace: ${MDB_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb-ops-manager
  template:
    metadata:
      labels:
        app: mongodb-ops-manager
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
kind: PersistentVolumeClaim
metadata:
  name: ops-manager-pvc
  namespace: ${MDB_NS}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ops-manager-service
  namespace: ${MDB_NS}
spec:
  selector:
    app: mongodb-ops-manager
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
  type: LoadBalancer
EOF
    
    # Wait for Ops Manager to be ready
    log_info "Waiting for Ops Manager to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/mongodb-ops-manager -n "${MDB_NS}"
    
    log_success "MongoDB Ops Manager deployed"
}

# Deploy MongoDB Enterprise
deploy_mongodb() {
    log_step "Deploying MongoDB Enterprise Advanced"
    
    # Create MongoDB Enterprise resource
    kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: ${MDB_RESOURCE_NAME}
spec:
  members: 3
  version: ${MDB_VERSION}
  type: ReplicaSet
  opsManager:
    configMapRef:
      name: om-project
  credentials: om-credentials
  security:
    authentication:
      enabled: true
      ignoreUnknownUsers: true
      modes:
      - SCRAM
  agent:
    logLevel: INFO
  podSpec:
    podTemplate:
      spec:
        containers:
        - name: mongodb-enterprise-database
          resources:
            limits:
              cpu: "${MONGODB_CPU_LIMIT:-2}"
              memory: "${MONGODB_MEMORY_LIMIT:-2Gi}"
            requests:
              cpu: "1"
              memory: 1Gi
EOF
    
    # Wait for MongoDB to be ready
    log_info "Waiting for MongoDB Enterprise to be ready..."
    kubectl --context "${K8S_CTX}" -n "${MDB_NS}" wait --for=jsonpath='{.status.phase}'=Running "mdb/${MDB_RESOURCE_NAME}" --timeout=600s
    
    log_success "MongoDB Enterprise Advanced deployed"
}

# Create MongoDB users
create_users() {
    log_step "Creating MongoDB Users"
    
    # Admin user
    kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
        create secret generic mdb-admin-user-password \
        --from-literal=password="${MDB_ADMIN_USER_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-admin
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
    
    # Search sync user
    kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
        create secret generic "${MDB_RESOURCE_NAME}-search-sync-source-password" \
        --from-literal=password="${MDB_SEARCH_SYNC_USER_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: search-sync-source-user
spec:
  username: search-sync-source
  db: admin
  mongodbResourceRef:
    name: ${MDB_RESOURCE_NAME}
  passwordSecretKeyRef:
    name: ${MDB_RESOURCE_NAME}-search-sync-source-password
    key: password
  roles:
  - name: searchCoordinator
    db: admin
EOF
    
    # Regular user
    kubectl --context "${K8S_CTX}" --namespace "${MDB_NS}" \
        create secret generic mdb-user-password \
        --from-literal=password="${MDB_USER_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBUser
metadata:
  name: mdb-user
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
    db: searchdb
EOF
    
    log_success "MongoDB users created"
}

# Deploy MongoDB Search (mongot nodes for Vector Search)
deploy_search() {
    log_step "Deploying MongoDB Search & Vector Search (mongot nodes)"
    
    log_info "Creating MongoDBSearch resource with dedicated search nodes..."
    
    # Create MongoDB Search resource - deploys mongot processes
    # This enables native $vectorSearch aggregation pipeline
    kubectl apply --context "${K8S_CTX}" -n "${MDB_NS}" -f - <<EOF
apiVersion: mongodb.com/v1
kind: MongoDBSearch
metadata:
  name: ${MDB_RESOURCE_NAME}
spec:
  # MongoDB resource is automatically inferred from matching name
  # Deploys dedicated mongot (search) nodes
  resourceRequirements:
    limits:
      cpu: "${SEARCH_CPU_LIMIT:-3}"
      memory: "${SEARCH_MEMORY_LIMIT:-5Gi}"
    requests:
      cpu: "2"
      memory: 3Gi
EOF
    
    # Wait for Search nodes to be ready
    log_info "Waiting for MongoDB Search nodes (mongot) to be ready..."
    kubectl --context "${K8S_CTX}" -n "${MDB_NS}" wait --for=jsonpath='{.status.phase}'=Running "mdbs/${MDB_RESOURCE_NAME}" --timeout=300s
    
    log_success "MongoDB Search & Vector Search deployed with dedicated mongot nodes"
    log_info "Vector Search is now available via \$vectorSearch aggregation pipeline"
}

# Display deployment summary
show_summary() {
    log_step "Deployment Complete!"
    
    echo -e "\n${GREEN}🎉 MongoDB Enterprise Advanced with Vector Search is ready!${NC}"
    echo ""
    echo "📊 Deployment Summary:"
    echo "   Kubernetes Context: $K8S_CTX"
    echo "   Namespace: $MDB_NS"
    echo "   MongoDB Resource: $MDB_RESOURCE_NAME"
    echo "   MongoDB Version: $MDB_VERSION"
    echo ""
    echo "🔍 MongoDB Search (Vector Search):"
    echo "   MongoDBSearch Resource: $MDB_RESOURCE_NAME"
    echo "   Search Nodes (mongot): Deployed"
    echo "   Vector Search: ENABLED"
    echo "   \$vectorSearch: Available in aggregation pipeline"
    echo ""
    echo "🔗 Access Information:"
    echo "   MongoDB Connection:"
    echo "   mongodb://mdb-user:${MDB_USER_PASSWORD}@${MDB_RESOURCE_NAME}-svc.${MDB_NS}.svc.cluster.local:27017/searchdb?replicaSet=${MDB_RESOURCE_NAME}"
    echo ""
    echo "   Ops Manager:"
    echo "   kubectl port-forward -n ${MDB_NS} service/ops-manager-service 8080:8080"
    echo "   Then open: http://localhost:8080"
    echo ""
    echo "📋 Useful Commands:"
    echo "   # View all resources"
    echo "   kubectl get pods -n ${MDB_NS}"
    echo "   kubectl get mdb -n ${MDB_NS}"
    echo "   kubectl get mdbs -n ${MDB_NS}"
    echo ""
    echo "   # View search nodes"
    echo "   kubectl get pods -n ${MDB_NS} -l app=${MDB_RESOURCE_NAME}-search-svc"
    echo ""
    echo "   # Access MongoDB shell"
    echo "   kubectl exec -it ${MDB_RESOURCE_NAME}-0 -n ${MDB_NS} -- mongosh"
    echo ""
    echo "🔧 Next Steps:"
    echo "   1. Create Vector Search Index:"
    echo "      mongosh < scripts/setup-vector-search.js"
    echo ""
    echo "   2. Or create via MongoDB shell:"
    echo "      kubectl exec -it ${MDB_RESOURCE_NAME}-0 -n ${MDB_NS} -- mongosh"
    echo "      use searchdb"
    echo "      db.documents.createSearchIndex({"
    echo "        name: \"vector_index\","
    echo "        type: \"vectorSearch\","
    echo "        definition: {"
    echo "          fields: [{"
    echo "            type: \"vector\","
    echo "            path: \"embedding\","
    echo "            numDimensions: 384,"
    echo "            similarity: \"cosine\""
    echo "          }]"
    echo "        }"
    echo "      })"
    echo ""
    echo "   3. Deploy your application:"
    echo "      Update backend MONGODB_URL to use the connection string above"
    echo ""
    echo "   4. Test Vector Search:"
    echo "      Upload documents → Generate embeddings → Use \$vectorSearch!"
    echo ""
    echo "📖 Documentation:"
    echo "   See MONGODB_ENTERPRISE_DEMO.md for full demo guide"
}

# Main deployment function
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        MongoDB Enterprise Advanced Deployment Script        ║"
    echo "║                    Single Executable                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Initialize
    create_default_config
    load_config
    detect_os
    detect_kubernetes
    
    # Deploy
    check_prerequisites
    install_operator
    deploy_ops_manager
    deploy_mongodb
    create_users
    deploy_search
    
    # Summary
    show_summary
}

# Run main function
main "$@"

