# Architecture Deep Dive: How Enterprise Vector Search Works

**Published:** November 2025  
**Category:** Technical Architecture  
**Reading Time:** 15 minutes

## Introduction: Understanding the Stack

When you click "Search" in this demo, **a lot happens behind the scenes**. This article explains the complete data flow—from user input to search results—so you understand how enterprise vector search actually works in an airgapped environment.

By the end, you'll know:
- How MongoDB's mongot process enables vector search
- Why embeddings are 384 dimensions
- How RAG retrieves context and generates answers
- Where bottlenecks occur and how to optimize them

---

## The Complete Stack: Component Breakdown

```
┌─────────────────────────────────────────────────────────────────┐
│                       USER BROWSER                               │
│  React App (JavaScript) - Port 30999                            │
│  - User submits query "database security best practices"        │
│  - Sends HTTP request to backend API                            │
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BACKEND API (FastAPI)                         │
│  Python - Port 30888                                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Step 1: Embedding Generation                                ││
│  │ - Model: SentenceTransformer (all-MiniLM-L6-v2)            ││
│  │ - Input: "database security best practices"                ││
│  │ - Output: [0.023, -0.156, 0.089, ... ] (384 floats)       ││
│  │ - Time: ~50-100ms                                           ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│               MONGODB ENTERPRISE (mongod + mongot)              │
│  Port 27017 (mongod) + mongot process                          │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Step 2: $vectorSearch Aggregation                          ││
│  │ - Receives 384-dim query vector                            ││
│  │ - mongot searches vector index using HNSW algorithm       ││
│  │ - Computes cosine similarity against all doc embeddings   ││
│  │ - Returns top 10 matches with scores                       ││
│  │ - Time: ~20-50ms (1,000 docs), ~100-200ms (100K docs)     ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Data Storage                                                ││
│  │ {                                                           ││
│  │   "_id": ObjectId("..."),                                  ││
│  │   "title": "Securing Your Database",                       ││
│  │   "body": "Implement authentication and authorization...", ││
│  │   "tags": ["security", "database"],                        ││
│  │   "embedding": [0.012, -0.089, ...] // 384 floats         ││
│  │ }                                                           ││
│  └─────────────────────────────────────────────────────────────┘│
└──────────────────┬──────────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RESULTS RETURNED                            │
│  - Documents ranked by similarity score (0.0 - 1.0)            │
│  - Displayed in UI with highlighted relevance                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component 1: The Embedding Model (SentenceTransformer)

### **What Are Embeddings?**

An **embedding** is a mathematical representation of text as a vector (list of numbers). Similar concepts have similar vectors.

Example:
```
"database security"     → [0.12, -0.45, 0.89, ...]
"securing databases"    → [0.13, -0.44, 0.87, ...] // Very similar
"chocolate cake recipe" → [-0.67, 0.23, -0.12, ...] // Very different
```

### **Why all-MiniLM-L6-v2?**

This model was chosen for **airgapped deployments** because:

1. **Small size:** 80MB (downloads in seconds, fits in memory easily)
2. **Fast inference:** 50-100ms per embedding on CPU (no GPU required)
3. **Good quality:** 384 dimensions provide sufficient semantic understanding
4. **Widely used:** Proven in production by thousands of companies

**Alternatives:**
- **Larger models:** `all-mpnet-base-v2` (768 dims, better quality, 2x slower)
- **Multilingual:** `paraphrase-multilingual-MiniLM-L12-v2` (for non-English)
- **Domain-specific:** Fine-tuned models for medical, legal, technical text

### **How It Works**

```python
from sentence_transformers import SentenceTransformer

# Load model once at startup (cached in memory)
model = SentenceTransformer('all-MiniLM-L6-v2')

# Generate embedding for query
query = "database security best practices"
embedding = model.encode(query)  # Returns numpy array of 384 floats

