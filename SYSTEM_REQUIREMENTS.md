# System Requirements for MongoDB Enterprise Demo

## 📊 Minimum Requirements Assessment

### Hardware Requirements

#### **Docker Compose Deployment (Local Dev)**

| Component | CPU | RAM | Disk | Notes |
|-----------|-----|-----|------|-------|
| MongoDB Enterprise | 1 core | 1GB | 2GB | Database + replica set |
| Ollama (llama2) | 2 cores | 4GB | 4GB | LLM model in memory |
| Backend (Whisper + Embeddings) | 2 cores | 3GB | 1GB | AI models |
| Frontend | 0.5 core | 200MB | 500MB | React app |
| **TOTAL MINIMUM** | **4 cores** | **8GB** | **8GB** | |
| **RECOMMENDED** | **8 cores** | **16GB** | **20GB** | For smooth operation |

#### **Kubernetes Deployment (Production)**

| Component | CPU | RAM | Disk | Replicas |
|-----------|-----|-----|------|----------|
| MongoDB Enterprise (per pod) | 1 core | 1GB | 10GB | 3 pods |
| MongoDB Search (mongot) | 2 cores | 3GB | 5GB | 1 pod |
| Ops Manager | 1 core | 2GB | 10GB | 1 pod |
| Kubernetes Operator | 0.5 core | 200MB | - | 1 pod |
| **TOTAL MINIMUM** | **10 cores** | **15GB** | **45GB** | |
| **RECOMMENDED** | **16 cores** | **32GB** | **100GB** | For production |

### Software Requirements

#### **Required Software**

| Software | Minimum Version | Purpose |
|----------|----------------|---------|
| **Docker** | 20.10+ | Container runtime |
| **Docker Compose** | 2.0+ | Multi-container orchestration |
| **kubectl** | 1.24+ | Kubernetes management (K8s only) |
| **helm** | 3.10+ | Package manager (K8s only) |
| **Bash** | 5.0+ | Deployment scripts |
| **curl** | 7.0+ | Health checks |

#### **Optional Software**

| Software | Purpose |
|----------|---------|
| **mongosh** | MongoDB shell access |
| **jq** | JSON processing in scripts |

### Network Requirements

| Port | Service | Required For |
|------|---------|--------------|
| 27017 | MongoDB | Database access |
| 8000 | Backend API | Application |
| 5173 | Frontend | Web UI |
| 11434 | Ollama | LLM inference |
| 8080 | Ops Manager | Monitoring (K8s) |

### Storage Requirements

#### **Docker Volumes**

| Volume | Size | Content |
|--------|------|---------|
| mongodb_data | 5GB+ | Database files |
| ollama_data | 4GB+ | LLM models |
| whisper_models | 650MB+ | Speech-to-text models |
| sentence_transformers_models | 200MB+ | Embedding models |
| **TOTAL** | **~10GB** | |

#### **Kubernetes Persistent Volumes**

| PVC | Size | Access Mode |
|-----|------|-------------|
| MongoDB data (per pod) | 10GB+ | ReadWriteOnce |
| Ops Manager | 10GB | ReadWriteOnce |
| **TOTAL** | **40GB+** | |

### Internet Bandwidth

| Operation | Size | Frequency |
|-----------|------|-----------|
| Initial model download | ~5GB | First time only |
| Docker image pulls | ~2GB | First time only |
| MongoDB Enterprise images | ~1GB | First time only |
| **TOTAL FIRST RUN** | **~8GB** | |

### Operating System Support

| OS | Docker Compose | Kubernetes |
|----|----------------|------------|
| **macOS** (Intel) | ✅ Supported | ✅ Supported |
| **macOS** (Apple Silicon) | ✅ Supported* | ✅ Supported* |
| **Ubuntu 20.04+** | ✅ Supported | ✅ Supported |
| **RHEL 8+** | ✅ Supported | ✅ Supported |
| **Windows 10/11** | ✅ WSL2 Required | ✅ WSL2 Required |

*Note: Apple Silicon requires Rosetta 2 for some components

### Performance Expectations

#### **Response Times (Recommended Hardware)**

| Operation | Expected Time | Notes |
|-----------|--------------|-------|
| First startup | 5-10 minutes | Downloading models |
| Subsequent startup | 30-60 seconds | Models cached |
| Speech-to-text (30s audio) | 2-5 seconds | Whisper base model |
| Semantic search (1k docs) | <100ms | MongoDB vector search |
| Semantic search (10k docs) | <200ms | Python fallback |
| RAG query (with Ollama) | 3-10 seconds | Depends on query |

#### **Minimum Hardware Impact**

With **minimum** hardware (4 cores, 8GB RAM):
- ⚠️ Slower startup (10-15 min)
- ⚠️ Speech-to-text: 5-10 seconds
- ⚠️ RAG queries: 10-20 seconds
- ⚠️ May experience slowdowns with multiple operations

### Kubernetes Cluster Requirements

#### **Minimum Cluster Specs**

