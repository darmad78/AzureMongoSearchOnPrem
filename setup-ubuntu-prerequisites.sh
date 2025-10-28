#!/bin/bash

# Ubuntu Prerequisites Setup for MongoDB Enterprise Advanced
# Installs required tools for Kubernetes and MongoDB deployment

set -e

echo "🐧 Setting up Ubuntu prerequisites for MongoDB Enterprise Advanced..."

# Update package list
echo "📦 Updating package list..."
sudo apt update

# Install required packages
echo "📦 Installing required packages..."
sudo apt install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    software-properties-common \
    unzip

# Install Docker
echo "🐳 Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker $USER
    echo "✅ Docker installed. Please log out and back in for group changes to take effect."
else
    echo "✅ Docker already installed"
fi

# Install kubectl
echo "☸️ Installing kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    echo "✅ kubectl installed"
else
    echo "✅ kubectl already installed"
fi

# Install Helm
echo "⚙️ Installing Helm..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ Helm installed"
else
    echo "✅ Helm already installed"
fi

# Install minikube (recommended for Ubuntu)
echo "🏗️ Installing minikube..."
if ! command -v minikube &> /dev/null; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    echo "✅ minikube installed"
else
    echo "✅ minikube already installed"
fi

# Install kind (alternative to minikube)
echo "🏗️ Installing kind..."
if ! command -v kind &> /dev/null; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo "✅ kind installed"
else
    echo "✅ kind already installed"
fi

echo ""
echo "🎉 Prerequisites installation complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Log out and back in (for Docker group changes)"
echo "   2. Start a Kubernetes cluster:"
echo "      - minikube: minikube start"
echo "      - kind: kind create cluster"
echo "   3. Copy environment file: cp env.ubuntu.example .env"
echo "   4. Run setup scripts: ./setup-kubernetes.sh"
echo ""
echo "🔧 Available Kubernetes options:"
echo "   - minikube (recommended for development)"
echo "   - kind (lightweight, good for CI/CD)"
echo "   - microk8s (snap-based, easy setup)"



