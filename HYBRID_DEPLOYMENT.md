# Hybrid Docker Compose + Kubernetes Deployment for Native Vector Search

This guide explains how to deploy MongoDB Enterprise with **native `$vectorSearch`** using a hybrid architecture:

- **Docker Compose** (4 CPUs): MongoDB, Backend, Frontend, Ollama
- **Kubernetes** (2-3 CPUs): mongot search pods only

This approach enables native MongoDB Vector Search on modest hardware!

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│  Docker Compose (Main Application)                  │
│  ─────────────────────────────────────              │
│  ├─ MongoDB Enterprise (no mongot)                  │
│  │  └─ Configured with searchIndexManagementHost   │
│  │                                                   │
│  ├─ Backend (FastAPI)                               │
│  │  └─ Whisper AI, SentenceTransformers            │
│  │                                                   │
│  ├─ Frontend (React + Vite)                         │
│  │  └─ Audio upload, Search, RAG Chat              │
│  │                                                   │
│  └─ Ollama                                          │
│     └─ Local LLM (llama2)                           │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ mongotHost parameter
                   │ Points to K8s LoadBalancer
                   ▼
┌─────────────────────────────────────────────────────┐
│  Kubernetes (Search Only)                           │
│  ────────────────────────                          │
│  └─ mongot Pods (MongoDBSearch CR)                 │
│     ├─ Connects to external MongoDB                │
│     ├─ Provides $vectorSearch capability           │
│     └─ Exposed via LoadBalancer                    │
└─────────────────────────────────────────────────────┘
```

---

## 📋 Prerequisites

### Local Machine:
- Docker & Docker Compose
- Kubernetes cluster (Minikube, kind, Docker Desktop, or cloud)
- kubectl configured
- Helm 3+
- 6-7 CPUs total (4 for Docker, 2-3 for K8s)
- 8GB RAM

### Knowledge:
- Basic Docker Compose
- Basic Kubernetes commands
- MongoDB basics

---

## 🚀 Deployment Steps

### Step 1: Deploy Docker Compose Stack

Start the main application stack:

```bash
cd ~/RAGOnPremMongoDB

# Start all services
docker compose up -d

# Verify services are running
docker compose ps
```

This deploys:
- ✅ MongoDB Enterprise (port 27017)
- ✅ Backend API (port 8000)
- ✅ Frontend (port 5173)
- ✅ Ollama (port 11434)

**At this point, the app works with Python fallback search.**

---

### Step 2: Deploy mongot to Kubernetes

Set your search sync password:

```bash
export SEARCH_SYNC_PASSWORD="your-secure-password-here"
```

Run the lightweight K8s deployment:

```bash
./deploy-search-only.sh
```

This script will:
1. Install MongoDB Kubernetes Operator
2. Extract MongoDB keyfile from Docker
3. Create search user secrets
4. Deploy mongot pods (MongoDBSearch CR)
5. Create LoadBalancer for external access
6. Display the external IP

**Note the external IP provided at the end!**

---

### Step 3: Create Search Sync User in MongoDB

The mongot pods need a user in MongoDB to sync data.

Option A: Use the helper script:

```bash
export SEARCH_SYNC_PASSWORD="your-secure-password-here"
./scripts/create-search-user.sh
```

Option B: Manually create the user:

```bash
docker exec -it mongodb-enterprise mongosh -u admin -p password123 --authenticationDatabase admin

# In mongosh:
use admin

db.createUser({
  user: "search-sync-source",
  pwd: "your-secure-password-here",
  roles: [
    { role: "searchCoordinator", db: "admin" }
  ]
})
```

---

### Step 4: Configure MongoDB to Use mongot

Create `docker-compose.override.yml` with the mongot external IP:

```yaml
services:
  mongodb:
    environment:
      MONGOT_HOST: "YOUR_K8S_LOADBALANCER_IP:27027"  # Replace with actual IP
```

Restart MongoDB:

```bash
docker compose restart mongodb
```

**MongoDB will now use native $vectorSearch!**

---

### Step 5: Verify Native Vector Search

Check the backend logs:

```bash
docker compose logs -f backend
```

Upload an audio file or add documents, then perform a semantic search.

**You should see:**
- ✅ No "SearchNotEnabled" warnings
- ✅ Semantic search using `$vectorSearch`

If you see warnings, mongot connection isn't working. Check:

```bash
# Verify mongot is running
kubectl get pods -n mongodb -l app=mdbs-search-svc

# Check mongot logs
kubectl logs -n mongodb -l app=mdbs-search-svc

# Verify LoadBalancer IP
kubectl get service mdbs-external -n mongodb
```

---

## 🔍 Creating Vector Search Indexes

Once connected, create a vector search index:

### Option 1: Via Backend API

```bash
curl -X POST http://localhost:8000/search/create-vector-index
```

### Option 2: Via mongosh

```bash
docker exec -it mongodb-enterprise mongosh -u admin -p password123 --authenticationDatabase admin

