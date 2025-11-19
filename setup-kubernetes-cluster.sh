#!/bin/bash

# Kubernetes Cluster Setup Script for Ubuntu
# Provides options for minikube, kind, or microk8s

set -e

echo "☸️ Setting up Kubernetes cluster for Ubuntu..."

# Function to setup minikube
setup_minikube() {
    echo "🏗️ Setting up minikube cluster..."
    
    # Start minikube
    minikube start --driver=docker --memory=8192 --cpus=4
    
    # Enable required addons
    minikube addons enable metrics-server
    minikube addons enable ingress
    
    # Set kubectl context
    kubectl config use-context minikube
    
    echo "✅ minikube cluster ready!"
    echo "   Context: minikube"
    echo "   Dashboard: minikube dashboard"
}

# Function to setup kind
setup_kind() {
    echo "🏗️ Setting up kind cluster..."
    
    # Create kind cluster with more resources
    cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        system-reserved: memory=2Gi
        kube-reserved: memory=2Gi
  extraPortMappings:
  - containerPort: 30000
    hostPort: 8080
    protocol: TCP
  - containerPort: 30001
    hostPort: 27017
    protocol: TCP
EOF
    
    kind create cluster --config=kind-config.yaml --name mongodb-cluster
    
    echo "✅ kind cluster ready!"
    echo "   Context: kind-mongodb-cluster"
    echo "   Port 8080 -> 30000 (Ops Manager)"
    echo "   Port 27017 -> 30001 (MongoDB)"
}

# Function to setup microk8s
setup_microk8s() {
    echo "🏗️ Setting up microk8s cluster..."
    
    # Install microk8s
    sudo snap install microk8s --classic
    
    # Add user to microk8s group
    sudo usermod -a -G microk8s $USER
    
    # Enable required addons
    sudo microk8s enable dns storage ingress metrics-server
    
    # Create kubectl alias
    echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
    source ~/.bashrc
    
    echo "✅ microk8s cluster ready!"
    echo "   Context: microk8s"
    echo "   Note: Use 'microk8s kubectl' instead of 'kubectl'"
}

# Main menu
echo "Choose your Kubernetes setup:"
echo "1) minikube (recommended for development)"
echo "2) kind (lightweight, good for CI/CD)"
echo "3) microk8s (snap-based, easy setup)"
echo "4) Skip (use existing cluster)"

read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        setup_minikube
        CLUSTER_CONTEXT="minikube"
        ;;
    2)
        setup_kind
        CLUSTER_CONTEXT="kind-mongodb-cluster"
        ;;
    3)
        setup_microk8s
        CLUSTER_CONTEXT="microk8s"
        ;;
    4)
        echo "⏭️ Skipping cluster setup"
        echo "Please update your .env file with the correct K8S_CTX value"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Update environment file
if [ -f .env ]; then
    sed -i "s/K8S_CTX=.*/K8S_CTX=\"$CLUSTER_CONTEXT\"/" .env
    echo "✅ Updated .env file with cluster context: $CLUSTER_CONTEXT"
else
    echo "⚠️ No .env file found. Please create one from env.ubuntu.example"
fi

echo ""
echo "🎉 Kubernetes cluster setup complete!"
echo ""
echo "🔧 Next steps:"
echo "   1. Verify cluster: kubectl get nodes"
echo "   2. Run: ./setup-kubernetes.sh"
echo ""
echo "📋 Cluster information:"
echo "   Context: $CLUSTER_CONTEXT"
echo "   Nodes: $(kubectl get nodes --no-headers | wc -l)"