```yaml
Cluster:
  Nodes: 1 (demo) or 3+ (production)
  Node Resources (each):
    CPU: 4 cores
    RAM: 8GB
    Disk: 50GB
  Total Cluster:
    CPU: 12+ cores
    RAM: 24GB
    Disk: 150GB
```

#### **Required Kubernetes Features**

- ✅ PersistentVolume support
- ✅ LoadBalancer or NodePort services
- ✅ RBAC enabled
- ✅ StorageClass configured

### Development vs Production

#### **Development/Demo Setup**

```yaml
CPU: 4-8 cores
RAM: 8-16GB
Disk: 10-20GB
Network: Standard broadband
Use Case: Single user, demos, development
```

#### **Production Setup**

```yaml
CPU: 16+ cores
RAM: 32+ GB
Disk: 100+ GB SSD
Network: Low-latency, high-bandwidth
Use Case: Multiple users, production workloads
```

### Resource Allocation Summary

#### **Docker Compose (docker-compose.yml)**

```yaml
MongoDB Enterprise:
  CPU: 2 cores (limit)
  RAM: 2GB (limit)
  
Ollama:
  CPU: No limit (uses available)
  RAM: 4-6GB (model dependent)
  
Backend:
  CPU: 2 cores
  RAM: 3GB
  
Frontend:
  CPU: 0.5 cores
  RAM: 200MB
```

#### **Kubernetes (deploy.sh)**

```yaml
MongoDB (per pod):
  CPU: 1 core (request), 2 cores (limit)
  RAM: 1GB (request), 2GB (limit)
  
Search Nodes:
  CPU: 2 cores (request), 3 cores (limit)
  RAM: 3GB (request), 5GB (limit)
  
Ops Manager:
  CPU: 1 core (request), 2 cores (limit)
  RAM: 2GB (request), 4GB (limit)
```

### Scaling Considerations

#### **Can Handle**

- Documents: Up to 100,000 (Docker), 1M+ (Kubernetes)
- Concurrent users: 1-5 (Docker), 10-100+ (Kubernetes)
- Search queries: 10/sec (Docker), 100+/sec (Kubernetes)

#### **Bottlenecks**

1. **Memory**: Ollama models, MongoDB working set
2. **CPU**: Whisper transcription, embedding generation
3. **Disk I/O**: MongoDB writes, model loading

### Pre-flight Checklist

Before deploying, ensure:

- [ ] CPU cores meet minimum (4 for Docker, 10 for K8s)
- [ ] RAM available (8GB for Docker, 16GB for K8s)
- [ ] Disk space free (10GB for Docker, 50GB for K8s)
- [ ] Docker/Kubernetes running
- [ ] Internet connection for downloads
- [ ] Ports not in use (27017, 8000, 5173, 11434)
- [ ] User has admin/sudo privileges (if needed)

### Troubleshooting Low Resources

#### **If RAM is limited (<8GB)**

```yaml
# Use smaller models in docker-compose.yml:
OLLAMA_MODEL: phi  # 1.6GB instead of 3.8GB

# Or disable Ollama, use OpenAI:
LLM_PROVIDER: openai
OPENAI_API_KEY: your-key
```

#### **If Disk is limited (<10GB)**

- Don't download all Whisper models (use `tiny`)
- Use external MongoDB (MongoDB Atlas)
- Clean Docker: `docker system prune -a`

#### **If CPU is limited (<4 cores)**

- ⚠️ Demo will be very slow
- Use cloud deployment instead
- Reduce concurrent operations

### Cloud Provider Recommendations

#### **AWS**

```
Docker: t3.xlarge (4 vCPU, 16GB RAM) - $0.1664/hr
Kubernetes: 3x t3.large (2 vCPU, 8GB each) - ~$0.25/hr
```

#### **Google Cloud**

```
Docker: n2-standard-4 (4 vCPU, 16GB RAM) - ~$0.19/hr
Kubernetes: 3x n2-standard-2 (2 vCPU, 8GB each) - ~$0.28/hr
```

#### **Azure**

```
Docker: Standard_D4s_v3 (4 vCPU, 16GB RAM) - ~$0.19/hr
Kubernetes: 3x Standard_D2s_v3 (2 vCPU, 8GB each) - ~$0.29/hr
```

### Cost Estimate

#### **One-time Setup**

- Software: $0 (all open source)
- Internet bandwidth: ~8GB download

#### **Running Costs**

**Local (own hardware):**
- Electricity: ~$0.10-0.50/day
- No cloud costs

**Cloud (AWS example):**
- Docker: ~$120/month (t3.xlarge 24/7)
- Kubernetes: ~$180/month (3x t3.large 24/7)
- Storage: ~$5-10/month

**Recommended: Run locally for demos, cloud for production**

---

## ✅ Quick Requirements Check

Run this command to check your system:

```bash
./check-requirements.sh
```

This will verify:
- ✅ CPU cores available
- ✅ RAM available
- ✅ Disk space free
- ✅ Required software installed
- ✅ Ports available
- ✅ Internet connectivity

