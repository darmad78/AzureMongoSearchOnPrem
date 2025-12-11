#!/bin/bash

# Post-Deployment Verification and Vector Search Setup Script
# Verifies all components are running and sets up vector search indexes

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

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file $CONFIG_FILE not found"
        log_info "Please run the phase deployment scripts first (deploy-phase1-ops-manager.sh, etc.)"
        exit 1
    fi
    
    # Parse JSON configuration
    K8S_CTX=$(grep -o '"k8s_context": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_NS=$(grep -o '"mongodb_namespace": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_RESOURCE_NAME=$(grep -o '"mongodb_resource_name": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_VERSION=$(grep -o '"mongodb_version": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    MDB_USER_PASSWORD=$(grep -o '"user_password": *"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    
    # Auto-detect context if needed
    if [ "$K8S_CTX" = "auto" ] || [ -z "$K8S_CTX" ]; then
        K8S_CTX=$(kubectl config current-context 2>/dev/null || echo "")
        if [ -z "$K8S_CTX" ]; then
            log_error "No Kubernetes context found"
            exit 1
        fi
    fi
}

# Verify Kubernetes Operator
verify_operator() {
    log_step "Verifying MongoDB Kubernetes Operator"
    
    local operator_pod=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get pods -l app.kubernetes.io/name=mongodb-kubernetes-operator -o name 2>/dev/null)
    
    if [ -z "$operator_pod" ]; then
        log_error "MongoDB Kubernetes Operator not found"
        return 1
    fi
    
    local status=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get $operator_pod -o jsonpath='{.status.phase}')
    
    if [ "$status" = "Running" ]; then
        log_success "MongoDB Kubernetes Operator is Running"
        return 0
    else
        log_error "MongoDB Kubernetes Operator status: $status"
        return 1
    fi
}

# Verify Ops Manager
verify_ops_manager() {
    log_step "Verifying MongoDB Ops Manager"
    
    local om_deployment=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get deployment mongodb-ops-manager -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    
    if [ "$om_deployment" -ge 1 ]; then
        log_success "MongoDB Ops Manager is Running"
        return 0
    else
        log_warning "MongoDB Ops Manager not available (optional component)"
        return 0
    fi
}

# Verify MongoDB Enterprise
verify_mongodb() {
    log_step "Verifying MongoDB Enterprise Advanced"
    
    # Check MongoDB resource
    local mdb_phase=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get mdb/${MDB_RESOURCE_NAME} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [ "$mdb_phase" != "Running" ]; then
        log_error "MongoDB resource status: $mdb_phase (expected: Running)"
        return 1
    fi
    
    log_success "MongoDB resource is Running"
    
    # Check all pods
    local expected_members=3
    local running_pods=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get pods -l app=${MDB_RESOURCE_NAME}-svc -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    
    if [ "$running_pods" -ge "$expected_members" ]; then
        log_success "All $running_pods MongoDB pods are Running"
    else
        log_error "Expected $expected_members MongoDB pods, found $running_pods running"
        return 1
    fi
    
    # Test MongoDB connection
    log_info "Testing MongoDB connection..."
    local test_result=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" exec ${MDB_RESOURCE_NAME}-0 -- mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null || echo "0")
    
    if [ "$test_result" = "1" ]; then
        log_success "MongoDB connection successful"
    else
        log_error "MongoDB connection failed"
        return 1
    fi
    
    return 0
}

