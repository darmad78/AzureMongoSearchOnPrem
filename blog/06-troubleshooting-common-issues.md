# Troubleshooting Guide: Common Issues and Solutions

**Published:** November 2025  
**Category:** Support, Technical Guide  
**Reading Time:** 12 minutes

## Introduction: Debugging in Airgapped Environments

When you're demonstrating in an **airgapped environment**, you can't just "Google the error." This guide provides **systematic troubleshooting** for every common issue you might encounter.

**Bookmark this page** before deploying in a secure facility.

---

## Quick Diagnosis: System Health Check

**First step for ANY issue:** Check system health.

### **In the UI:**
1. Click "System Health" section
2. Click "Load System Info"
3. Look for ❌ or ⚠️ indicators

### **In Terminal:**

```bash
# Check all pods are running (Kubernetes)
kubectl get pods -n mongodb

# Check Docker containers are running (Docker Compose)
docker ps

# Check backend logs
docker logs mongodb-search-backend -f

# Check MongoDB logs
docker logs mongodb -f
```

---

## Issue Category 1: Vector Search Errors

### **Error: "Vector index 'vector_index' not found"**

**Symptoms:**
- Semantic search fails with 503 error
- RAG chat fails with "MongoDB Vector Search is not available"
- System Health shows "vector_index_status": "SearchNotEnabled"

**Root Causes:**
1. mongot search process not running
2. MongoDB not configured to connect to mongot
3. Search index not yet built

**Solution:**

**Step 1: Verify mongot is running**

```bash
# Kubernetes: Check for search pod
kubectl get pods -n mongodb | grep search
# Should see: mdb-rs-search-0  1/1  Running

# Docker: Check mongot container
docker ps | grep mongot
```

**Step 2: Check MongoDB configuration**

```bash
# Connect to MongoDB
mongosh "mongodb://admin:password123@localhost:27017/admin"

# Check if mongot is configured
db.adminCommand({ getCmdLineOpts: 1 })
# Look for: searchIndexManagement.mongotHost

# If missing, mongot isn't configured
```

**Step 3: Configure MongoDB to use mongot**

**For Docker Compose:**

Edit `docker-compose.override.yml`:

```yaml
services:
  mongodb:
    environment:
      - MONGOT_HOST=mongot:27027
    command: >
      --setParameter searchIndexManagement.mongotHost=mongot:27027
      --replSet rs0
```

Then restart:
```bash
docker compose restart mongodb
```

**For Kubernetes:**

Edit MongoDB resource with mongot host:

```yaml
spec:
  search:
    enabled: true
    mongotHost: "mdb-rs-search-0.mdb-rs-svc.mongodb.svc.cluster.local:27027"
```

**Step 4: Recreate vector index**

```bash
# Connect to MongoDB
mongosh "mongodb://admin:password123@localhost:27017/admin"

# Switch to searchdb
use searchdb

# List existing indexes
db.documents.listSearchIndexes()

# If vector_index doesn't exist, create it
db.adminCommand({
  createSearchIndexes: "documents",
  indexes: [
    {
      name: "vector_index",
      type: "vectorSearch",
      definition: {
        fields: [
          {
            type: "vector",
            path: "embedding",
            numDimensions: 384,
            similarity: "cosine"
          }
        ]
      }
    }
  ]
})

# Check status (may show "BUILDING" initially)
db.documents.listSearchIndexes()
```

**Wait 1-2 minutes** for index to build, then retry search.

---

### **Error: "Search returns zero results but documents exist"**

**Symptoms:**
- Documents visible in "All Documents" section
- Vector search returns empty results
- System Health shows vector_index_status: "BUILDING"

**Root Cause:** Index is still building (takes time for large datasets)

**Solution:**

```bash
# Check index status
mongosh "mongodb://admin:password123@localhost:27017/searchdb"
db.documents.listSearchIndexes()

# Look for status field:
# - "READY" = good, index is queryable
# - "BUILDING" = wait, index still being created
# - "FAILED" = error, check logs

# If BUILDING, estimate time:
# - 1,000 docs: ~5-10 seconds
# - 10,000 docs: ~30-60 seconds
# - 100,000 docs: ~5-10 minutes
```

