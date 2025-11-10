#!/bin/bash
set -e

# Test MongoDB Data Script
# This script checks if data exists in MongoDB and tests various query capabilities

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
log_step() { echo -e "\n${BLUE}🔍 $1${NC}\n=================================================="; }

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║            MongoDB Data Testing Script                     ║
║         Check Documents, Indexes, and Search               ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
POD_NAME="mdb-rs-0"
DB_NAME="searchdb"
COLLECTION_NAME="documents"
USERNAME="mdb-admin"
PASSWORD="admin-user-password-CHANGE-ME"

# Step 1: Verify MongoDB Connection
log_step "Step 1: Verifying MongoDB Connection"

log_info "Checking if MongoDB pod exists..."
if ! kubectl get pod ${POD_NAME} -n ${NAMESPACE} &>/dev/null; then
    log_error "MongoDB pod ${POD_NAME} not found in namespace ${NAMESPACE}"
    exit 1
fi
log_success "MongoDB pod found: ${POD_NAME}"

# Find mongosh binary
log_info "Locating mongosh binary..."
MONGOSH_PATH=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- find /var/lib/mongodb-mms-automation -name mongosh -type f 2>/dev/null | head -1 || echo "")

if [ -z "${MONGOSH_PATH}" ]; then
    log_error "Could not find mongosh binary in the pod"
    log_info "Trying to find mongo (legacy shell)..."
    MONGOSH_PATH=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- find /var/lib/mongodb-mms-automation -name mongo -type f 2>/dev/null | head -1 || echo "")
    if [ -z "${MONGOSH_PATH}" ]; then
        log_error "Could not find mongo shell"
        exit 1
    fi
fi
log_success "Found shell: ${MONGOSH_PATH}"

# Test connection
log_info "Testing MongoDB connection..."
TEST_CONN=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
    --eval "db.adminCommand('ping')" \
    -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
    --quiet 2>&1 || echo "failed")

if echo "${TEST_CONN}" | grep -q "ok.*1"; then
    log_success "MongoDB connection successful"
else
    log_error "MongoDB connection failed"
    echo "${TEST_CONN}"
    exit 1
fi

# Step 2: Check Database and Collection
log_step "Step 2: Checking Database and Collection"

log_info "Listing databases..."
DBS=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
    --eval "db.adminCommand('listDatabases')" \
    -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
    --quiet 2>&1)

if echo "${DBS}" | grep -q "${DB_NAME}"; then
    log_success "Database '${DB_NAME}' exists"
else
    log_warning "Database '${DB_NAME}' not found"
    echo ""
    echo "Available databases:"
    echo "${DBS}" | grep -o '"name"\s*:\s*"[^"]*"' || echo "None"
fi

# Step 3: Count Documents
log_step "Step 3: Counting Documents"

log_info "Counting documents in ${DB_NAME}.${COLLECTION_NAME}..."
DOC_COUNT=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
    --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.countDocuments({})" \
    -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
    --quiet 2>&1 | grep -v "switched to db" | grep -v "Defaulted container" | tail -1 | tr -d ' ')

if [ -z "${DOC_COUNT}" ] || [ "${DOC_COUNT}" = "0" ]; then
    log_warning "No documents found in collection"
    echo ""
    echo "📝 To add test documents, you can:"
    echo "   1. Use the backend API to insert documents"
    echo "   2. Run: curl -X POST http://backend-url/documents -d '{...}'"
    echo "   3. Use the frontend to add documents"
else
    log_success "Found ${DOC_COUNT} document(s) in collection"
fi

# Step 4: Show Sample Documents
log_step "Step 4: Showing Sample Documents"

if [ "${DOC_COUNT}" != "0" ] && [ -n "${DOC_COUNT}" ]; then
    log_info "Fetching first 3 documents..."
    kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
        --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.find().limit(3).forEach(doc => { print('---'); printjson(doc); })" \
        -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
        --quiet 2>&1 | grep -v "switched to db" | grep -v "Defaulted container" | tail -n +2
    
    echo ""
else
    log_warning "No documents to display"
fi

# Step 5: Check Indexes
log_step "Step 5: Checking Indexes"

log_info "Listing indexes on ${COLLECTION_NAME}..."
INDEXES=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
    --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.getIndexes()" \
    -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
    --quiet 2>&1 | grep -v "switched to db" | grep -v "Defaulted container")

if [ -n "${INDEXES}" ]; then
    echo "${INDEXES}"
else
    echo "   (No indexes or empty collection)"
fi
echo ""

