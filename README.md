# RAG On-Premises with MongoDB Enterprise

A complete **Retrieval-Augmented Generation (RAG)** application that enables semantic document search and AI-powered question answering using your own documents, all running **on-premises** with MongoDB Enterprise Advanced.

## 🎯 The Problem This Solves

Organizations in **airgapped, secure, or regulated environments** (defense, finance, healthcare) need:

- **Semantic Search**: Find documents by meaning, not just keywords ("budget discussions" finds "financial planning meetings")
- **RAG Chat**: Ask questions and get answers based on your actual documents
- **Audio Transcription**: Convert voice recordings to searchable documents
- **On-Premises Deployment**: No cloud dependencies, complete data sovereignty
- **Enterprise-Grade**: High availability, monitoring, and production-ready infrastructure

Traditional keyword search fails when users ask questions like:
- "What did we discuss about budget in the last meeting?" (semantic understanding needed)
- "Find documents about security vulnerabilities" (concept matching, not exact words)
- "Summarize the key points from the quarterly report" (requires AI understanding)

This application solves these challenges by combining **MongoDB Enterprise Vector Search** with **local LLM inference** (Ollama) for a complete on-premises RAG solution.

## 🚀 What This Application Does

### Core Capabilities

1. **Document Management**
   - Upload text documents with title, body, and tags
   - Upload audio files (MP3, WAV, etc.) - automatically transcribed to text using Whisper AI
   - Store documents in MongoDB Enterprise with automatic embedding generation

2. **Dual Search Modes**
   - **Full-Text Search**: Traditional keyword search using MongoDB `$search` aggregation
   - **Semantic/Vector Search**: Find documents by meaning using MongoDB `$vectorSearch` aggregation
   - Both searches return relevance scores and execution details

3. **RAG Chat Interface**
   - Ask questions in natural language
   - System finds relevant documents using semantic search
   - Local LLM (Ollama) generates answers based on your documents
   - Shows source documents used for the answer
   - Customizable system prompts

4. **Audio Transcription**
   - Upload audio files (meetings, interviews, voice notes)
   - Automatic transcription using Whisper AI
   - Transcribed text becomes searchable documents
   - Supports multiple languages

5. **Enterprise Features**
   - MongoDB Enterprise Advanced with 3-node replica set (high availability)
   - MongoDB Ops Manager for monitoring and management
   - Dedicated search nodes (mongot) for vector search
   - Kubernetes deployment for scalability
   - Complete on-premises operation

### Technology Stack

- **Backend**: Python FastAPI with Whisper AI, Sentence Transformers, Ollama
- **Frontend**: React with modern UI and collapsible sections
- **Database**: MongoDB Enterprise Advanced 8.2.1 with Vector Search
- **Search**: MongoDB Search (mongot) for native `$vectorSearch` aggregation
- **LLM**: Ollama (local, free) for on-premises LLM inference
- **Deployment**: Kubernetes with phase-based deployment scripts

## 📋 System Requirements

### Hardware Requirements

| Component | CPU | RAM | Disk | Notes |
|-----------|-----|-----|------|-------|
| **MongoDB Enterprise** (3-node replica set) | 3 cores | 3GB | 30GB | High availability |
| **MongoDB Search** (mongot) | 2 cores | 3GB | 5GB | Vector search nodes |
| **Ops Manager** | 1 core | 2GB | 10GB | Monitoring & management |
| **Backend** (FastAPI + AI models) | 2 cores | 4GB | 5GB | Whisper + embeddings |
| **Frontend** (React) | 0.5 core | 512MB | 1GB | Web interface |
| **Ollama** (LLM) | 1-4 cores | 4-8GB | 10GB | Depends on model size |
| **Kubernetes Overhead** | 2-3 cores | 2GB | - | Control plane |
| **TOTAL MINIMUM** | **10+ cores** | **16GB** | **60GB** | |
| **RECOMMENDED** | **16 cores** | **32GB** | **100GB** | For production workloads |

### Software Prerequisites

**Required:**
- **Kubernetes Cluster**: minikube, kind, Docker Desktop K8s, or cloud K8s (GKE, EKS, AKS)
- **kubectl**: Kubernetes command-line tool (v1.24+)
- **Helm**: Package manager for Kubernetes (v3.10+)
- **Docker**: Container runtime (20.10+) - for building images
- **Bash**: Shell for running deployment scripts

**Operating System:**
- **Linux**: Ubuntu 22.04 LTS (recommended) or RHEL 8+
- **macOS**: For local development (deployment targets Linux)
- **Windows**: WSL2 for local development

**MongoDB Enterprise Binary:**
- Place MongoDB Enterprise binary in `backend/opsmanagerfiles/`
- Example: `mongodb-linux-x86_64-enterprise-rhel8-8.2.1.tgz`
- Required for Phase 2 deployment

## 🚀 Deployment - Phase-Based Approach

The deployment is split into **5 phases** that must be run in sequence. Each phase builds on the previous one.

### Prerequisites Check

```bash
# Clone the repository
git clone https://github.com/darmad78/RAGOnPremMongoDB.git
cd RAGOnPremMongoDB

# Check system requirements
./check-requirements.sh kubernetes
```