**Workaround:** Use keyword search (disable "Semantic Search" toggle) while waiting.

---

### **Error: "Vector search is slow (>1 second)"**

**Symptoms:**
- Search works but takes 1-5 seconds
- UI feels unresponsive

**Root Causes:**
1. Too many documents for single search node
2. numCandidates parameter too high
3. Insufficient CPU/RAM on search node

**Solution:**

**Step 1: Check dataset size**

```bash
mongosh "mongodb://admin:password123@localhost:27017/searchdb"
db.documents.countDocuments()
```

**Performance expectations:**
- <10,000 docs: <100ms (should be fast)
- 10,000-100,000 docs: 100-300ms (acceptable)
- >100,000 docs: 300ms-1s (may need scaling)

**Step 2: Tune numCandidates**

Edit `backend/main.py` line ~1087:

```python
# Current (accurate but slower)
"numCandidates": limit * 10  # e.g., 100 for limit=10

# Faster (slightly less accurate)
"numCandidates": limit * 5   # e.g., 50 for limit=10

# Fastest (may miss some results)
"numCandidates": limit * 2   # e.g., 20 for limit=10
```

Restart backend:
```bash
docker compose restart backend
# OR
kubectl rollout restart deployment backend -n mongodb
```

**Step 3: Add more search nodes (Kubernetes only)**

Edit MongoDB resource:

```yaml
spec:
  search:
    replicas: 2  # Add second search node
```

MongoDB will automatically distribute search load.

---

## Issue Category 2: Audio Transcription Errors

### **Error: "Transcription failed: [Errno 2] No such file or directory: 'ffmpeg'"**

**Symptoms:**
- Audio upload fails immediately
- Backend logs show ffmpeg error

**Root Cause:** FFmpeg not installed (required by Whisper)

**Solution:**

**For Docker:** Rebuild backend image with FFmpeg

```dockerfile
# backend/Dockerfile
FROM python:3.10-slim

# Install FFmpeg
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

# ... rest of Dockerfile
```

```bash
docker compose build backend
docker compose up -d backend
```

**For Kubernetes:** Ensure FFmpeg in container image

```bash
# Check if FFmpeg is available
kubectl exec -n mongodb deployment/backend -- ffmpeg -version
```

---

### **Error: "Audio transcription takes 5+ minutes for 1-minute audio"**

**Symptoms:**
- Transcription works but is extremely slow
- Backend pod shows high CPU usage

**Root Causes:**
1. Using "large" Whisper model instead of "base"
2. Insufficient CPU allocated to backend
3. Audio file is very large (uncompressed WAV)

**Solution:**

**Step 1: Check Whisper model size**

In `backend/main.py` line ~42:

```python
whisper_model = whisper.load_model("base")  # Correct (fast)
# NOT: whisper_model = whisper.load_model("large")  # Slow
```

**Whisper model speeds (CPU-only):**
- **tiny:** 10x realtime (6 sec for 1 min audio)
- **base:** 3-5x realtime (12-20 sec for 1 min audio) ← **Recommended**
- **small:** 1-2x realtime (30-60 sec for 1 min audio)
- **medium:** 0.5x realtime (2 min for 1 min audio)
- **large:** 0.2x realtime (5 min for 1 min audio)

**Step 2: Increase backend CPU**

**Docker Compose:**
```yaml
services:
  backend:
    deploy:
      resources:
        limits:
          cpus: '2.0'  # Increase from 1.0
```

**Kubernetes:**
```yaml
spec:
  containers:
  - name: backend
    resources:
      requests:
        cpu: "1000m"
      limits:
        cpu: "2000m"  # Increase from 1000m
```

**Step 3: Use compressed audio formats**

- ✅ **Good:** .mp3, .opus, .m4a (small file size)
- ❌ **Bad:** .wav (large, especially if high sample rate)

---

### **Error: "Detected language is wrong"**

**Symptoms:**
- Audio in Spanish, but Whisper detects "English"
- Transcription is garbled or incorrect

