# MongoDB Enterprise Advanced Document Search App

A complete full-text search application built with MongoDB Enterprise Advanced 8.2.1, featuring Search & Vector Search capabilities, deployed on Kubernetes with a Python FastAPI backend and React frontend.

## 🚀 Features

- ✅ **MongoDB Enterprise Advanced 8.2.1** with replica set
- ✅ **MongoDB Search** (full-text search with relevance scoring)
- ✅ **MongoDB Vector Search** (AI/ML search capabilities)
- ✅ **MongoDB Ops Manager** (monitoring and management)
- ✅ **Python FastAPI Backend** (modern, fast API)
- ✅ **React Frontend** (clean, responsive UI)
- ✅ **Kubernetes Deployment** (scalable, production-ready)
- ✅ **Single Executable Deployment** (automated setup)

## 🎯 Quick Start

### Option 1: Docker Compose (Fastest - 5 minutes)

```bash
# Clone the repository
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem

# Check requirements
./check-requirements.sh docker

# Deploy everything
docker-compose up -d

# Access: http://localhost:5173
```

### Option 2: Kubernetes (Full Enterprise - 30 minutes)

```bash
# Clone the repository
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem

# Check requirements
./check-requirements.sh kubernetes

# Deploy MongoDB Enterprise + Search + Ops Manager
./deploy.sh

# Verify and setup vector search
./verify-and-setup.sh
```

### Option 3: Step-by-Step Deployment

```bash
# 1. Install prerequisites (Ubuntu)
./setup-ubuntu-prerequisites.sh

# 2. Set up Kubernetes cluster
./setup-kubernetes-cluster.sh

# 3. Deploy MongoDB Enterprise Advanced
./setup-kubernetes.sh
./setup-ops-manager.sh
./setup-mongodb.sh
./setup-users.sh
./setup-search.sh

# 4. Start the web application
cd backend && pip install -r requirements.txt && python main.py &
cd frontend && npm install && npm run dev
```

## 📋 Prerequisites

- **Kubernetes Cluster**: minikube, kind, Docker Desktop, or microk8s
- **kubectl**: Kubernetes command-line tool
- **Helm**: Package manager for Kubernetes
- **Docker**: Container runtime
- **Python 3.8+**: For FastAPI backend
- **Node.js 16+**: For React frontend

## 🔧 Configuration

### Environment Setup

1. **Copy configuration template**:
   ```bash
   cp deploy.conf.example deploy.conf
   ```

2. **Edit configuration**:
   ```bash
   nano deploy.conf
   ```

3. **Update passwords and settings**:
   ```json
   {
     "passwords": {
       "admin_password": "your-secure-admin-password",
       "user_password": "your-secure-user-password",
       "search_sync_password": "your-secure-search-password"
     }
   }
   ```

## 📊 Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   React Frontend │    │  FastAPI Backend │    │ MongoDB Enterprise │
│                 │    │                 │    │                 │
│  - Document Form │◄──►│  - REST API     │◄──►│  - Replica Set   │
│  - Search UI    │    │  - Text Search  │    │  - Search Engine │
│  - Results List │    │  - CRUD Ops     │    │  - Vector Search │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   Kubernetes    │
                       │                 │
                       │  - MongoDB Pods │
                       │  - Search Pods  │
                       │  - Ops Manager  │
                       └─────────────────┘