### Phase 1: Deploy Ops Manager

**What it does:**
- Sets up Kubernetes cluster (minikube if needed)
- Installs MongoDB Kubernetes Operator
- Deploys MongoDB Application Database in Kubernetes
- Installs Ops Manager on the VM
- Configures Ops Manager to use Kubernetes MongoDB

**Run:**
```bash
./deploy-phase1-ops-manager.sh
```

**What you'll get:**
- Ops Manager URL: `http://<VM_IP>:9000` (or `:80` if nginx proxy is set up)
- MongoDB Application Database accessible at `<NODE_IP>:<NODE_PORT>`

**Information to collect:**
1. Open Ops Manager in browser at the URL shown
2. Create organization (note the **Organization ID** from URL: `/v2/org/YOUR_ORG_ID/`)
3. Create project (note the **Project ID** from URL: `/project/YOUR_PROJECT_ID/`)
4. Go to **Project Settings → Access Manager → API Keys**
5. Generate new API Key with **Project Owner** role
6. Copy **Public API Key** and **Private API Key**
7. Add your VM IP to **IP Access List** (Organization Settings → Access Manager → IP Access List)

**Save these credentials for Phase 2:**
- Organization ID
- Project ID
- Public API Key
- Private API Key

### Phase 2: Deploy MongoDB Enterprise

**What it does:**
- Installs MongoDB Kubernetes Operator (unified)
- Creates Ops Manager configuration
- Deploys 3-node MongoDB Enterprise replica set
- Creates MongoDB users (admin, application, search sync)
- Configures MongoDB server parameters

**Prerequisites:**
- Phase 1 completed
- Ops Manager credentials from Phase 1
- MongoDB Enterprise binary in `backend/opsmanagerfiles/` (e.g., `mongodb-linux-x86_64-enterprise-rhel8-8.2.1.tgz`)

**Run:**
```bash
./deploy-phase2-mongodb-enterprise.sh
```

**Input required:**
- Organization ID (from Phase 1)
- Project ID (from Phase 1)
- Public API Key (from Phase 1)
- Private API Key (from Phase 1)

**What you'll get:**
- MongoDB Enterprise 3-node replica set running
- Users created: `mdb-admin`, `mdb-user`, `search-sync-source`
- MongoDB accessible at: `mongodb://mdb-user:<password>@<service>:27017/searchdb?replicaSet=mdb-rs`

**Information to note:**
- MongoDB service name: `mdb-rs-svc.mongodb.svc.cluster.local`
- Replica set name: `mdb-rs`
- User passwords: Check secrets or use defaults (change them!)

### Phase 3: Deploy MongoDB Search

**What it does:**
- Verifies MongoDB Enterprise is ready
- Creates search sync user
- Deploys MongoDB Search (mongot) nodes via MongoDBSearch Custom Resource
- Enables native `$vectorSearch` aggregation pipeline

**Prerequisites:**
- Phase 2 completed
- MongoDB Enterprise in "Running" phase

**Run:**
```bash
./deploy-phase3-mongodb-search.sh
```

**What you'll get:**
- MongoDB Search (mongot) nodes running
- Vector search enabled via `$vectorSearch` aggregation
- Ready for semantic search operations

**Information to verify:**
```bash
# Check search nodes
kubectl get pods -n mongodb | grep search

# Check search resource status
kubectl get mdbs -n mongodb
```

### Phase 4: Deploy AI Models

**What it does:**
- Deploys Ollama service to Kubernetes
- Pulls LLM model (default: `phi`, configurable)
- Creates ConfigMap with model configuration
- Tests Ollama API

**Prerequisites:**
- Phase 3 completed
- Sufficient memory for LLM model (4-8GB depending on model)

**Run:**
```bash
# Default model (phi - smaller, faster)
./deploy-phase4-ai-models.sh

# Or use a different model
export OLLAMA_MODEL=mistral
./deploy-phase4-ai-models.sh
```

**Configuration options:**
- `OLLAMA_MODEL`: LLM model name (default: `phi`)
  - `phi`: 1.6GB, fastest, lower quality
  - `llama2`: 3.8GB, good balance
  - `mistral`: 4.1GB, better quality
  - `llama3`: 4.7GB, latest
- `EMBEDDING_MODEL`: Embedding model (default: `all-MiniLM-L6-v2`)
- `WHISPER_MODEL`: Speech-to-text model (default: `base`)

**What you'll get:**
- Ollama service running at: `http://ollama-svc.mongodb.svc.cluster.local:11434`
- LLM model loaded and ready
- ConfigMap with model configuration

**Information to note:**
- Ollama service URL (for backend configuration)
- Model name being used
- Available models: `kubectl exec <ollama-pod> -n mongodb -- ollama list`

### Phase 5: Deploy Backend & Frontend

**What it does:**
- Builds backend Docker image (FastAPI + AI models)
- Builds frontend Docker image (React)
- Loads images to Kubernetes (minikube)
- Retrieves MongoDB and Ollama connection details
- Creates MongoDB text indexes
- Deploys backend and frontend applications
- Sets up persistent port forwarding (systemd service)

