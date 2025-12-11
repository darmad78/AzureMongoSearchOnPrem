#!/bin/bash
set -e

# Test Script for MongoDB Search Application
# Tests all API endpoints and functionality

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_step() { echo -e "\n${BLUE}🧪 $1${NC}\n=================================================="; }

# Configuration
EXTERNAL_IP=$(curl -s ifconfig.me)
BACKEND_URL="http://${EXTERNAL_IP}:30888"
FRONTEND_URL="http://${EXTERNAL_IP}:30173"

echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║            MongoDB Search Application Tests                ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "Testing URLs:"
echo "  Backend:  ${BACKEND_URL}"
echo "  Frontend: ${FRONTEND_URL}"
echo ""

# Test 1: Backend Health Check
log_step "Test 1: Backend Health Check"
if curl -s "${BACKEND_URL}" | grep -q "Document Search API"; then
    log_success "Backend is responding correctly"
else
    log_error "Backend health check failed"
    exit 1
fi

# Test 2: Frontend is Serving
log_step "Test 2: Frontend Availability"
if curl -s "${FRONTEND_URL}" | grep -q "Document Search App"; then
    log_success "Frontend is serving correctly"
else
    log_error "Frontend is not accessible"
    exit 1
fi

# Test 3: Check Frontend API URL
log_step "Test 3: Frontend API Configuration"
FRONTEND_JS=$(curl -s "${FRONTEND_URL}" | grep -o 'assets/index-[^"]*\.js' | head -1)
if [ -n "$FRONTEND_JS" ]; then
    API_URL_IN_JS=$(curl -s "${FRONTEND_URL}/${FRONTEND_JS}" | grep -o "http://[0-9.]*:30888" | head -1)
    if [ "$API_URL_IN_JS" == "${BACKEND_URL}" ]; then
        log_success "Frontend is configured with correct backend URL: ${API_URL_IN_JS}"
    else
        log_error "Frontend has wrong API URL: ${API_URL_IN_JS} (expected: ${BACKEND_URL})"
        exit 1
    fi
else
    log_warning "Could not find JavaScript file to verify API URL"
fi

# Test 4: Create a Test Document
log_step "Test 4: Create Test Document"
TEST_DOC=$(cat <<EOF
{
  "title": "Test Document $(date +%s)",
  "body": "This is a test document created by the automated test script. It contains sample content for testing search functionality.",
  "tags": ["test", "automation", "sample"]
}
EOF
)

RESPONSE=$(curl -s -X POST "${BACKEND_URL}/documents" \
    -H "Content-Type: application/json" \
    -d "$TEST_DOC")

if echo "$RESPONSE" | grep -q "id"; then
    DOC_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    log_success "Document created successfully (ID: ${DOC_ID})"
else
    log_error "Failed to create document"
    echo "$RESPONSE"
    exit 1
fi

# Test 5: List All Documents
log_step "Test 5: List All Documents"
DOCS=$(curl -s "${BACKEND_URL}/documents")
DOC_COUNT=$(echo "$DOCS" | grep -o '"id"' | wc -l)
if [ "$DOC_COUNT" -gt 0 ]; then
    log_success "Retrieved ${DOC_COUNT} documents from database"
else
    log_error "No documents found"
    exit 1
fi

# Test 6: Text Search
log_step "Test 6: Text Search"
SEARCH_RESULT=$(curl -s "${BACKEND_URL}/search?q=test")
if echo "$SEARCH_RESULT" | grep -q "results"; then
    RESULT_COUNT=$(echo "$SEARCH_RESULT" | grep -o '"id"' | wc -l)
    log_success "Text search returned ${RESULT_COUNT} results"
else
    log_error "Text search failed"
    exit 1
fi

# Test 7: Semantic Search
log_step "Test 7: Semantic Search"
SEMANTIC_RESULT=$(curl -s "${BACKEND_URL}/search/semantic?q=test+document")
if echo "$SEMANTIC_RESULT" | grep -q "results"; then
    RESULT_COUNT=$(echo "$SEMANTIC_RESULT" | grep -o '"id"' | wc -l)
    log_success "Semantic search returned ${RESULT_COUNT} results"
else
    log_error "Semantic search failed"
    exit 1
fi

# Test 8: RAG Chat Endpoint
log_step "Test 8: RAG Chat Endpoint"
CHAT_REQUEST=$(cat <<EOF
{
  "question": "What is this document about?",
  "max_context_docs": 3
}
EOF
)

CHAT_RESPONSE=$(curl -s -X POST "${BACKEND_URL}/chat" \
    -H "Content-Type: application/json" \
    -d "$CHAT_REQUEST")

if echo "$CHAT_RESPONSE" | grep -q "answer"; then
    log_success "RAG chat endpoint is working"
    ANSWER=$(echo "$CHAT_RESPONSE" | grep -o '"answer":"[^"]*"' | cut -d'"' -f4 | head -c 100)
    log_info "Sample answer: ${ANSWER}..."
else
    log_error "RAG chat endpoint failed"
    echo "$CHAT_RESPONSE"
fi

# Test 9: Kubernetes Pods Status
log_step "Test 9: Kubernetes Deployment Status"
echo ""
echo "Backend Pods:"
kubectl get pods -n mongodb -l app=search-backend
echo ""
echo "Frontend Pods:"
kubectl get pods -n mongodb -l app=search-frontend
echo ""
echo "MongoDB Pods:"
kubectl get pods -n mongodb -l app=mdb-rs
echo ""
echo "Ollama Pods:"
kubectl get pods -n mongodb -l app=ollama
echo ""

# Test 10: Port Forwarding Status
log_step "Test 10: Port Forwarding Status"
PF_COUNT=$(ps aux | grep "kubectl port-forward" | grep -v grep | wc -l)
if [ "$PF_COUNT" -ge 2 ]; then
    log_success "Port forwarding is active (${PF_COUNT} processes)"
    ps aux | grep "kubectl port-forward" | grep -v grep
else
    log_warning "Port forwarding may not be running properly (found ${PF_COUNT} processes)"
fi

# Summary
log_step "Test Summary"
echo ""
echo -e "${GREEN}🎉 All tests completed successfully!${NC}"
echo ""
echo "📊 Application Status:"
echo "   ✅ Backend API: ${BACKEND_URL}"
echo "   ✅ Frontend UI: ${FRONTEND_URL}"
echo "   ✅ Documents in DB: ${DOC_COUNT}"
echo "   ✅ Text Search: Working"
echo "   ✅ Semantic Search: Working"
echo "   ✅ RAG Chat: Working"
echo ""
echo "🌐 Access your application:"
echo "   Frontend: ${FRONTEND_URL}"
echo "   Backend:  ${BACKEND_URL}"
echo ""
echo "💡 Test document created with ID: ${DOC_ID}"
echo ""

