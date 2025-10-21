# Ubuntu Quick Start Guide

Complete guide to deploy MongoDB Enterprise Advanced on Ubuntu in **3 simple steps**.

---

## 📋 What You'll Deploy

- ✅ MongoDB Enterprise Advanced (3-node replica set)
- ✅ MongoDB Search nodes (mongot) with Vector Search
- ✅ MongoDB Ops Manager
- ✅ Kubernetes Operator
- ✅ Backend API (FastAPI + AI models)
- ✅ Frontend UI (React)
- ✅ Ollama LLM for RAG

---

## 🎯 Choose Your Deployment Path

### **Option 1: Docker Compose** (Quickest - 5 minutes)
Best for: Development, Testing, Single Server

### **Option 2: Kubernetes** (Full Enterprise - 30 minutes)
Best for: Production, Demos, Multi-node

---

## 🚀 Option 1: Docker Compose (Quick & Easy)

### Prerequisites
- Ubuntu 20.04 or 22.04
- 8GB RAM minimum (16GB recommended)
- 10GB free disk space
- Sudo access

### Step 1: Install Docker
```bash
# Run the prerequisites script
chmod +x setup-ubuntu-prerequisites.sh
./setup-ubuntu-prerequisites.sh

# Log out and back in for Docker group changes
logout
# or
newgrp docker
```

### Step 2: Check Requirements
```bash
# Verify your system meets requirements
./check-requirements.sh docker
```

### Step 3: Deploy Everything
```bash
# Start all services
docker-compose up -d

# Watch the logs
docker-compose logs -f
```

### Step 4: Access Your App
- **Frontend**: http://localhost:5173
- **Backend API**: http://localhost:8000
- **MongoDB**: localhost:27017

### Done! 🎉
Upload documents, use voice search, ask questions!

---

## 🏗️ Option 2: Kubernetes (Full Enterprise)

### Prerequisites
- Ubuntu 20.04 or 22.04
- 16GB RAM minimum (32GB recommended)
- 50GB free disk space
- Sudo access

### Step 1: Install Prerequisites
```bash
# Install Docker, kubectl, Helm, minikube
chmod +x setup-ubuntu-prerequisites.sh
./setup-ubuntu-prerequisites.sh

# Log out and back in
logout
```

### Step 2: Start Kubernetes Cluster
```bash
# Log back in
ssh user@your-ubuntu-machine

# Start minikube with adequate resources
minikube start --cpus=4 --memory=8192 --disk-size=50g

# Or use kind (lighter weight)
kind create cluster --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
EOF

# Verify cluster is running
kubectl cluster-info
```

### Step 3: Check Requirements
```bash
# Verify your system meets Kubernetes requirements
./check-requirements.sh kubernetes
```

### Step 4: Configure Deployment
```bash
# Create config file (will be created automatically)
./deploy.sh
# On first run, it creates deploy.conf and exits

# Edit the configuration
nano deploy.conf
```

**Example deploy.conf:**
```json
{
  "environment": {
    "k8s_context": "minikube",
    "mongodb_namespace": "mongodb",
    "mongodb_resource_name": "mdb-rs",
    "mongodb_version": "8.2.1-ent"
  },
  "passwords": {
    "admin_password": "YourSecurePassword123",
    "user_password": "UserPassword123",
    "search_sync_password": "SearchPassword123"
  },
  "resources": {
    "mongodb_cpu_limit": "2",
    "mongodb_memory_limit": "2Gi",
    "search_cpu_limit": "3",
    "search_memory_limit": "5Gi"
  },
  "ops_manager": {
    "enabled": true,
    "project_name": "search-project"
  }
}
```

### Step 5: Deploy MongoDB Enterprise
```bash
# Deploy everything
./deploy.sh
```

**This will:**
1. ✅ Check requirements
2. ✅ Install MongoDB Kubernetes Operator
3. ✅ Deploy Ops Manager
4. ✅ Deploy MongoDB Enterprise (3 pods)
5. ✅ Create users
6. ✅ Deploy Search nodes (mongot)

**Estimated time:** 15-20 minutes

### Step 6: Verify and Setup Vector Search
```bash
# Verify deployment and create vector search index
./verify-and-setup.sh
```

### Step 7: Deploy Application (Optional)
```bash
# Create Kubernetes deployments for backend/frontend
kubectl create namespace app

# Deploy backend
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: your-registry/backend:latest
        env:
        - name: MONGODB_URL
          value: "mongodb://mdb-user:UserPassword123@mdb-rs-svc.mongodb.svc.cluster.local:27017/searchdb?replicaSet=mdb-rs"
        - name: OLLAMA_URL
          value: "http://ollama:11434"
        ports:
        - containerPort: 8000
EOF
```

### Step 8: Access Services
```bash
# Port forward MongoDB
kubectl port-forward -n mongodb svc/mdb-rs-svc 27017:27017

# Port forward Ops Manager
kubectl port-forward -n mongodb svc/ops-manager-service 8080:8080

# Access Ops Manager
# Open: http://localhost:8080
```

### Done! 🎉

---

## 📊 Resource Requirements

### Docker Compose
| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| **Minimum** | 4 cores | 8GB | 10GB |
| **Recommended** | 8 cores | 16GB | 20GB |

### Kubernetes
| Component | CPU | RAM | Disk |
|-----------|-----|-----|------|
| **Minimum** | 10 cores | 16GB | 50GB |
| **Recommended** | 16 cores | 32GB | 100GB |

