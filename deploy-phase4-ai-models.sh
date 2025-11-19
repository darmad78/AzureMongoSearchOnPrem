#!/bin/bash
set -e

# Phase 4: Deploy AI Models (Embedding & LLM)
# This deploys Ollama for LLM inference with configurable models

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
║              Phase 4: AI Models Deployment                 ║
║         Embedding Model & LLM (Ollama) Setup               ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Configuration
NAMESPACE="mongodb"
OLLAMA_MODEL="${OLLAMA_MODEL:-phi}"  # Default to phi (smaller, works with 8Gi memory), can be overridden
EMBEDDING_MODEL="${EMBEDDING_MODEL:-all-MiniLM-L6-v2}"  # Default embedding model
WHISPER_MODEL="${WHISPER_MODEL:-base}"  # Default Whisper model for speech-to-text

log_info "Configuration:"
echo "  📦 LLM Model: ${OLLAMA_MODEL}"
echo "  📦 Embedding Model: ${EMBEDDING_MODEL}"
echo "  📦 Whisper Model: ${WHISPER_MODEL}"
echo "  📦 Namespace: ${NAMESPACE}"
echo ""

log_info "You can change these by setting environment variables:"
echo "  export OLLAMA_MODEL=mistral    # or llama3, codellama, etc."
echo "  export EMBEDDING_MODEL=all-MiniLM-L6-v2"
echo "  export WHISPER_MODEL=base      # or small, medium, large"
echo ""

# Step 1: Deploy Ollama
log_step "Step 1: Deploying Ollama (LLM Service)"

log_info "Deploying Ollama to Kubernetes..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-data
  namespace: ${NAMESPACE}
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
  name: ollama
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        ports:
        - containerPort: 11434
        volumeMounts:
        - name: ollama-data
          mountPath: /root/.ollama
        env:
        - name: OLLAMA_HOST
          value: "0.0.0.0:11434"
        - name: OLLAMA_ORIGINS
          value: "*"
        readinessProbe:
          httpGet:
            path: /api/tags
            port: 11434
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /api/tags
            port: 11434
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          successThreshold: 1
          failureThreshold: 3
        resources:
          requests:
            cpu: "1"
            memory: "4Gi"
          limits:
            cpu: "4"
            memory: "8Gi"
      volumes:
      - name: ollama-data
        persistentVolumeClaim:
          claimName: ollama-data
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-svc
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ollama
  ports:
  - port: 11434
    targetPort: 11434
  type: ClusterIP
EOF

log_success "Ollama deployment created"

# Step 2: Wait for Ollama to be ready
log_step "Step 2: Waiting for Ollama to be Ready"

log_info "Waiting for Ollama pod to be created..."
echo ""
echo "💡 Monitor progress in another terminal:"
echo "   kubectl get pods -n ${NAMESPACE} -l app=ollama -w"
echo "   kubectl logs -n ${NAMESPACE} -l app=ollama -f"
echo ""

# Wait for pod to exist
TIMEOUT=120
ELAPSED=0
while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
  OLLAMA_POD=$(kubectl get pods -n ${NAMESPACE} -l app=ollama -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -n "${OLLAMA_POD}" ]; then
    log_success "Ollama pod created: ${OLLAMA_POD}"
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ -z "${OLLAMA_POD}" ]; then
  log_error "Ollama pod was not created within ${TIMEOUT}s"
  exit 1
fi

log_info "Waiting for Ollama pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=ollama -n ${NAMESPACE} --timeout=300s || {
  log_error "Ollama pod did not become ready"
  log_info "Checking pod status..."
  kubectl describe pod -l app=ollama -n ${NAMESPACE} | tail -30
  exit 1
}

log_success "Ollama pod is ready"

# Verify Ollama is responding
log_info "Verifying Ollama API is accessible..."
OLLAMA_POD=$(kubectl get pods -n ${NAMESPACE} -l app=ollama -o jsonpath='{.items[0].metadata.name}')
kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- curl -s http://localhost:11434/api/tags >/dev/null && \
  log_success "Ollama API is responding" || \
  log_warning "Ollama API check failed, but continuing..."

# Step 3: Pull LLM Model
log_step "Step 3: Pulling LLM Model (${OLLAMA_MODEL})"

log_info "Pulling ${OLLAMA_MODEL} model into Ollama..."
log_warning "This may take several minutes depending on model size"
echo ""
echo "💡 Model sizes (approximate):"
echo "   llama2 (7B):      ~3.8GB"
echo "   llama3 (8B):      ~4.7GB"
echo "   mistral (7B):     ~4.1GB"
echo "   codellama (7B):   ~3.8GB"
echo "   llama2:13b:       ~7.4GB"
echo ""

# Pull the model
log_info "Executing: ollama pull ${OLLAMA_MODEL}"
kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull ${OLLAMA_MODEL} 2>&1 | while IFS= read -r line; do
  echo "   $line"
done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log_success "Model ${OLLAMA_MODEL} pulled successfully"
else
  log_error "Failed to pull model ${OLLAMA_MODEL}"
  log_info "You can manually pull it later with:"
  echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull ${OLLAMA_MODEL}"
  exit 1
fi