# Check for specific index types
if echo "${INDEXES}" | grep -q "text"; then
    log_success "Text index found (for full-text search)"
else
    log_warning "No text index found"
fi

if echo "${INDEXES}" | grep -q "vector"; then
    log_success "Vector index found (for semantic search)"
else
    log_warning "No vector index found"
fi

# Step 6: Test Text Search (if documents exist)
log_step "Step 6: Testing Text Search"

if [ "${DOC_COUNT}" != "0" ]; then
    log_info "Testing text search with query 'test'..."
    SEARCH_RESULT=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
        --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.find({\$text: {\$search: 'test'}}).limit(2)" \
        -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
        --quiet 2>&1 || echo "Search failed")
    
    if echo "${SEARCH_RESULT}" | grep -q "_id"; then
        log_success "Text search is working"
        echo "Sample results:"
        echo "${SEARCH_RESULT}" | head -20
    else
        log_warning "Text search returned no results or failed"
        log_info "This is normal if no documents match 'test' or text index doesn't exist"
    fi
else
    log_warning "Skipping text search (no documents)"
fi

# Step 7: Check for Embeddings
log_step "Step 7: Checking for Embeddings"

if [ "${DOC_COUNT}" != "0" ]; then
    log_info "Checking if documents have embeddings..."
    EMBED_COUNT=$(kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
        --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.countDocuments({embedding: {\$exists: true}})" \
        -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
        --quiet 2>&1 | grep -v "switched to db" | grep -v "Defaulted container" | tail -1 | tr -d ' ')
    
    if [ "${EMBED_COUNT}" != "0" ]; then
        log_success "${EMBED_COUNT} document(s) have embeddings (ready for vector search)"
    else
        log_warning "No documents have embeddings"
        echo "   Embeddings are added by the backend when documents are created"
    fi
else
    log_warning "No documents to check"
fi

# Step 8: Collection Statistics
log_step "Step 8: Collection Statistics"

if [ "${DOC_COUNT}" != "0" ]; then
    log_info "Getting collection statistics..."
    kubectl exec ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \
        --eval "use ${DB_NAME}; db.${COLLECTION_NAME}.stats()" \
        -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin \
        --quiet 2>&1 | grep -E "count|size|storageSize|avgObjSize|nindexes" || echo "Stats not available"
else
    log_warning "Collection is empty, skipping statistics"
fi

# Step 9: Summary
log_step "Step 9: Summary"

echo -e "${GREEN}📊 MongoDB Data Summary:${NC}"
echo ""
echo "   Database: ${DB_NAME}"
echo "   Collection: ${COLLECTION_NAME}"
echo "   Document Count: ${DOC_COUNT:-0}"
echo "   Documents with Embeddings: ${EMBED_COUNT:-0}"
echo ""

if [ "${DOC_COUNT}" = "0" ]; then
    echo -e "${YELLOW}⚠️  No documents found. Here's how to add data:${NC}"
    echo ""
    echo "Option 1: Use the Backend API"
    echo "   # Port-forward the backend service"
    echo "   kubectl port-forward -n ${NAMESPACE} svc/backend-svc 8000:8000"
    echo ""
    echo "   # Add a document"
    echo '   curl -X POST http://localhost:8000/documents \'
    echo '     -H "Content-Type: application/json" \'
    echo '     -d '"'"'{'
    echo '       "title": "Test Document",'
    echo '       "body": "This is a test document for semantic search",'
    echo '       "tags": ["test", "sample"]'
    echo '     }'"'"
    echo ""
    echo "Option 2: Use the Frontend"
    echo "   Access the frontend UI and use the document upload feature"
    echo ""
    echo "Option 3: Manual MongoDB Insert"
    echo "   kubectl exec -it ${POD_NAME} -n ${NAMESPACE} -- ${MONGOSH_PATH} \\"
    echo "     -u ${USERNAME} -p ${PASSWORD} --authenticationDatabase admin"
    echo ""
    echo "   Then run:"
    echo "   use ${DB_NAME}"
    echo '   db.documents.insertOne({'
    echo '     title: "Sample Doc",'
    echo '     body: "Sample content",'
    echo '     tags: ["sample"]'
    echo '   })'
else
    log_success "MongoDB has data and is ready to use!"
    echo ""
    echo "✅ You can now:"
    echo "   • Perform text searches"
    echo "   • Use semantic/vector search (if embeddings exist)"
    echo "   • Test the RAG chat endpoint"
    echo "   • Add more documents via the backend API"
fi

echo ""
log_success "MongoDB data test complete!"