---

## 🔧 Common Ubuntu Commands

### Docker Management
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# View containers
docker ps

# View logs
docker-compose logs -f [service-name]

# Stop everything
docker-compose down

# Clean up
docker system prune -a
```

### Kubernetes Management
```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# View all pods
kubectl get pods -A

# View MongoDB resources
kubectl get mdb -n mongodb
kubectl get mdbs -n mongodb

# View logs
kubectl logs -n mongodb mdb-rs-0

# Access MongoDB shell
kubectl exec -it -n mongodb mdb-rs-0 -- mongosh

# Stop minikube
minikube stop

# Delete minikube cluster
minikube delete
```

---

## 🐛 Troubleshooting

### Docker Issues

**Problem:** Docker daemon not running
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

**Problem:** Permission denied
```bash
sudo usermod -aG docker $USER
newgrp docker
# or logout and back in
```

**Problem:** Port already in use
```bash
# Find what's using the port
sudo lsof -i :27017
# Kill the process
sudo kill -9 <PID>
```

### Kubernetes Issues

**Problem:** Minikube won't start
```bash
# Delete and recreate
minikube delete
minikube start --cpus=4 --memory=8192 --disk-size=50g
```

**Problem:** Pods pending
```bash
# Check node resources
kubectl top nodes
kubectl describe pod <pod-name> -n mongodb

# Check events
kubectl get events -n mongodb --sort-by='.lastTimestamp'
```

**Problem:** Not enough resources
```bash
# Increase minikube resources
minikube stop
minikube delete
minikube start --cpus=8 --memory=16384 --disk-size=100g
```

### Out of Disk Space
```bash
# Clean Docker
docker system prune -a --volumes

# Clean apt cache
sudo apt clean
sudo apt autoclean

# Check disk usage
df -h
du -sh /var/lib/docker
```

### Slow Performance
```bash
# Use smaller models
# Edit docker-compose.yml:
OLLAMA_MODEL: phi  # Instead of llama2

# Or reduce MongoDB resources
# Edit deploy.conf - reduce memory limits
```

---

## 🌐 Cloud Deployment (AWS, GCP, Azure)

### AWS EC2 Ubuntu

**Launch Instance:**
- AMI: Ubuntu 22.04 LTS
- Instance Type: t3.xlarge (4 vCPU, 16GB RAM)
- Storage: 50GB SSD

**Setup:**
```bash
# SSH into instance
ssh -i your-key.pem ubuntu@ec2-instance-ip

# Clone repository
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem

# Run setup
./setup-ubuntu-prerequisites.sh
logout  # Log back in

# Deploy
docker-compose up -d
```

### Google Cloud VM

**Create VM:**
```bash
gcloud compute instances create mongodb-demo \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --machine-type=n2-standard-4 \
    --boot-disk-size=50GB
```

**Setup same as above**

### Azure VM

**Create VM:**
```bash
az vm create \
    --resource-group myResourceGroup \
    --name mongodb-demo \
    --image UbuntuLTS \
    --size Standard_D4s_v3 \
    --admin-username azureuser
```

**Setup same as above**

---

## 🚀 Quick Commands Summary

### First Time Setup
```bash
# 1. Install prerequisites
./setup-ubuntu-prerequisites.sh && logout

# 2. Check requirements (after logging back in)
./check-requirements.sh docker

# 3. Deploy
docker-compose up -d
```

### Kubernetes Setup
```bash
# 1. Install prerequisites
./setup-ubuntu-prerequisites.sh && logout

# 2. Start cluster (after logging back in)
minikube start --cpus=4 --memory=8192 --disk-size=50g

# 3. Check requirements
./check-requirements.sh kubernetes

# 4. Deploy
./deploy.sh

# 5. Verify
./verify-and-setup.sh
```

---

## ✅ Verification

### Check Everything is Running

**Docker:**
```bash
docker-compose ps
# All services should show "Up"
```

**Kubernetes:**
```bash
kubectl get pods -n mongodb
# All pods should show "Running"
```

### Test the Application

**Upload a document:**
- Go to http://localhost:5173
- Click "Add New Document"
- Enter title, body, tags
- Submit

**Try voice search:**
- Click microphone button
- Speak your query
- See results!

**Ask questions (RAG):**
- Go to chat section
- Type: "What are the main topics?"
- Get AI-powered answer!

---

## 📖 Next Steps

1. **Read the docs:**
   - `MONGODB_ENTERPRISE_DEMO.md` - Full demo guide
   - `RAG_SETUP_GUIDE.md` - RAG and LLM setup
   - `SYSTEM_REQUIREMENTS.md` - Detailed requirements

2. **Customize:**
   - Change LLM model (Ollama vs OpenAI)
   - Adjust resource limits
   - Add more replica set members

3. **Scale:**
   - Add more search nodes
   - Deploy to production cluster
   - Enable monitoring

---

## 🎉 Success!

You now have a fully functional MongoDB Enterprise Advanced deployment with:
- ✅ Vector Search
- ✅ RAG with LLM
- ✅ Speech-to-text
- ✅ Semantic search
- ✅ Modern web UI

**Repository:** https://github.com/darmad78/AzureMongoSearchOnPrem

**Enjoy your MongoDB Enterprise demo!** 🚀