# Verify model is available
log_info "Verifying model is available..."
MODELS_LIST=$(kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama list 2>/dev/null || echo "")
if echo "${MODELS_LIST}" | grep -q "${OLLAMA_MODEL}"; then
  log_success "Model ${OLLAMA_MODEL} is available"
  echo ""
  echo "📋 Available models:"
  echo "${MODELS_LIST}" | while IFS= read -r line; do
    echo "   $line"
  done
else
  log_warning "Model verification failed, but it may still work"
fi

# Step 4: Create Model Configuration ConfigMap
log_step "Step 4: Creating Model Configuration"

log_info "Creating ConfigMap with model configuration..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-models-config
  namespace: ${NAMESPACE}
data:
  # LLM Configuration
  LLM_PROVIDER: "ollama"
  OLLAMA_URL: "http://ollama-svc:11434"
  OLLAMA_MODEL: "${OLLAMA_MODEL}"
  
  # Embedding Model (used by backend)
  EMBEDDING_MODEL: "${EMBEDDING_MODEL}"
  
  # Whisper Model (used by backend for speech-to-text)
  WHISPER_MODEL: "${WHISPER_MODEL}"
  
  # Model Information
  MODEL_INFO: |
    LLM: ${OLLAMA_MODEL} (via Ollama)
    Embedding: ${EMBEDDING_MODEL} (via sentence-transformers)
    Speech-to-Text: ${WHISPER_MODEL} (via Whisper)
EOF

log_success "Model configuration created"

# Step 5: Verify Deployment
log_step "Step 5: Verifying AI Models Deployment"

log_info "Checking all components..."
echo ""

echo "Ollama Deployment:"
kubectl get deployment ollama -n ${NAMESPACE}
echo ""

echo "Ollama Pod:"
kubectl get pods -n ${NAMESPACE} -l app=ollama
echo ""

echo "Ollama Service:"
kubectl get svc ollama-svc -n ${NAMESPACE}
echo ""

echo "Model Configuration:"
kubectl get configmap ai-models-config -n ${NAMESPACE}
echo ""

# Test Ollama with a simple query
log_info "Testing Ollama with a simple query..."
TEST_RESPONSE=$(kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- curl -s -X POST http://localhost:11434/api/generate \
  -d '{"model": "'"${OLLAMA_MODEL}"'", "prompt": "Say hello in one word", "stream": false}' 2>/dev/null || echo "")

if [ -n "${TEST_RESPONSE}" ] && echo "${TEST_RESPONSE}" | grep -q "response"; then
  log_success "Ollama is working correctly"
  RESPONSE_TEXT=$(echo "${TEST_RESPONSE}" | grep -o '"response":"[^"]*"' | sed 's/"response":"\(.*\)"/\1/' | head -c 100)
  log_info "Test response: ${RESPONSE_TEXT}"
else
  log_warning "Could not verify Ollama response, but deployment is complete"
fi

log_success "Phase 4 complete! AI Models are deployed."
echo ""

# Step 6: Access Information
log_step "Step 6: Access Information & Next Steps"

echo -e "${GREEN}🎉 AI Models Deployment Summary:${NC}"
echo ""
echo "📦 Deployed Models:"
echo "   ✅ LLM: ${OLLAMA_MODEL} (via Ollama)"
echo "   ✅ Embedding: ${EMBEDDING_MODEL} (will be loaded by backend)"
echo "   ✅ Speech-to-Text: ${WHISPER_MODEL} (will be loaded by backend)"
echo ""

echo "🔗 Ollama Service:"
echo "   Internal URL: http://ollama-svc.${NAMESPACE}.svc.cluster.local:11434"
echo "   Service Name: ollama-svc"
echo "   Port: 11434"
echo ""

echo "📋 Useful Commands:"
echo ""
echo "   # Check Ollama status"
echo "   kubectl get pods -n ${NAMESPACE} -l app=ollama"
echo ""
echo "   # View Ollama logs"
echo "   kubectl logs -n ${NAMESPACE} -l app=ollama -f"
echo ""
echo "   # List available models"
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama list"
echo ""
echo "   # Pull additional models"
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull mistral"
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull llama3"
echo ""
echo "   # Test Ollama directly"
echo "   kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama run ${OLLAMA_MODEL}"
echo ""
echo "   # Access Ollama from another pod"
echo "   curl -X POST http://ollama-svc:11434/api/generate \\"
echo "     -d '{\"model\": \"${OLLAMA_MODEL}\", \"prompt\": \"Hello\", \"stream\": false}'"
echo ""

echo "🔄 To change models:"
echo "   1. Pull new model:"
echo "      kubectl exec ${OLLAMA_POD} -n ${NAMESPACE} -- ollama pull <model-name>"
echo ""
echo "   2. Update ConfigMap:"
echo "      kubectl edit configmap ai-models-config -n ${NAMESPACE}"
echo ""
echo "   3. Restart backend (Phase 5) to use new models"
echo ""

echo "🎯 Next Steps:"
echo "   ✅ Phase 1: Ops Manager deployed"
echo "   ✅ Phase 2: MongoDB Enterprise deployed"
echo "   ✅ Phase 3: MongoDB Search deployed"
echo "   ✅ Phase 4: AI Models deployed"
echo "   📝 Phase 5: Deploy Backend & Frontend"
echo ""
echo "   Run: ./deploy-phase5-backend-frontend.sh"
echo ""

log_success "Phase 4 deployment complete! 🚀"

