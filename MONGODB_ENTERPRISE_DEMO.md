# MongoDB Enterprise Advanced Demo Guide

This project demonstrates **MongoDB Enterprise Advanced** capabilities including:
- ✅ Vector Search for AI-powered semantic search
- ✅ Full-text Search with advanced features  
- ✅ RAG (Retrieval-Augmented Generation) with LLMs
- ✅ Speech-to-text with embeddings

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  USER INTERFACE                         │
│            React + Voice + Chat                         │
└──────────────────────┬──────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────┐
│                  BACKEND (FastAPI)                      │
│  • Whisper AI (Speech-to-Text)                         │
│  • SentenceTransformers (Embeddings)                   │
│  • Ollama (LLM for RAG)                                │
└──────────────────────┬──────────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────────┐
│         MONGODB ENTERPRISE ADVANCED                     │
│                                                         │
│  🔍 Vector Search ($vectorSearch)                      │
│     - 384-dim embeddings                               │
│     - Cosine similarity                                │
│     - Native indexing                                  │
│                                                         │
│  📊 Full-Text Search                                   │
│     - Text indexes                                     │
│     - Language analyzers                               │
│                                                         │
│  💾 Document Storage                                   │
│     - Text content                                     │
│     - Vector embeddings                                │
│     - Metadata                                         │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Deployment Options

### Option 1: Docker Compose (Quick Demo)

**What you get:**
- ✅ MongoDB Enterprise Server
- ✅ Ollama LLM
- ✅ Full application stack
- ⚠️ Vector Search with fallback (no dedicated search nodes)

**Best for:**
- Quick demos
- Development
- Testing features
- Learning MongoDB Enterprise

**Limitation:**
- `$vectorSearch` aggregation will fall back to Python implementation
- No dedicated Atlas Search nodes
- Still demonstrates all features functionally

```bash
docker-compose up -d
```

---

### Option 2: Kubernetes with Atlas Search (Full Demo)

**What you get:**
- ✅ MongoDB Enterprise Advanced
- ✅ **Dedicated Atlas Search nodes**
- ✅ **Native $vectorSearch**  
- ✅ Ops Manager
- ✅ Production-ready deployment

**Best for:**
- Full MongoDB Enterprise demo
- Production environments
- Showing complete capabilities
- Customer presentations

```bash
./deploy.sh
```

---

## 🎯 Vector Search: How It Works

### 1. **Embedding Generation**

Every document gets a 384-dimensional vector embedding:

```python
# In backend (SentenceTransformers)
text = f"{title} {body} {tags}"
embedding = embedding_model.encode(text).tolist()

# Stored in MongoDB
{
  "title": "AI Tutorial",
  "body": "Learn about machine learning...",
  "tags": ["AI", "ML"],
  "embedding": [0.234, -0.156, 0.892, ..., -0.123]  // 384 numbers
}
```

### 2. **Vector Search Index**

MongoDB creates an optimized index for vector similarity:

```javascript
{
  "name": "vector_index",
  "type": "vectorSearch",
  "definition": {
    "fields": [{
      "type": "vector",
      "path": "embedding",
      "numDimensions": 384,
      "similarity": "cosine"
    }]
  }
}
```

### 3. **Query with $vectorSearch**

When user searches, MongoDB finds similar vectors:

```python
# Generate query embedding
query_embedding = embedding_model.encode("machine learning")

# MongoDB vector search
pipeline = [
    {
        "$vectorSearch": {
            "index": "vector_index",
            "path": "embedding",
            "queryVector": query_embedding,
            "numCandidates": 100,
            "limit": 10
        }
    }
]

results = db.documents.aggregate(pipeline)
```

**MongoDB handles:**
- ✅ Approximate Nearest Neighbor (ANN) search
- ✅ Cosine similarity calculation
- ✅ Result ranking by score
- ✅ Optimized performance at scale

---

## 🔄 Docker vs Kubernetes Vector Search

### Docker Compose Setup

**Flow:**
```
Query → Embedding → Python calculates similarity → Results
```

**Code:**
```python
# Fallback when $vectorSearch not available
for doc in all_docs:
    similarity = np.dot(query_embedding, doc["embedding"]) / (
        np.linalg.norm(query_embedding) * np.linalg.norm(doc["embedding"])
    )
```

**Pros:**
- ✅ Works immediately
- ✅ Demonstrates concept
- ✅ Good for small datasets (<10k docs)

**Cons:**
- ❌ Slower for large datasets
- ❌ Not using MongoDB's native capability

---

### Kubernetes Setup

**Flow:**
```
Query → Embedding → MongoDB $vectorSearch → Results
```

**Code:**
```python
# Native MongoDB Vector Search
pipeline = [{
    "$vectorSearch": {
        "index": "vector_index",
        "queryVector": query_embedding,
        ...
    }
}]
results = db.documents.aggregate(pipeline)
```

**Pros:**
- ✅ **Native MongoDB capability**
- ✅ **Optimized performance**
- ✅ Scales to millions of vectors
- ✅ Uses dedicated search nodes
- ✅ Shows true Enterprise features

**Cons:**
- ⚠️ Requires full deployment (more complex)
- ⚠️ Needs Enterprise license

---

## 📊 Feature Comparison

| Feature | Docker Compose | Kubernetes (deploy.sh) |
|---------|---------------|----------------------|
| **MongoDB Version** | Enterprise 8.0.3 | Enterprise 8.2.1 |
| **Vector Search** | Python fallback | Native $vectorSearch |
| **Search Nodes** | ❌ No | ✅ Dedicated nodes |
| **Performance** | Good (<10k docs) | Excellent (millions) |
| **Ops Manager** | ❌ No | ✅ Yes |
| **Setup Time** | 5-10 minutes | 15-30 minutes |
| **Best For** | Development/Demo | Production/Full Demo |