**Root Cause:** Whisper auto-detection fails for short clips or heavy accents

**Solution: Specify language explicitly**

In the UI, select language from dropdown before uploading:
- Spanish: `es`
- French: `fr`
- German: `de`
- Chinese: `zh`
- Arabic: `ar`

Or via API:

```bash
curl -X POST "http://localhost:30888/documents/from-audio" \
  -F "audio=@recording.mp3" \
  -F "language=es"
```

---

## Issue Category 3: RAG / Chat Errors

### **Error: "Ollama model not ready: Model 'phi' not found"**

**Symptoms:**
- Chat fails with 503 error
- System Health shows Ollama status: "error"

**Root Cause:** Ollama model not pulled

**Solution:**

**Step 1: Check Ollama is running**

```bash
# Docker
docker ps | grep ollama

# Kubernetes
kubectl get pods -n mongodb | grep ollama
```

**Step 2: List available models**

```bash
# Docker
docker exec ollama ollama list

# Kubernetes
kubectl exec -n mongodb deployment/ollama -- ollama list
```

**Step 3: Pull the model**

```bash
# Docker
docker exec ollama ollama pull phi

# Kubernetes
kubectl exec -n mongodb deployment/ollama -- ollama pull phi

# This downloads ~1.6GB (takes 2-5 min on fast network)
```

**Step 4: Verify model is ready**

```bash
# Should now appear in list
docker exec ollama ollama list
# Output: phi:latest  1.6GB  2 minutes ago
```

---

### **Error: "RAG answers are generic/not using my documents"**

**Symptoms:**
- Chat gives generic answers like ChatGPT
- Doesn't cite any sources
- Ignores uploaded documents

**Root Cause:** Vector search retrieval failing (falls back to generic LLM knowledge)

**Solution:**

**Step 1: Verify documents have embeddings**

```bash
mongosh "mongodb://admin:password123@localhost:27017/searchdb"

# Check if documents have embedding field
db.documents.findOne({}, { embedding: 1 })

# Should show: embedding: [ 0.023, -0.156, ... ] (384 values)
# If null or missing, embeddings weren't generated
```

**Step 2: Check vector search is working**

Test vector search directly:

```bash
# In UI: Enable "Semantic Search" and search for anything
# Should return results with "MongoDB Operation" showing "$vectorSearch"

# If it shows "$text" or "find", vector search is not being used
```

**Step 3: Verify RAG is retrieving documents**

Look at "Sources" section after asking a question:
- ✅ **Good:** Shows 5-10 document titles
- ❌ **Bad:** Shows zero sources

If zero sources, vector search index is missing (see Issue Category 1).

---

### **Error: "Chat is slow (30+ seconds per answer)"**

**Symptoms:**
- RAG works but takes 30-60 seconds
- UI shows "Waiting for LLM response..."

**Root Causes:**
1. Ollama model too large (llama2 7B instead of phi 2.7B)
2. CPU-only inference (no GPU)
3. Too many source documents (large context)

**Solution:**

**Step 1: Use faster model**

Edit backend to use smaller model:

```python
# backend/main.py line ~50
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi")  # Fast (2.7B params)
# NOT: "llama2"  # Slower (7B params)
# NOT: "mistral" # Even slower (7B+ params)
```

Pull new model:
```bash
docker exec ollama ollama pull phi
```

**Step 2: Reduce context documents**

Edit RAG request:

```python
# In UI: When asking question, reduce "Max Context Docs" from 10 to 3-5
# Fewer documents = faster processing
```

**Step 3: Add GPU (if available)**

Ollama automatically uses GPU if available. Check:

```bash
docker exec ollama nvidia-smi
# If GPUs listed, Ollama will use them

# Speed improvement with GPU:
# - CPU: 10-30 seconds per answer
# - GPU (RTX 3060): 2-5 seconds
# - GPU (A100): <1 second
```

---

## Issue Category 4: Deployment Issues

### **Error: "Cannot connect to MongoDB: connection refused"**

**Symptoms:**
- Backend can't reach MongoDB
- UI shows "Failed to fetch documents"
- System Health shows MongoDB: "error"