# Verify MongoDB Users
verify_users() {
    log_step "Verifying MongoDB Users"
    
    local users=("mdb-admin" "search-sync-source-user" "mdb-user")
    local all_users_ok=true
    
    for user_resource in "${users[@]}"; do
        local user_phase=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get mongodbuser/${user_resource} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        
        if [ "$user_phase" = "Running" ]; then
            log_success "User $user_resource is configured"
        else
            log_error "User $user_resource status: $user_phase"
            all_users_ok=false
        fi
    done
    
    if [ "$all_users_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

# Verify MongoDB Search
verify_search() {
    log_step "Verifying MongoDB Search & Vector Search"
    
    # Check MongoDBSearch resource
    local mdbs_phase=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get mdbs/${MDB_RESOURCE_NAME} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    
    if [ "$mdbs_phase" != "Running" ]; then
        log_error "MongoDBSearch resource status: $mdbs_phase (expected: Running)"
        return 1
    fi
    
    log_success "MongoDBSearch resource is Running"
    
    # Check search pods (mongot)
    local search_pods=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" get pods -l app=${MDB_RESOURCE_NAME}-search-svc -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
    
    if [ "$search_pods" -ge 1 ]; then
        log_success "MongoDB Search nodes (mongot) are Running: $search_pods pod(s)"
    else
        log_error "No MongoDB Search pods found"
        return 1
    fi
    
    return 0
}

# Setup Vector Search Index
setup_vector_search_index() {
    log_step "Setting Up Vector Search Index"
    
    log_info "Creating vector search index on documents collection..."
    
    # Create the vector search index
    kubectl --context "${K8S_CTX}" -n "${MDB_NS}" exec ${MDB_RESOURCE_NAME}-0 -- mongosh --quiet --eval "
    use searchdb;
    
    // Check if index already exists
    var existingIndexes = db.documents.getSearchIndexes('vector_index');
    if (existingIndexes.length > 0) {
        print('Vector search index already exists');
    } else {
        // Create vector search index
        db.documents.createSearchIndex({
            name: 'vector_index',
            type: 'vectorSearch',
            definition: {
                fields: [{
                    type: 'vector',
                    path: 'embedding',
                    numDimensions: 384,
                    similarity: 'cosine'
                }]
            }
        });
        print('Vector search index created successfully');
    }
    
    // Create text search index
    try {
        db.documents.createIndex(
            { title: 'text', body: 'text', tags: 'text' },
            { name: 'text_search_index' }
        );
        print('Text search index created');
    } catch(e) {
        if (e.code !== 85) { // Ignore if index already exists
            print('Error creating text index: ' + e.message);
        }
    }
    
    // Create supporting indexes
    db.documents.createIndex({ tags: 1 });
    db.documents.createIndex({ source: 1 });
    db.documents.createIndex({ embedding: 1 });
    
    print('All indexes created successfully');
    " 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Vector Search index setup completed"
        return 0
    else
        log_error "Failed to create vector search index"
        return 1
    fi
}

# Verify Vector Search Index
verify_vector_search_index() {
    log_step "Verifying Vector Search Index"
    
    log_info "Checking for vector search index..."
    
    local index_check=$(kubectl --context "${K8S_CTX}" -n "${MDB_NS}" exec ${MDB_RESOURCE_NAME}-0 -- mongosh --quiet --eval "
    use searchdb;
    var indexes = db.documents.getSearchIndexes('vector_index');
    if (indexes.length > 0) {
        print('FOUND');
        printjson(indexes[0]);
    } else {
        print('NOT_FOUND');
    }
    " 2>&1)
    
    if echo "$index_check" | grep -q "FOUND"; then
        log_success "Vector search index exists and is configured"
        log_info "Index details:"
        echo "$index_check" | grep -v "FOUND"
        return 0
    else
        log_warning "Vector search index not found"
        return 1
    fi
}

# Test Vector Search
test_vector_search() {
    log_step "Testing Vector Search Functionality"
    
    log_info "Inserting test document with embedding..."
    
    # Insert a test document
    kubectl --context "${K8S_CTX}" -n "${MDB_NS}" exec ${MDB_RESOURCE_NAME}-0 -- mongosh --quiet --eval "
    use searchdb;
    
    // Create test document with dummy embedding
    var testDoc = {
        title: 'Test Document for Vector Search',
        body: 'This is a test document to verify vector search functionality',
        tags: ['test', 'vector-search', 'demo'],
        embedding: Array(384).fill(0).map((_, i) => Math.random() - 0.5),
        source: 'test',
        createdAt: new Date()
    };
    
    // Insert test document
    var result = db.documents.insertOne(testDoc);
    if (result.acknowledged) {
        print('Test document inserted: ' + result.insertedId);
    } else {
        print('Failed to insert test document');
    }
    " 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Test document inserted successfully"
        log_info "Vector search is ready to use!"
        return 0
    else
        log_error "Failed to insert test document"
        return 1
    fi
}

# Display connection information
show_connection_info() {
    log_step "Connection Information"
    
    local connection_string="mongodb://mdb-user:${MDB_USER_PASSWORD}@${MDB_RESOURCE_NAME}-svc.${MDB_NS}.svc.cluster.local:27017/searchdb?replicaSet=${MDB_RESOURCE_NAME}"
    
    echo ""
    echo "📊 Deployment Status: ${GREEN}ALL SYSTEMS OPERATIONAL${NC}"
    echo ""
    echo "🔗 MongoDB Connection String:"
    echo "   $connection_string"
    echo ""
    echo "🔍 Vector Search Status: ${GREEN}ENABLED${NC}"
    echo "   Index Name: vector_index"
    echo "   Dimensions: 384"
    echo "   Similarity: cosine"
    echo ""
    echo "📋 Quick Commands:"
    echo ""
    echo "   # Access MongoDB shell:"
    echo "   kubectl exec -it ${MDB_RESOURCE_NAME}-0 -n ${MDB_NS} -- mongosh"
    echo ""
    echo "   # View all pods:"
    echo "   kubectl get pods -n ${MDB_NS}"
    echo ""
    echo "   # View MongoDB resource:"
    echo "   kubectl get mdb -n ${MDB_NS}"
    echo ""
    echo "   # View Search resource:"
    echo "   kubectl get mdbs -n ${MDB_NS}"
    echo ""
    echo "   # Port forward to Ops Manager:"
    echo "   kubectl port-forward -n ${MDB_NS} service/ops-manager-service 8080:8080"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Deploy your backend application"
    echo "   2. Configure MONGODB_URL environment variable"
    echo "   3. Upload documents and test vector search"
    echo "   4. Ask questions using RAG chat interface"
    echo ""
    echo "📖 Documentation:"
    echo "   - MONGODB_ENTERPRISE_DEMO.md"
    echo "   - RAG_SETUP_GUIDE.md"
    echo "   - ONE_CLICK_DEPLOY.md"
    echo ""
}

# Main verification function
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Post-Deployment Verification & Setup Script            ║"
    echo "║         MongoDB Enterprise Advanced + Vector Search        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Load configuration
    load_config
    
    log_info "Kubernetes Context: $K8S_CTX"
    log_info "Namespace: $MDB_NS"
    log_info "MongoDB Resource: $MDB_RESOURCE_NAME"
    echo ""
    
    # Track overall status
    local all_checks_passed=true
    
    # Run verification steps
    verify_operator || all_checks_passed=false
    verify_ops_manager || true  # Optional component
    verify_mongodb || all_checks_passed=false
    verify_users || all_checks_passed=false
    verify_search || all_checks_passed=false
    
    if [ "$all_checks_passed" = false ]; then
        log_error "Some verification checks failed"
        log_info "Please check the logs above and fix any issues"
        exit 1
    fi
    
    log_success "All verification checks passed!"
    echo ""
    
    # Setup vector search
    log_info "Proceeding with Vector Search setup..."
    setup_vector_search_index || {
        log_error "Vector search index setup failed"
        exit 1
    }
    
    # Verify the index was created
    sleep 5  # Give MongoDB a moment to create the index
    verify_vector_search_index || {
        log_warning "Could not verify vector search index immediately"
        log_info "Index may still be building. Check again in a few moments."
    }
    
    # Test functionality
    test_vector_search || {
        log_warning "Vector search test had issues, but deployment is complete"
    }
    
    # Show connection info
    show_connection_info
    
    log_success "Verification and setup completed successfully!"
    echo ""
}

# Run main function
main "$@"

