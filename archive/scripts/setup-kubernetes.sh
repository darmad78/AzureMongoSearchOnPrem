#!/bin/bash

# MongoDB Enterprise Advanced Kubernetes Setup Script
# This script sets up a local Kubernetes cluster and deploys MongoDB Enterprise with Search

set -e

echo "🚀 Setting up MongoDB Enterprise Advanced with Kubernetes..."

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    echo "   Visit: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    echo "   Visit: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Set environment variables
export K8S_CTX="docker-desktop"  # or minikube, kind, etc.
export MDB_NS="mongodb"
export MDB_RESOURCE_NAME="mdb-rs"
export OPS_MANAGER_PROJECT_NAME="search-project"
export OPS_MANAGER_API_URL="https://localhost:8443"  # Ops Manager will be deployed here
export MDB_VERSION="8.2.1-ent"
export MDB_ADMIN_USER_PASSWORD="admin-user-password-CHANGE-ME"
export MDB_USER_PASSWORD="mdb-user-password-CHANGE-ME"
export MDB_SEARCH_SYNC_USER_PASSWORD="search-sync-user-password-CHANGE-ME"

echo "📋 Environment variables set:"
echo "   K8S_CTX: $K8S_CTX"
echo "   MDB_NS: $MDB_NS"
echo "   MDB_RESOURCE_NAME: $MDB_RESOURCE_NAME"
echo "   MDB_VERSION: $MDB_VERSION"

# Create namespace
echo "📦 Creating namespace..."
kubectl create namespace $MDB_NS --dry-run=client -o yaml | kubectl apply -f -

# Add MongoDB Helm repository
echo "📦 Adding MongoDB Helm repository..."
helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update mongodb

# Install MongoDB Kubernetes Operator
echo "🔧 Installing MongoDB Kubernetes Operator..."
helm upgrade --install --kube-context "${K8S_CTX}" \
  --create-namespace \
  --namespace="${MDB_NS}" \
  mongodb-kubernetes \
  "${OPERATOR_HELM_CHART:-mongodb/mongodb-kubernetes}"

echo "✅ MongoDB Kubernetes Operator installed successfully!"
echo ""
echo "📝 Next steps:"
echo "   1. Deploy Ops Manager (run setup-ops-manager.sh)"
echo "   2. Deploy MongoDB Enterprise (run setup-mongodb.sh)"
echo "   3. Deploy MongoDB Search (run setup-search.sh)"
echo ""
echo "🔗 Useful commands:"
echo "   kubectl get pods -n $MDB_NS"
echo "   kubectl logs -n $MDB_NS deployment/mongodb-kubernetes-operator"