**Root Cause:** MongoDB not running or incorrect connection string

**Solution:**

**Step 1: Verify MongoDB is running**

```bash
# Docker
docker ps | grep mongodb
# Should show: mongodb  Up 5 minutes  27017/tcp

# Kubernetes
kubectl get pods -n mongodb | grep mdb-rs
# Should show: mdb-rs-0  2/2  Running
```

**Step 2: Test connection**

```bash
# Docker
mongosh "mongodb://admin:password123@localhost:27017/admin"

# Kubernetes (port-forward first)
kubectl port-forward -n mongodb svc/mdb-rs-svc 27017:27017
mongosh "mongodb://admin:password123@localhost:27017/admin"
```

**Step 3: Check connection string**

In backend logs:

```bash
docker logs mongodb-search-backend | grep MONGODB_URL
# Should show: MONGODB_URL=mongodb://admin:xxx@mongodb:27017/searchdb
```

**Common mistakes:**
- ❌ `localhost:27017` (should be `mongodb:27017` in Docker network)
- ❌ Wrong password (check docker-compose.yml environment variables)
- ❌ Wrong database name (`admin` vs `searchdb`)

---

### **Error: "Kubernetes pods stuck in 'Pending' state"**

**Symptoms:**
- `kubectl get pods` shows "Pending" for 5+ minutes
- Deployment never completes

**Root Causes:**
1. Insufficient cluster resources
2. Persistent volume claims not bound
3. Image pull failures

**Solution:**

**Step 1: Check pod events**

```bash
kubectl describe pod mdb-rs-0 -n mongodb
# Look at "Events" section for errors
```

**Common errors:**

**"Insufficient CPU"**
```bash
# Solution: Add more nodes or reduce resource requests
kubectl get nodes
kubectl top nodes  # Check available resources
```

**"FailedScheduling: persistentvolumeclaim not found"**
```bash
# Check PVCs
kubectl get pvc -n mongodb

# If not bound, check storage class exists
kubectl get storageclass

# May need to create local storage or use dynamic provisioning
```

**"ImagePullBackOff"**
```bash
# In airgapped environment, images must be pre-loaded
# Load from tarball:
docker load < mongodb-enterprise.tar
docker load < backend.tar
docker load < frontend.tar

# Tag for local registry if using one
```

---

## Issue Category 5: UI / Frontend Issues

### **Error: "Network error: Failed to fetch"**

**Symptoms:**
- All API calls fail in browser console
- Red error messages in UI
- System Health won't load

**Root Cause:** CORS or incorrect API URL

**Solution:**

**Step 1: Check API URL**

Open browser console (F12), look for:
```
Frontend API_URL: http://10.0.2.15:30888
```

Try accessing directly:
```
http://10.0.2.15:30888/health/system
```

If fails → backend not accessible at that URL.

**Step 2: Check backend is running**

```bash
# Docker
docker ps | grep backend
curl http://localhost:30888/

# Kubernetes
kubectl get svc -n mongodb | grep backend
kubectl port-forward -n mongodb svc/backend-service 30888:8000
curl http://localhost:30888/
```

**Step 3: Check firewall rules**

In airgapped/secure environments, port 30888 may be blocked:

```bash
# Test from client machine
telnet <backend-host> 30888

# If fails, request firewall rule:
# - Source: Client subnet
# - Destination: Backend IP
# - Port: 30888/TCP
# - Protocol: HTTP
```

---

### **Error: "MongoDB Operation" section shows "null"**

**Symptoms:**
- Features work but no query details shown
- "MongoDB Operation" section empty

**Root Cause:** This is actually normal for some operations

**Explanation:**

MongoDB operation details are only shown for:
- ✅ Create document (shows insertOne)
- ✅ Search (shows $search or $vectorSearch)
- ✅ Chat/RAG (shows aggregate)

Not shown for:
- ❌ Initial page load (no query yet)
- ❌ System Health check (separate endpoint)

**This is expected behavior, not an error.**

---

## Issue Category 6: Performance Issues

### **Error: "System Health shows high memory usage (90%+)"**