# embedding = [0.023, -0.156, 0.089, ..., 0.045] (384 values)
```

**Performance:**
- Single query: ~50ms
- Batch of 10 queries: ~200ms (amortized 20ms each)
- Runs on CPU (no GPU required for inference)

### **Memory Usage**

- Model weights: ~250MB RAM
- Per-query overhead: ~5MB (temporary tensors)
- **Total: ~300MB sustained RAM usage**

---

## Component 2: MongoDB Enterprise with mongot

### **What is mongot?**

`mongot` is a **dedicated search process** included in MongoDB Enterprise (not available in Community Edition). It runs alongside `mongod` and provides:

- **Vector search:** HNSW (Hierarchical Navigable Small World) index for fast similarity search
- **Full-text search:** Lucene-based inverted indexes for keyword search
- **Real-time sync:** Automatically indexes new documents as they're inserted

### **How mongot Syncs with mongod**

```
┌─────────────┐          ┌─────────────┐
│   mongod    │  Oplog   │   mongot    │
│  (primary)  │ ───────► │  (search)   │
│             │  Stream  │             │
│  Stores:    │          │  Indexes:   │
│  - Docs     │          │  - Vectors  │
│  - Metadata │          │  - Text     │
└─────────────┘          └─────────────┘
```

**Synchronization process:**
1. Document inserted into MongoDB via `insertOne`
2. mongod writes to oplog (operation log)
3. mongot reads oplog and extracts `embedding` field
4. mongot builds/updates HNSW vector index
5. Search queries hit mongot, not mongod data files

**Latency:** New documents typically searchable within **1-2 seconds** of insertion.

### **The HNSW Algorithm**

HNSW (Hierarchical Navigable Small World) is the algorithm mongot uses for vector search.

**Why HNSW?**
- **Fast:** Sub-linear search time O(log n) instead of linear O(n)
- **Accurate:** Finds true nearest neighbors 95%+ of the time
- **Memory efficient:** Graph structure uses less RAM than flat indexes

**How it works (simplified):**
1. Vectors organized in a multi-layer graph
2. Search starts at top layer (coarse approximation)
3. Traverses to lower layers (finer granularity)
4. Returns k-nearest neighbors with similarity scores

**Trade-offs:**
- Build time: Slower to create index (acceptable for batch indexing)
- Update time: Fast incremental updates (good for real-time ingestion)
- Query time: Extremely fast (what matters for user experience)

### **Vector Index Configuration**

When the backend starts, it creates the vector index:

```python
db.command({
    "createSearchIndexes": "documents",
    "indexes": [{
        "name": "vector_index",
        "type": "vectorSearch",
        "definition": {
            "fields": [{
                "type": "vector",
                "path": "embedding",        # Field containing vector
                "numDimensions": 384,       # Must match model output
                "similarity": "cosine"      # Similarity metric
            }]
        }
    }]
})
```

**Similarity metrics:**
- **cosine:** Best for normalized embeddings (default for most models)
- **euclidean:** Best for distance-based embeddings
- **dotProduct:** Best for specially-trained models

---

## Component 3: The Search Query Flow

### **$vectorSearch Aggregation**

When you search, the backend constructs this aggregation pipeline:

```python
pipeline = [
    {
        "$vectorSearch": {
            "index": "vector_index",           # Which index to use
            "path": "embedding",               # Field with vectors
            "queryVector": query_embedding,    # Your 384-dim query
            "numCandidates": 100,             # Pre-filter candidates
            "limit": 10                        # Final results to return
        }
    },
    {
        "$project": {
            "_id": 1,
            "title": 1,
            "body": 1,
            "tags": 1,
            "score": {"$meta": "vectorSearchScore"}  # Similarity score
        }
    }
]