---

## 🎓 Setting Up Vector Search

### For Docker Compose:

The app automatically falls back to Python-based vector search. Works out of the box!

```bash
docker-compose up -d
# Upload documents → Automatic embeddings → Search works!
```

---

### For Kubernetes (Full Atlas Search):

1. **Deploy with Atlas Search nodes:**
```bash
./deploy.sh
```

2. **Create vector search index:**

Option A - MongoDB Shell:
```bash
kubectl exec -it mongodb-0 -n mongodb -- mongosh

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

Option B - Atlas UI (if using Atlas):
- Go to Database → Search
- Create Search Index → JSON Editor
- Paste index definition from `scripts/setup-vector-search.js`

3. **Verify index:**
```bash
db.documents.getSearchIndexes()
```

4. **Test vector search:**
```bash
# Make a search request - now uses native $vectorSearch!
curl "http://localhost:8000/search/semantic?q=machine%20learning"
```

---

## 🧪 Demo Script

### Quick Demo (Docker):

```bash
# 1. Start everything
docker-compose up -d

# 2. Open UI
open http://localhost:5173

# 3. Upload a document
# - Click "Add New Document"
# - Title: "Machine Learning Basics"
# - Body: "Introduction to neural networks and deep learning"
# - Submit

# 4. Try semantic search
# - Toggle "Semantic Search"
# - Search: "AI and neural nets"
# - See similar documents!

# 5. Ask questions
# - Go to chat section
# - Ask: "What is covered in the ML tutorial?"
# - Get AI-powered answer!
```

---

### Full Enterprise Demo (Kubernetes):

```bash
# 1. Deploy full stack
./deploy.sh

# 2. Create vector search index
kubectl exec -it mongodb-0 -n mongodb -- mongosh
# Run setup-vector-search.js commands

# 3. Port forward services
kubectl port-forward svc/backend 8000:8000 -n mongodb &
kubectl port-forward svc/frontend 5173:5173 -n mongodb &

# 4. Demo native $vectorSearch
# - Upload documents via UI
# - Show MongoDB Ops Manager
# - Demonstrate vector search performance
# - Show search index in Atlas UI
```

---

## 🔍 Demonstrating MongoDB Vector Search

### What to Show:

1. **Document Ingestion:**
   - Upload text/audio
   - Show automatic embedding generation
   - View in MongoDB (including embedding field)

2. **Semantic Search:**
   - Search: "machine learning"
   - Matches: "AI", "neural networks", "deep learning"
   - Show it finds by meaning, not keywords!

3. **Vector Search Index:**
   - Show index definition
   - Explain 384 dimensions
   - Explain cosine similarity

4. **Performance:**
   - Add many documents
   - Show instant search results
   - Explain ANN (Approximate Nearest Neighbor)

5. **RAG with Vector Search:**
   - Ask question
   - Show: Query → Vector Search → Top docs → LLM → Answer
   - Highlight MongoDB's role in retrieval

---

## 📈 Scaling Story

### Small Dataset (Docker):
```
1,000 documents
Python cosine similarity: ~100ms
✅ Acceptable for demo
```

### Medium Dataset (Early Kubernetes):
```
10,000 documents  
Python: ~1,000ms (slow!)
MongoDB $vectorSearch: ~50ms
✅ 20x faster
```

### Large Dataset (Full Enterprise):
```
1,000,000 documents
Python: Would take forever
MongoDB $vectorSearch: ~100ms
✅ Only MongoDB solution works
```

---

## 🎤 Presenting to Customers

### Opening Statement:
> "This demo showcases MongoDB Enterprise Advanced with Vector Search - a critical capability for modern AI applications. You'll see how MongoDB natively handles semantic search, enabling RAG and AI-powered features at scale."

### Key Points:
1. **"Not just a database - an AI platform"**
   - Stores vectors natively
   - Indexes 384-dimensional embeddings
   - Performs ANN search efficiently

2. **"Production-ready vector search"**
   - Dedicated search nodes
   - Scales to millions of vectors
   - Sub-100ms queries

3. **"Complete AI stack"**
   - Vector search for retrieval
   - LLM integration for generation
   - Speech-to-text for accessibility

4. **"Enterprise features"**
   - Ops Manager for monitoring
   - Security and authentication
   - High availability

---

## 🐛 Troubleshooting

### Vector Search Not Working in Docker?

**Expected!** Docker uses fallback. For true `$vectorSearch`:
```bash
./deploy.sh  # Use Kubernetes deployment
```

### How to verify what's being used?

Check backend logs:
```bash
docker-compose logs backend | grep -i "vector"
```

If you see "Falling back to manual search" → using Python (normal for Docker)

---

## 📚 Additional Resources

- **MongoDB Vector Search Docs**: https://www.mongodb.com/docs/atlas/atlas-vector-search/
- **Enterprise Features**: https://www.mongodb.com/products/mongodb-enterprise-advanced
- **Atlas Search**: https://www.mongodb.com/docs/atlas/atlas-search/

---

## ✅ Success Metrics for Demo

After the demo, customer should understand:

✅ MongoDB can store and search vector embeddings natively  
✅ $vectorSearch provides production-ready semantic search  
✅ Integrates seamlessly with AI/ML workflows  
✅ Scales from thousands to millions of vectors  
✅ Enables RAG and other AI use cases  
✅ Enterprise features provide production reliability  

---

**Ready to demo MongoDB Enterprise's AI capabilities! 🚀**