**Symptoms:**
- System sluggish
- Processes getting killed (OOMKilled)
- Swap usage high

**Root Causes:**
1. All AI models loaded simultaneously
2. Insufficient RAM for workload
3. Memory leak (rare)

**Solution:**

**Step 1: Check what's using memory**

```bash
# Docker
docker stats

# Kubernetes
kubectl top pods -n mongodb
```

**Typical memory usage:**
- MongoDB: 500MB - 2GB (depends on dataset)
- Backend (Whisper + SentenceTransformer): 1-2GB
- Ollama (phi model): 2-3GB
- mongot: 500MB - 1GB

**Total: 4-8GB minimum**

**Step 2: Reduce memory if needed**

**Option 1: Unload Whisper if not using audio**
```python
# backend/main.py line ~42
# Comment out:
# whisper_model = whisper.load_model("base")
# whisper_model = None
```

**Option 2: Use smaller Ollama model**
```bash
# Instead of phi (2.7B), use tinyllama (1.1B)
docker exec ollama ollama pull tinyllama
# Edit backend to use OLLAMA_MODEL=tinyllama
```

**Option 3: Increase swap space (last resort)**
```bash
# Linux only - creates 4GB swap file
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Diagnostic Commands Cheat Sheet

**Quick health check:**
```bash
# All-in-one status check
kubectl get pods,svc,pvc -n mongodb
docker ps
curl http://localhost:30888/health/system
```

**Log investigation:**
```bash
# Backend logs (most useful)
docker logs -f mongodb-search-backend
kubectl logs -f -n mongodb deployment/backend

# MongoDB logs
docker logs -f mongodb
kubectl logs -f -n mongodb mdb-rs-0 -c mongod

# Frontend logs (rarely needed)
docker logs -f mongodb-search-frontend
```

**Network debugging:**
```bash
# Test connectivity from backend to MongoDB
docker exec mongodb-search-backend ping mongodb
kubectl exec -n mongodb deployment/backend -- nc -zv mdb-rs-svc 27017

# Test connectivity from browser to backend
curl -v http://<backend-ip>:30888/
```

**MongoDB debugging:**
```bash
# Connect to MongoDB
mongosh "mongodb://admin:password123@localhost:27017/admin"

# Check search indexes
use searchdb
db.documents.listSearchIndexes()

# Check mongot configuration
db.adminCommand({ getCmdLineOpts: 1 })

# Check recent errors
db.adminCommand({ getLog: "global" })
```

---

## When to Escalate

**You can self-resolve:**
- Vector index not ready (just wait)
- Ollama model not pulled (pull it)
- High CPU usage during transcription (expected)

**Escalate to vendor/support if:**
- mongot consistently crashes (check logs: `docker logs mongot`)
- MongoDB replica set won't elect primary (networking issue)
- Persistent "SearchNotEnabled" error after following all troubleshooting steps
- Memory leaks (usage grows unbounded over time)

---

## Prevention: Pre-Demo Checklist

Avoid issues by verifying before demo:

**24 hours before:**
- [ ] Deploy application and verify all components start
- [ ] Add sample documents and test search
- [ ] Upload test audio file and verify transcription
- [ ] Ask test question in RAG chat
- [ ] Check System Health dashboard (all green)

**1 hour before:**
- [ ] Restart all services (fresh start)
- [ ] Re-verify System Health
- [ ] Clear browser cache/cookies
- [ ] Test from demo laptop (not dev machine)
- [ ] Have backup: screenshots/video if live demo fails

---

## Conclusion: Systematic Troubleshooting

**Remember the debugging hierarchy:**

1. **Check System Health** (UI dashboard or `/health/system` endpoint)
2. **Check logs** (backend first, then MongoDB)
3. **Verify configuration** (connection strings, model names)
4. **Test components individually** (MongoDB alone, then backend, then Ollama)
5. **Check resources** (CPU, RAM, disk space)

Most issues are **configuration, not code bugs**. Work methodically through this guide rather than guessing.

---

**Need more help?** Check repository Issues, or review deployment logs line-by-line to identify root cause.

