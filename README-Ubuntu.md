# MongoDB Enterprise Advanced Setup - Ubuntu Guide

This guide provides Ubuntu-specific setup instructions for MongoDB Enterprise Advanced with Kubernetes.

## Ubuntu Prerequisites

### 1. Install Required Tools
```bash
# Make script executable and run
chmod +x setup-ubuntu-prerequisites.sh
./setup-ubuntu-prerequisites.sh
```

This script installs:
- Docker CE
- kubectl
- Helm
- minikube
- kind

### 2. Start Kubernetes Cluster
```bash
# Choose your preferred Kubernetes setup
chmod +x setup-kubernetes-cluster.sh
./setup-kubernetes-cluster.sh
```

**Options:**
- **minikube** (recommended for development)
- **kind** (lightweight, good for CI/CD)
- **microk8s** (snap-based, easy setup)

## Ubuntu-Specific Setup Steps

### 1. Environment Configuration
```bash
# Copy Ubuntu-specific environment file
cp env.ubuntu.example .env

# Edit with your preferences
nano .env
```

### 2. Install MongoDB Kubernetes Operator
```bash
./setup-kubernetes.sh
```

### 3. Deploy Ops Manager
```bash
./setup-ops-manager.sh
```

### 4. Deploy MongoDB Enterprise
```bash
./setup-mongodb.sh
```

### 5. Create Users
```bash
./setup-users.sh
```

### 6. Deploy MongoDB Search
```bash
./setup-search.sh
```

## Ubuntu-Specific Notes

### Docker Configuration
```bash
# Add user to docker group (if not done by script)
sudo usermod -aG docker $USER
newgrp docker

# Verify Docker is running
docker info
```

### Kubernetes Cluster Options

#### minikube (Recommended)
```bash
# Start with more resources
minikube start --driver=docker --memory=8192 --cpus=4

# Enable addons
minikube addons enable metrics-server
minikube addons enable ingress

# Access dashboard
minikube dashboard
```

#### kind (Lightweight)
```bash
# Create cluster with port mappings
kind create cluster --name mongodb-cluster

# Verify
kubectl cluster-info --context kind-mongodb-cluster
```

#### microk8s (Snap-based)
```bash
# Install
sudo snap install microk8s --classic

# Enable addons
sudo microk8s enable dns storage ingress

# Use microk8s kubectl
microk8s kubectl get nodes
```

## Ubuntu Troubleshooting

### Docker Issues
```bash
# Restart Docker service
sudo systemctl restart docker

# Check Docker status
sudo systemctl status docker

# Check Docker group membership
groups $USER
```

### Kubernetes Issues
```bash
# Check cluster status
kubectl cluster-info

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods --all-namespaces
```

### Resource Requirements
- **Minimum**: 8GB RAM, 4 CPU cores
- **Recommended**: 16GB RAM, 8 CPU cores
- **Storage**: 50GB free space

### Network Configuration
```bash
# Check if ports are available
sudo netstat -tlnp | grep :8080
sudo netstat -tlnp | grep :27017

# Configure firewall (if needed)
sudo ufw allow 8080
sudo ufw allow 27017
```

## Ubuntu Performance Optimization

### System Settings
```bash
# Increase file descriptor limits
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Optimize kernel parameters
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Docker Optimization
```bash
# Configure Docker daemon
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
```

## Verification Commands

```bash
# Check all components
kubectl get pods -n mongodb
kubectl get mdb -n mongodb
kubectl get mdbs -n mongodb

# Test MongoDB connection
kubectl port-forward -n mongodb service/mdb-rs-svc 27017:27017 &
mongosh "mongodb://mdb-user:<password>@localhost:27017/searchdb?replicaSet=mdb-rs"

# Test Ops Manager
kubectl port-forward -n mongodb service/ops-manager-service 8080:8080 &
# Open: http://localhost:8080
```

## Ubuntu-Specific Resources

- [Docker CE for Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [kubectl for Ubuntu](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)
- [Helm for Ubuntu](https://helm.sh/docs/intro/install/)
- [minikube for Ubuntu](https://minikube.sigs.k8s.io/docs/start/)
- [kind for Ubuntu](https://kind.sigs.k8s.io/docs/user/quick-start/)

