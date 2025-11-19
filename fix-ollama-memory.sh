#!/bin/bash

# Script to fix Ollama memory issues
# The model is being killed due to insufficient memory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-mongodb}"
OLLAMA_POD=$(kubectl get pods -n ${NAMESPACE} -l app=ollama -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "${OLLAMA_POD}" ]; then
    echo -e "${RED}❌ Ollama pod not found${NC}"
    exit 1
fi

echo -e "${BLUE}🔍 Diagnosing Ollama Memory Issue${NC}"
echo ""

# Check current memory limits
echo -e "${BLUE}Current Ollama Memory Configuration:${NC}"
kubectl get deployment ollama -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq '.' 2>/dev/null || \
kubectl get deployment ollama -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].resources}'
echo ""

# Check node memory
echo -e "${BLUE}Node Memory Status:${NC}"
kubectl top nodes 2>/dev/null || echo "   Metrics not available"
echo ""

# Check available memory on nodes
echo -e "${BLUE}Node Memory Capacity:${NC}"
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory 2>/dev/null || echo "   Unable to get node info"
echo ""

echo -e "${YELLOW}⚠️  The issue: llama2 model needs ~6-8GB RAM to run${NC}"
echo "   - Model weights: ~3.8GB"
echo "   - KV cache: ~2GB"
echo "   - System overhead: ~1-2GB"
echo ""

echo -e "${BLUE}💡 Solutions:${NC}"
echo ""
echo -e "${GREEN}Option 1: Use a smaller model (RECOMMENDED)${NC}"
echo "   The 'phi' model is only ~1.6GB and works well:"
echo ""
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull phi"
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama rm llama2"
echo ""
echo "   Then update backend config to use 'phi' instead of 'llama2'"
echo ""

echo -e "${GREEN}Option 2: Increase Ollama memory limits${NC}"
echo "   If you have enough node memory, increase limits to 12Gi or 16Gi:"
echo ""
cat << 'EOF'
kubectl patch deployment ollama -n mongodb --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/limits/memory",
    "value": "12Gi"
  },
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources/requests/memory",
    "value": "8Gi"
  }
]'
EOF
echo ""

echo -e "${GREEN}Option 3: Reduce KV cache size${NC}"
echo "   Set OLLAMA_NUM_GPU=0 and use smaller context:"
echo ""
cat << 'EOF'
kubectl set env deployment/ollama -n mongodb OLLAMA_NUM_GPU=0
EOF
echo ""

echo -e "${BLUE}🚀 Quick Fix: Switch to phi model${NC}"
read -p "Do you want to switch to the phi model (smaller, ~1.6GB)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Pulling phi model...${NC}"
    kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull phi
    
    echo -e "${BLUE}Testing phi model...${NC}"
    if kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama run phi "Say hello" 2>&1 | grep -q "hello\|Hello\|Hi"; then
        echo -e "${GREEN}✅ Phi model works!${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  Now update your backend configuration:${NC}"
        echo "   kubectl patch configmap backend-config -n ${NAMESPACE} --type='json' -p='[{\"op\": \"replace\", \"path\": \"/data/OLLAMA_MODEL\", \"value\": \"phi\"}]'"
        echo ""
        echo "   Then restart backend:"
        echo "   kubectl rollout restart deployment/search-backend -n ${NAMESPACE}"
        echo "   (or: kubectl rollout restart deployment/backend -n ${NAMESPACE})"
    else
        echo -e "${RED}❌ Phi model test failed${NC}"
    fi
fi