**Prerequisites:**
- Phase 1-4 completed
- Docker installed and running
- Backend and frontend source code in `./backend` and `./frontend`

**Run:**
```bash
./deploy-phase5-backend-frontend.sh
```

**What you'll get:**
- Backend service accessible at: `http://<VM_IP>:30888`
- Frontend service accessible at: `http://<VM_IP>:30173`
- Systemd service for automatic port forwarding
- Complete RAG application ready to use

## 📊 What Information You Should Get After Deployment

### Access URLs

After completing all 5 phases, you should have:

1. **Frontend Application**: `http://<VM_IP>:30173`
   - Document upload interface
   - Search interface (text and semantic)
   - RAG chat interface
   - Audio upload and transcription
   - System health monitoring

2. **Backend API**: `http://<VM_IP>:30888`
   - REST API endpoints
   - Health check: `http://<VM_IP>:30888/health/system`

3. **Ops Manager**: `http://<VM_IP>:9000` (or `:80`)
   - MongoDB monitoring and management
   - Deployment configuration
   - Backup management

### Credentials

**MongoDB Users:**
- Admin user: `mdb-admin` (password in secret `mdb-admin-user-password`)
- Application user: `mdb-user` (password in secret `mdb-user-password`)
- Search sync user: `search-sync-source` (password in secret `mdb-rs-search-sync-source-password`)

**To retrieve passwords:**
```bash
# Get MongoDB user password
kubectl get secret mdb-user-password -n mongodb -o jsonpath='{.data.password}' | base64 -d

# Get admin password
kubectl get secret mdb-admin-user-password -n mongodb -o jsonpath='{.data.password}' | base64 -d
```

**MongoDB Connection String:**
```bash
# Get connection details
kubectl get svc mdb-rs-svc -n mongodb
# Connection: mongodb://mdb-user:<password>@mdb-rs-svc.mongodb.svc.cluster.local:27017/searchdb?replicaSet=mdb-rs&authSource=admin
```

### Verification Commands

**Check all pods:**
```bash
kubectl get pods -n mongodb
```

**Check MongoDB status:**
```bash
kubectl get mdb -n mongodb
kubectl get mdbs -n mongodb
```

**Check services:**
```bash
kubectl get svc -n mongodb
```

**View logs:**
```bash
# Backend logs
kubectl logs -n mongodb -l app=search-backend -f

# Frontend logs
kubectl logs -n mongodb -l app=search-frontend -f

# MongoDB logs
kubectl logs -n mongodb mdb-rs-0 -f
```

## 🎯 Using the Application

### 1. Upload Documents

- **Text Documents**: Enter title, body text, and tags
- **Audio Files**: Upload MP3/WAV files - automatically transcribed
- Documents are stored with automatic embedding generation for semantic search

### 2. Search Documents

- **Text Search**: Traditional keyword search
- **Semantic Search**: Find documents by meaning (e.g., "budget discussions" finds "financial planning meetings")
- Both show relevance scores and MongoDB query details

### 3. RAG Chat

- Ask questions in natural language
- System finds relevant documents using semantic search
- LLM generates answers based on your documents
- View source documents used for the answer

### 4. Monitor System Health

- Check MongoDB connection status
- Verify Ollama LLM availability
- View document counts and storage
- Monitor vector index status

## 🔧 Troubleshooting

### MongoDB Not Ready

```bash
# Check MongoDB resource status
kubectl describe mdb mdb-rs -n mongodb

# Check pod logs
kubectl logs -n mongodb mdb-rs-0 -f
```

### Search Not Working

```bash
# Verify search nodes are running
kubectl get pods -n mongodb | grep search

# Check search resource
kubectl describe mdbs mdb-rs -n mongodb
```

### Backend/Frontend Not Accessible

```bash
# Check if services are running
kubectl get pods -n mongodb -l app=search-backend
kubectl get pods -n mongodb -l app=search-frontend

# Check port forwarding service
sudo systemctl status k8s-port-forward.service
```

### Ollama Not Responding

```bash
# Check Ollama pod
kubectl get pods -n mongodb -l app=ollama

# Test Ollama API
kubectl exec <ollama-pod> -n mongodb -- curl http://localhost:11434/api/tags
```

## 📚 Additional Documentation

- [System Requirements](SYSTEM_REQUIREMENTS.md) - Detailed hardware and software requirements
- [RAG Setup Guide](RAG_SETUP_GUIDE.md) - How to use RAG features
- [MongoDB Enterprise Demo](MONGODB_ENTERPRISE_DEMO.md) - MongoDB-specific features
- [Ubuntu Quickstart](UBUNTU_QUICKSTART.md) - Ubuntu-specific deployment guide

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
- [Ollama](https://ollama.com/)

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/darmad78/RAGOnPremMongoDB/issues)
- **Discussions**: [GitHub Discussions](https://github.com/darmad78/RAGOnPremMongoDB/discussions)

---

**Ready to deploy?** Start with Phase 1: `./deploy-phase1-ops-manager.sh`