```

## 🛠️ Development

### Backend (FastAPI)

```bash
cd backend
pip install -r requirements.txt
python main.py
```

**API Endpoints:**
- `POST /documents` - Create a new document
- `GET /documents` - Get all documents
- `GET /search?q=query` - Search documents

### Frontend (React)

```bash
cd frontend
npm install
npm run dev
```

**Features:**
- Document submission form
- Full-text search interface
- Results display with relevance scoring
- Responsive design

## 📚 Documentation

- [Single Executable Deployment](README-Single-Deploy.md)
- [Ubuntu Setup Guide](README-Ubuntu.md)
- [Kubernetes Deployment](README-Kubernetes.md)

## 🔍 MongoDB Search Features

### Text Search
```javascript
// Search across title, body, and tags
{
  "$text": {
    "$search": "search terms"
  }
}
```

### Vector Search (AI/ML)
```javascript
// Semantic search with embeddings
{
  "$vectorSearch": {
    "index": "vector_index",
    "path": "embedding",
    "queryVector": [0.1, 0.2, ...],
    "numCandidates": 100
  }
}
```

## 🚀 Deployment Options

### Local Development
- Docker Compose setup
- Local MongoDB instance
- Development-friendly configuration

### Kubernetes Production
- MongoDB Enterprise Advanced
- High availability replica set
- Ops Manager monitoring
- Scalable search nodes

### Cloud Deployments

Deploy to any cloud provider running Ubuntu 22.04:

#### AWS EC2
```bash
# Launch: Ubuntu 22.04, t3.xlarge (4 vCPU, 16GB RAM), 50GB disk
# After instance is running:

ssh -i key.pem ubuntu@ec2-ip
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem
./setup-ubuntu-prerequisites.sh

# Log out and back in, then:
./check-requirements.sh docker
docker-compose up -d
```

#### Google Cloud Platform
```bash
# Create VM instance
gcloud compute instances create mongodb-demo \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --machine-type=n2-standard-4 \
  --boot-disk-size=50GB

# SSH into instance
gcloud compute ssh mongodb-demo

# Setup and deploy
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem
./setup-ubuntu-prerequisites.sh

# Log out and back in, then:
./check-requirements.sh docker
docker-compose up -d
```

#### Microsoft Azure
```bash
# Create VM instance
az vm create \
  --resource-group myResourceGroup \
  --name mongodb-demo \
  --image UbuntuLTS \
  --size Standard_D4s_v3 \
  --admin-username azureuser \
  --generate-ssh-keys

# SSH into instance
ssh azureuser@<vm-public-ip>

# Setup and deploy
git clone https://github.com/darmad78/AzureMongoSearchOnPrem.git
cd AzureMongoSearchOnPrem
./setup-ubuntu-prerequisites.sh

# Log out and back in, then:
./check-requirements.sh docker
docker-compose up -d
```

**Cloud Instance Requirements:**
- **Minimum**: 4 vCPU, 8GB RAM, 10GB disk (Docker Compose)
- **Recommended**: 4 vCPU, 16GB RAM, 50GB disk (Docker Compose)
- **Kubernetes**: 10+ vCPU, 16GB RAM, 50GB disk

**See [UBUNTU_QUICKSTART.md](UBUNTU_QUICKSTART.md) for complete Ubuntu deployment guide.**

## 📊 Monitoring

### Ops Manager
```bash
kubectl port-forward -n mongodb service/ops-manager-service 8080:8080
# Open: http://localhost:8080
```

### Kubernetes Dashboard
```bash
kubectl get pods -n mongodb
kubectl get mdb -n mongodb
kubectl get mdbs -n mongodb
```

## 🔧 Troubleshooting

### Check Deployment Status
```bash
kubectl get pods -n mongodb
kubectl logs -n mongodb deployment/mongodb-kubernetes-operator
```

### Verify MongoDB Connection
```bash
kubectl port-forward -n mongodb service/mdb-rs-svc 27017:27017
mongosh "mongodb://mdb-user:<password>@localhost:27017/searchdb?replicaSet=mdb-rs"
```

### Check Search Functionality
```bash
kubectl logs -n mongodb mdb-rs-search-0
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [MongoDB Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes)
- [MongoDB Enterprise Advanced](https://www.mongodb.com/products/enterprise-advanced)
- [FastAPI](https://fastapi.tiangolo.com/)
- [React](https://reactjs.org/)

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/darmad78/AzureMongoSearchOnPrem/issues)
- **Discussions**: [GitHub Discussions](https://github.com/darmad78/AzureMongoSearchOnPrem/discussions)
- **Documentation**: [MongoDB Docs](https://www.mongodb.com/docs/)
- **Ubuntu Guide**: [UBUNTU_QUICKSTART.md](UBUNTU_QUICKSTART.md)
- **System Requirements**: [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md)

---

**Ready to deploy?** Run `./deploy.sh` and you'll have a full MongoDB Enterprise Advanced search application running in minutes!