results = documents.aggregate(pipeline)
```

### **What Happens Inside MongoDB**

1. **mongot receives query vector** (384 floats)
2. **HNSW graph traversal** finds 100 candidate documents (numCandidates)
3. **Exact similarity computed** for all 100 candidates
4. **Top 10 selected** by highest cosine similarity
5. **Scores normalized** to 0.0 - 1.0 range
6. **Results returned** to backend

**Time breakdown (1,000 documents):**
- HNSW traversal: ~5ms
- Similarity computation: ~10ms
- Result serialization: ~5ms
- **Total: ~20ms**

### **numCandidates: The Quality/Speed Tradeoff**

- **Low (20-50):** Faster search, might miss some relevant results
- **Medium (100-200):** Balanced (recommended for most use cases)
- **High (500+):** Slower but finds virtually all relevant results

**Rule of thumb:** `numCandidates = limit × 10` (e.g., limit=10 → numCandidates=100)

---

## Component 4: RAG (Retrieval-Augmented Generation)

### **The Complete RAG Flow**

```
User Question: "How do I improve database performance?"
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 1. RETRIEVE (Vector Search)                             │
│    - Question → embedding → $vectorSearch               │
│    - Get top 10 relevant documents                      │
│    - Time: ~50ms (embedding) + ~30ms (search) = 80ms    │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 2. CONSTRUCT CONTEXT                                    │
│    Context:                                             │
│    Document 1 (Title: Optimizing MongoDB):             │
│    "To improve performance, ensure proper indexes..."   │
│                                                          │
│    Document 2 (Title: Query Performance):               │
│    "Use explain() to analyze slow queries..."           │
│    ...                                                   │
│    (up to 10 documents concatenated)                    │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 3. GENERATE ANSWER (Ollama LLM)                         │
│    Prompt sent to Ollama:                               │
│    System: "Answer based on context only."              │
│    Context: [10 documents]                              │
│    Question: "How do I improve database performance?"   │
│    Answer: [Generated response]                         │
│    - Time: ~5-15 seconds (depends on model & hardware)  │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 4. RETURN ANSWER WITH SOURCES                           │
│    Answer: "To improve database performance, you        │
│    should: 1) Create proper indexes (Document 1)        │
│    2) Analyze slow queries with explain() (Document 2)" │
│                                                          │
│    Sources: [Document 1, Document 2, ...]              │
└─────────────────────────────────────────────────────────┘
```

### **Why This Works**

Traditional LLMs (like ChatGPT) answer from **training data** (generic internet knowledge). RAG answers from **your specific documents** (company policies, product manuals, research papers).

**Benefits:**
- **Accuracy:** LLM can't hallucinate facts not in your documents
- **Verifiability:** Sources are cited, users can check original docs
- **Freshness:** New documents immediately usable (no model retraining)
- **Privacy:** Documents never leave your network

### **The Ollama Component**

Ollama is a **local LLM runtime** (think "Docker for AI models"). This demo uses the **phi** model:

- **Size:** ~1.6GB
- **Speed:** 5-15 seconds for 200-word answer (CPU-only)
- **Quality:** Good for technical Q&A, summaries, explanations

**Alternatives:**
- **llama2:** Better quality, slower (7B parameters)
- **mistral:** Best quality, much slower (7B+ parameters)
- **codellama:** Optimized for code-related questions

### **Custom System Prompts**

The system prompt controls how the LLM responds:

```python
# Default (balanced)
"You are a helpful assistant that answers based on the context. 
If the answer is not in the context, say so."

# Strict (no hallucination)
"Answer ONLY using information from the context. If the context 
doesn't contain the answer, respond with 'Information not found in 
provided documents.' Do not use outside knowledge."

# Executive summary
"You are a senior analyst. Provide concise, bullet-point answers 
citing specific documents by title. Focus on actionable insights."
```

---

## Data Flow: Audio Transcription

### **Whisper AI Pipeline**

```
User uploads audio.mp3 (2.5MB, 90 seconds)
                   │
                   ▼
┌─────────────────────────────────────────────────────────┐
│ 1. FILE UPLOAD (Browser → Backend)                      │
│    - Multipart form data over HTTP                      │
│    - Saved to temp file: /tmp/audio_xyz.mp3             │
│    - Time: ~1 second (network transfer)                 │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 2. WHISPER TRANSCRIPTION (CPU-intensive)                │
│    - FFmpeg decodes audio to WAV                        │
│    - Whisper "base" model processes ~30x realtime       │
│    - For 90sec audio: ~3 seconds transcription time     │
│    - Output: Text + detected language                   │
│    - Memory: ~500MB RAM during processing               │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 3. EMBEDDING GENERATION                                  │
│    - Transcribed text → SentenceTransformer             │
│    - Generate 384-dim embedding                         │
│    - Time: ~100ms                                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│ 4. MONGODB STORAGE                                       │
│    - Insert document with transcription + embedding     │
│    - mongot indexes for search                          │
│    - Time: ~50ms insert + ~1sec indexing                │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
         Document immediately searchable!