use searchdb

db.documents.createSearchIndex({
  name: "vector_index",
  type: "vectorSearch",
  definition: {
    fields: [{
      type: "vector",
      path: "embedding",
      numDimensions: 384,
      similarity: "cosine"
    }]
  }
})
```

Verify the index:

```javascript
db.documents.listSearchIndexes()
```

---

## 📊 Resource Usage

### Docker Compose (4 CPUs):
- MongoDB: 2 CPUs, 2GB RAM
- Backend: 1 CPU, 1GB RAM
- Frontend: 0.5 CPU, 512MB RAM
- Ollama: 0.5 CPU, 2GB RAM

### Kubernetes (2-3 CPUs):
- mongot pod: 1-2 CPUs, 2-3GB RAM
- Operator: 0.5 CPU, 200MB RAM

**Total: 6-7 CPUs, ~8GB RAM**

---

## 🔧 Troubleshooting

### mongot Pods Not Starting

```bash
# Check operator logs
kubectl logs -n mongodb deployment/mongodb-kubernetes-operator

# Check mongot logs
kubectl logs -n mongodb -l app=mdbs-search-svc

# Check MongoDBSearch status
kubectl get mdbs -n mongodb
kubectl describe mdbs mdbs -n mongodb
```

### MongoDB Can't Connect to mongot

**Symptoms:** "SearchNotEnabled" error persists

**Checks:**
1. Verify `MONGOT_HOST` is set in `docker-compose.override.yml`
2. Verify LoadBalancer has external IP: `kubectl get service mdbs-external -n mongodb`
3. Test connectivity from MongoDB:
   ```bash
   docker exec mongodb-enterprise curl -v telnet://LOADBALANCER_IP:27027
   ```
4. Check MongoDB logs: `docker compose logs mongodb | grep -i search`

### Search Sync User Authentication Fails

**Symptoms:** mongot logs show authentication errors

**Fix:**
1. Verify user exists:
   ```bash
   docker exec -it mongodb-enterprise mongosh -u admin -p password123 --authenticationDatabase admin
   use admin
   db.getUser("search-sync-source")
   ```

2. Verify password in K8s secret matches:
   ```bash
   kubectl get secret rs0-search-sync-source-password -n mongodb -o jsonpath='{.data.password}' | base64 -d
   ```

3. Verify keyfile matches:
   ```bash
   # From Docker
   docker exec mongodb-enterprise cat /data/keyfile/mongodb.key
   
   # From K8s
   kubectl get secret rs0-keyfile -n mongodb -o jsonpath='{.data.keyfile}' | base64 -d
   ```

### LoadBalancer IP Not Assigned

**Cloud providers:** Should assign IP automatically

**Minikube/kind:**
```bash
# Minikube
minikube tunnel  # Run in separate terminal

# kind
# Use NodePort instead of LoadBalancer
kubectl patch service mdbs-external -n mongodb -p '{"spec":{"type":"NodePort"}}'
kubectl get service mdbs-external -n mongodb
# Use: <node-ip>:<node-port>
```

---

## 🧹 Cleanup

### Remove mongot from Kubernetes

```bash
kubectl delete mdbs mdbs -n mongodb
kubectl delete service mdbs-external -n mongodb
helm uninstall mongodb-kubernetes -n mongodb
kubectl delete namespace mongodb
```

### Remove Docker Compose Stack

```bash
docker compose down -v
```

---

## 🎯 Benefits of This Approach

1. **Native $vectorSearch** - Real MongoDB Enterprise capability
2. **Modest Hardware** - Works on 6-7 CPU machines
3. **Separation of Concerns** - App in Docker, Search in K8s
4. **Easy Updates** - Update app without touching search
5. **Production-Ready** - Same mongot as enterprise deployments

---

## 📚 Next Steps

1. **Test Search Performance:**
   - Upload many documents
   - Compare $vectorSearch vs Python fallback
   - Monitor mongot resource usage

2. **Production Deployment:**
   - Use managed Kubernetes (GKE, EKS, AKS)
   - Scale mongot replicas for HA
   - Add monitoring (Prometheus + Grafana)

3. **Advanced Features:**
   - Hybrid search (text + vector)
   - Multiple vector indexes
   - Cross-collection search

---

## 🔗 References

- [MongoDB Vector Search Docs](https://www.mongodb.com/docs/atlas/atlas-vector-search/)
- [MongoDB Kubernetes Operator](https://github.com/mongodb/mongodb-kubernetes)
- [MongoDBSearch CR Reference](https://www.mongodb.com/docs/kubernetes/reference/fts-vs-settings/)

---

**Questions?** Check the main [README.md](./README.md) or open an issue!

