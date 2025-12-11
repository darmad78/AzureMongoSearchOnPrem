#!/bin/bash

# Script to fix Ollama model issues
# This script checks if the Ollama model is available and pulls it if needed

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-mongodb}"
OLLAMA_MODEL="${OLLAMA_MODEL:-phi}"

echo -e "${BLUE}🔍 Checking Ollama Setup${NC}"
echo ""

# Step 1: Check if Ollama pod exists
echo -e "${BLUE}Step 1: Checking Ollama pod...${NC}"
OLLAMA_POD=$(kubectl get pods -n ${NAMESPACE} -l app=ollama -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${OLLAMA_POD}" ]; then
    echo -e "${RED}❌ Ollama pod not found in namespace ${NAMESPACE}${NC}"
    echo "   Available pods:"
    kubectl get pods -n ${NAMESPACE} | grep ollama || echo "   No ollama pods found"
    exit 1
fi

echo -e "${GREEN}✅ Found Ollama pod: ${OLLAMA_POD}${NC}"

# Step 2: Check if Ollama is ready
echo -e "${BLUE}Step 2: Checking Ollama readiness...${NC}"
POD_STATUS=$(kubectl get pod ${OLLAMA_POD} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "${POD_STATUS}" != "Running" ]; then
    echo -e "${YELLOW}⚠️  Ollama pod is not running (status: ${POD_STATUS})${NC}"
    echo "   Waiting for pod to be ready..."
    kubectl wait --for=condition=Ready pod/${OLLAMA_POD} -n ${NAMESPACE} --timeout=120s || {
        echo -e "${RED}❌ Ollama pod did not become ready${NC}"
        echo "   Pod logs:"
        kubectl logs ${OLLAMA_POD} -n ${NAMESPACE} --tail=20
        exit 1
    }
fi

echo -e "${GREEN}✅ Ollama pod is running${NC}"

# Step 3: Check if Ollama service is accessible
echo -e "${BLUE}Step 3: Checking Ollama service accessibility...${NC}"
if kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Ollama service is accessible${NC}"
else
    echo -e "${YELLOW}⚠️  Ollama service may not be ready yet, waiting...${NC}"
    sleep 10
    if kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Ollama service is now accessible${NC}"
    else
        echo -e "${RED}❌ Cannot access Ollama service${NC}"
        echo "   Checking pod logs..."
        kubectl logs ${OLLAMA_POD} -n ${NAMESPACE} --tail=30
        exit 1
    fi
fi

# Step 4: List available models
echo -e "${BLUE}Step 4: Checking available models...${NC}"
MODELS_LIST=$(kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama list 2>/dev/null || echo "")

if [ -z "${MODELS_LIST}" ]; then
    echo -e "${YELLOW}⚠️  No models found or ollama list command failed${NC}"
else
    echo "   Available models:"
    echo "${MODELS_LIST}" | sed 's/^/   /'
fi

# Step 5: Check if the required model exists
echo -e "${BLUE}Step 5: Checking if model '${OLLAMA_MODEL}' is available...${NC}"
if echo "${MODELS_LIST}" | grep -q "${OLLAMA_MODEL}"; then
    echo -e "${GREEN}✅ Model '${OLLAMA_MODEL}' is already available${NC}"
    echo ""
    echo -e "${GREEN}🎉 Ollama is ready to use!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Model '${OLLAMA_MODEL}' not found${NC}"
fi

# Step 6: Pull the model
echo -e "${BLUE}Step 6: Pulling model '${OLLAMA_MODEL}'...${NC}"
echo -e "${YELLOW}   This may take several minutes (model size: ~3.8GB for llama2)${NC}"
echo ""

# Pull the model with progress output
kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull ${OLLAMA_MODEL} 2>&1 | while IFS= read -r line; do
    echo "   $line"
done

# Check if pull was successful
if kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama list 2>/dev/null | grep -q "${OLLAMA_MODEL}"; then
    echo ""
    echo -e "${GREEN}✅ Model '${OLLAMA_MODEL}' pulled successfully!${NC}"
else
    echo ""
    echo -e "${RED}❌ Failed to pull model '${OLLAMA_MODEL}'${NC}"
    echo "   Please check the logs above for errors"
    exit 1
fi

# Step 7: Verify model works
echo -e "${BLUE}Step 7: Testing model...${NC}"
TEST_RESPONSE=$(kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- curl -s -X POST http://localhost:11434/api/generate \
  -d '{"model": "'"${OLLAMA_MODEL}"'", "prompt": "Say hello in one word", "stream": false}' 2>/dev/null || echo "")

if echo "${TEST_RESPONSE}" | grep -q "response"; then
    echo -e "${GREEN}✅ Model test successful!${NC}"
    echo ""
    echo -e "${GREEN}🎉 Ollama is fully configured and ready!${NC}"
else
    echo -e "${YELLOW}⚠️  Model test returned unexpected response${NC}"
    echo "   Response: ${TEST_RESPONSE:0:200}"
fi

echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo "   Ollama Pod: ${OLLAMA_POD}"
echo "   Model: ${OLLAMA_MODEL}"
echo "   Namespace: ${NAMESPACE}"
echo ""
echo -e "${BLUE}💡 Next steps:${NC}"
echo "   1. Restart the backend pod to pick up the model:"
echo "      kubectl rollout restart deployment/search-backend -n ${NAMESPACE}"
echo "      (or: kubectl rollout restart deployment/backend -n ${NAMESPACE})"
echo ""
echo "   2. Check backend logs:"
echo "      kubectl logs -n ${NAMESPACE} -l app=search-backend -f"
echo "      (or: kubectl logs -n ${NAMESPACE} -l app=backend -f)"
echo ""
echo "   3. Test the health endpoint:"
echo "      curl http://<backend-url>/health/ollama"