```

**Total time for 90-second audio:** ~5-8 seconds end-to-end

---

## Performance Optimization Points

### **1. Embedding Generation (Backend)**

**Bottleneck:** CPU-bound, single-threaded

**Optimizations:**
- **Batch processing:** Embed 10 queries together (amortizes overhead)
- **GPU acceleration:** Add CUDA support for 10x speedup (requires GPU)
- **Caching:** Cache embeddings for common queries (reduces compute)

**Code change for GPU:**
```python
# Install: pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
model = SentenceTransformer('all-MiniLM-L6-v2', device='cuda')
```

### **2. Vector Search (MongoDB)**

**Bottleneck:** HNSW index traversal scales with data size

**Optimizations:**
- **Horizontal scaling:** Add more mongot search nodes (distribute index)
- **numCandidates tuning:** Lower value for faster (less accurate) search
- **Filtered search:** Combine with `$match` stage to pre-filter by category/date

**Example filtered search:**
```python
pipeline = [
    {"$match": {"tags": "security"}},  # Pre-filter by tag
    {"$vectorSearch": {                # Then vector search
        "index": "vector_index",
        "path": "embedding",
        "queryVector": query_embedding,
        "limit": 10
    }}
]
```

### **3. RAG Answer Generation (Ollama)**

**Bottleneck:** LLM inference is slow on CPU (5-15 seconds)

**Optimizations:**
- **GPU acceleration:** Ollama supports CUDA/ROCm (10x faster)
- **Smaller models:** Use `phi` (fast) vs `llama2` (slower but better)
- **Parallel requests:** Run multiple Ollama instances (load balancing)
- **Prompt engineering:** Shorter context = faster generation

**Hardware impact:**
- **CPU-only:** 5-15 seconds per answer
- **GPU (RTX 3060):** 1-2 seconds per answer
- **GPU (A100):** <1 second per answer

---

## Scaling: How Big Can This Get?

### **Document Volume**

| Documents | Vector Index Size | Search Time | Hardware Needed |
|-----------|------------------|-------------|-----------------|
| 1,000 | ~2MB | 20-30ms | Hybrid (6 CPU) |
| 10,000 | ~20MB | 50-80ms | Hybrid (6 CPU) |
| 100,000 | ~200MB | 100-200ms | Full K8s (12 CPU) |
| 1,000,000 | ~2GB | 300-500ms | Full K8s + Sharding |
| 10,000,000+ | ~20GB+ | 500ms-1s | Distributed (50+ CPU) |

**Scaling strategies:**
- **Vertical:** Add more CPU/RAM to mongot nodes (works up to ~1M docs)
- **Horizontal:** Add more search nodes, shard data (for 10M+ docs)
- **Hybrid:** Use pre-filtering to reduce search space ($match before $vectorSearch)

### **Query Volume**

| Queries/sec | Backend Instances | MongoDB Nodes | Total CPU |
|-------------|------------------|---------------|-----------|
| 1-10 | 1 | 1 | 6-8 |
| 10-100 | 2-3 | 3 | 16-24 |
| 100-1000 | 5-10 | 3-5 | 40-60 |
| 1000+ | 10+ | 5+ shards | 100+ |

---

## Monitoring & Debugging

### **Using the System Health Dashboard**

The demo includes a `/health/system` endpoint showing:

- **MongoDB:** Connection status, replica set health, index status
- **Ollama:** Model availability, response time
- **Backend:** Memory usage, model loading status
- **System:** CPU%, RAM%, disk usage

**Access in UI:** Click "System Health" section, then "Load System Info"

### **Ops Manager (Full Kubernetes)**

For production deployments, Ops Manager provides:

- **Query analytics:** Which searches are slowest?
- **Index performance:** Is vector index being used efficiently?
- **Resource utilization:** Is mongot CPU-bound or memory-bound?
- **Alerts:** Notifications when search latency exceeds threshold

### **Common Issues**

**"Vector index not found"**
- **Cause:** mongot not running or not synced
- **Fix:** Check mongot process, verify MONGOT_HOST in config

**"Slow search (>1 second)"**
- **Cause:** Too many documents, numCandidates too high
- **Fix:** Add search nodes or lower numCandidates

**"RAG answer takes 30+ seconds"**
- **Cause:** Ollama model not loaded or CPU-bound
- **Fix:** Pre-load model, add GPU, or use smaller model

---

## Key Takeaways

1. **Embeddings are the foundation** - 384-dim vectors capture semantic meaning
2. **mongot enables native vector search** - HNSW algorithm for fast similarity matching
3. **RAG combines retrieval + generation** - Vector search finds context, LLM generates answers
4. **Performance is tunable** - Trade accuracy for speed via numCandidates
5. **Scaling is predictable** - Linear growth in hardware needs with data volume

---

**Next Steps:**
- Load 1,000+ documents and test search performance yourself
- Try adjusting numCandidates (in main.py) and observe speed/quality tradeoffs
- Monitor System Health during heavy usage
- Review Ops Manager metrics (Full Kubernetes deployment)

**Want to go deeper?** Read the MongoDB Vector Search documentation and SentenceTransformers model card for implementation details.

