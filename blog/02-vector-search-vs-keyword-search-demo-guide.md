# Vector Search vs Keyword Search: A Hands-On Demo Guide

**Published:** November 2025  
**Category:** Tutorial, Search Technology  
**Reading Time:** 10 minutes

## Why This Demo Matters

If you're evaluating this application, you're probably asking: **"Is vector search actually better than traditional keyword search, or is it just hype?"**

This guide will show you **exactly how to test both** using this demo application, with real examples that highlight the differences.

## Understanding the Two Search Types

### **Keyword Search (Full-Text Search)**

**How it works:**
- Looks for exact word matches in documents
- Uses inverted indexes (like a book index)
- Ranks results by term frequency and field weighting
- Fast and well-understood technology

**Best for:**
- Known entity searches ("John Smith", "Project Apollo")
- Exact terminology ("MongoDB replica set configuration")
- Document titles and identifiers

**Limitations:**
- Misses synonyms ("car" won't find "automobile")
- Struggles with different phrasings
- No understanding of context or meaning

### **Vector Search (Semantic Search)**

**How it works:**
- Converts text to high-dimensional numerical vectors (embeddings)
- Measures similarity between query and document vectors
- Understands concepts and relationships, not just words
- Powered by machine learning models

**Best for:**
- Conceptual queries ("documents about network security threats")
- Questions in natural language ("How do I improve query performance?")
- Cross-language searches (with multilingual models)

**Limitations:**
- Slightly slower than keyword search
- Requires embedding generation (compute cost)
- Can be "too clever" for exact matches

## Demo Scenario: Testing Both Methods

Let's walk through a real evaluation scenario using this application.

### **Step 1: Load Sample Documents**

First, we'll add documents using the **"Add Document"** section. Create these three documents:

**Document 1: Database Performance**
```
Title: Optimizing MongoDB Query Speed
Body: To improve database performance, ensure proper indexes are created. 
Monitor slow queries using the profiler. Consider sharding for horizontal 
scaling when dataset exceeds single-server capacity.
Tags: mongodb, performance, optimization
```

**Document 2: Security Best Practices**
```
Title: Securing Your Database Infrastructure
Body: Implement authentication and authorization controls. Enable encryption 
at rest and in transit. Regularly audit access logs to detect unauthorized 
intrusion attempts or suspicious activity patterns.
Tags: security, database, compliance
```

**Document 3: Backup Strategies**
```
Title: Enterprise Data Protection Methods
Body: Establish automated backup schedules using Ops Manager. Test restore 
procedures quarterly. Maintain offsite copies for disaster recovery. Document 
retention policies must comply with regulatory requirements.
Tags: backup, disaster-recovery, compliance
```

### **Step 2: Test Keyword Search**

In the **Search** section, disable "Semantic Search" (toggle off). This uses MongoDB's `$search` operator—traditional full-text search with mongot.

**Test Query 1: "performance"**
- ✅ Finds: Document 1 (exact word match in title and body)
- ❌ Misses: Document 2 and 3 (word "performance" not present)

**Test Query 2: "unauthorized access"**
- ✅ Finds: Document 2 (both words present in body)
- ❌ Misses: Documents 1 and 3
- **Note:** Ranks based on term frequency, not meaning

**Test Query 3: "speed optimization"**
- ✅ Finds: Document 1 (both words present)
- ⚠️ May rank poorly if words are far apart in document

### **Step 3: Test Vector Search**

Now enable "Semantic Search" (toggle on). This uses MongoDB's `$vectorSearch` operator—embedding-based similarity.

**Test Query 1: "How do I make queries faster?"**
- ✅ Finds: Document 1 (understands "faster" = "performance" concept)
- ✅ High relevance score despite no exact word matches
- **Why it works:** Embedding model understands the *intent* of your question

**Test Query 2: "detecting security breaches"**
- ✅ Finds: Document 2 (understands "breaches" = "unauthorized intrusion")
- ✅ Also understands "detecting" relates to "audit access logs"
- **Why it works:** Semantic similarity between concepts

**Test Query 3: "data loss prevention"**
- ✅ Finds: Document 3 (understands "loss prevention" = "backup" concept)
- ⚠️ Might also find Document 2 if it mentions data protection
- **Why it works:** Vector search maps concepts to related topics

### **Step 4: Compare Results Side-by-Side**

Use this table to record your findings:

| Query | Keyword Results | Vector Results | Winner |
|-------|----------------|----------------|--------|
| "performance" | Doc 1 only | Doc 1 + related | Tie |
| "unauthorized access" | Doc 2 (exact) | Doc 2 (better context) | Vector |
| "speed optimization" | Doc 1 (weak) | Doc 1 (strong) | Vector |
| "making database faster" | Possibly none | Doc 1 | Vector |
| "MongoDB replica set" | Doc 1 (if mentioned) | Doc 1 | Keyword |

**Key Insight:** Vector search excels when users express needs in **natural language** or use **different terminology** than what appears in documents.

## Demo Scenario 2: Speech-to-Text + Semantic Search

This is where the application truly shines in airgapped environments.

### **Step 1: Upload Audio File**

1. Record yourself saying: *"What are the best practices for protecting sensitive data in a database environment?"*
2. Save as `.mp3`, `.wav`, or `.opus`
3. Upload via **"Audio to Document"** section

### **Step 2: Review Transcription**

The application uses **Whisper AI** (running locally) to transcribe:
- Check accuracy of transcription
- Notice language auto-detection
- See how it's automatically tagged with `audio-transcription`

### **Step 3: Search Your Own Voice**

Now try vector search with queries like:
- "database security" (should find your audio transcript)
- "sensitive information protection" (different words, same meaning)

**Why This Matters in Airgapped Environments:**
- Field teams record observations/interviews
- Audio converted to searchable text without cloud APIs
- Semantic search finds relevant recordings even with imprecise queries

## Demo Scenario 3: RAG (Retrieval-Augmented Generation)

After loading documents, test the **Chat** feature.

### **How It Works (Behind the Scenes)**

1. Your question is converted to an embedding vector
2. Vector search retrieves the 10 most relevant documents
3. Those documents become "context" for the LLM
4. Ollama (local LLM) generates an answer based **only** on that context

### **Test Questions**

**Question 1: "What should I do to improve database performance?"**

**Expected Behavior:**
- Retrieves Document 1 (performance doc) via vector search
- Ollama generates answer mentioning: indexes, profiler, sharding
- **Sources shown:** Document 1 cited

**Why It's Accurate:**
- Answer comes from *your* documents, not generic LLM training data
- Sources are verifiable (you can click to see original documents)

**Question 2: "How do I detect security breaches?"**

**Expected Behavior:**
- Retrieves Document 2 (security doc)
- Mentions: audit logs, intrusion detection, suspicious activity
- **Sources shown:** Document 2 cited

**Question 3: "Tell me about disaster recovery"**

**Expected Behavior:**
- Retrieves Document 3 (backup doc)
- Mentions: automated backups, restore testing, offsite copies
- **Sources shown:** Document 3 cited

### **Testing Custom Prompts**

Expand "Custom System Prompt" to change how the LLM responds:

**Prompt Example 1 (Concise):**
```
You are a technical documentation assistant. Provide brief, bullet-point 
answers based only on the context. If information is not in the context, 
say "Not found in provided documents."
```

**Prompt Example 2 (Detailed):**
```
You are a senior database architect. Provide detailed explanations with 
reasoning. Reference specific documents by title. If the context doesn't 
fully answer the question, explain what's missing.
```

**Why This Matters:**
- Same documents, different response styles
- Adaptable to different user roles (engineer vs executive)
- Demonstrates LLM control without retraining models

## Common Evaluation Questions

### **Q1: "How much data can this handle?"**

**Test yourself:**
- Load 100 documents via the UI (or bulk import via API)
- Measure search response times
- Check MongoDB storage size in Ops Manager

**Expected Performance:**
- 1,000 documents: <50ms vector search
- 10,000 documents: <200ms vector search
- 100,000+ documents: Consider adding search nodes (horizontal scaling)

### **Q2: "What if my documents are in multiple languages?"**

**Test yourself:**
- Add a document in Spanish: *"Las mejores prácticas de seguridad incluyen autenticación..."*
- Search in English: "security best practices"
- **Current model limitation:** `all-MiniLM-L6-v2` is primarily English
- **Production solution:** Swap to multilingual model like `paraphrase-multilingual-MiniLM-L12-v2`

### **Q3: "Can I control what gets embedded?"**

**Current behavior:**
- Title + Body + Tags are concatenated and embedded together
- Change in `main.py` line 721: `text_for_embedding = f"{title} {body} {tags}"`

**Customization options:**
- Embed title separately (for title-specific searches)
- Exclude tags from embeddings
- Add metadata fields (author, date, classification level)

### **Q4: "How do I tune relevance?"**

**Keyword search tuning:**
- Boost title matches over body matches
- Adjust analyzer (stemming, stop words)
- Configure in MongoDB search index definition

**Vector search tuning:**
- Adjust `numCandidates` parameter (line 1087 in `main.py`)
  - Higher = more accurate, slower
  - Lower = faster, may miss results
- Use different embedding models (larger = better quality, slower)
- Add re-ranking stage (combine vector + keyword scores)

## Performance Comparison in This Demo

Run these tests yourself using browser DevTools (Network tab):

| Operation | Keyword Search | Vector Search | Difference |
|-----------|---------------|---------------|------------|
| **Response Time (10 docs)** | ~15-30ms | ~30-60ms | 2x slower |
| **Disk Space per Doc** | ~5KB | ~6.5KB | +1.5KB (embedding) |
| **Index Build Time (1K docs)** | ~2 seconds | ~5 seconds | 2.5x slower |
| **CPU Usage (query)** | Low | Medium | Higher compute |

**Conclusion:** Vector search has overhead, but the **semantic accuracy** often justifies the cost.

## When to Use Which Search Type

### **Use Keyword Search When:**
- Users know exact entity names ("Customer #12345")
- Searching structured fields (product codes, IDs)
- Extremely low-latency required (<10ms)
- Document language is highly technical/domain-specific

### **Use Vector Search When:**
- Users ask questions in natural language
- Documents use varied terminology for same concepts
- "Discovery" searches (explore related topics)
- Multilingual search is needed

### **Use Hybrid Search (Both) When:**
- You want best of both worlds
- Re-rank vector results using keyword relevance
- Filter by exact fields (date, category) then vector search

**Note:** Hybrid search requires custom implementation (combine both operators in aggregation pipeline).

## Try This Advanced Test

To really understand the power of vector search:

### **The Synonym Challenge**

1. Add document: "Our company uses automobiles for field operations."
2. Search (keyword): "cars" → **Zero results** (word not present)
3. Search (vector): "cars" → **Finds it!** (understands cars = automobiles)

### **The Context Challenge**

1. Add document: "The Jaguar sighting was reported near the riverbank."
2. Add document: "The Jaguar sports car has a powerful engine."
3. Search (keyword): "Jaguar" → **Both results, no context**
4. Search (vector): "wildlife observation" → **Finds first doc only**
5. Search (vector): "luxury vehicles" → **Finds second doc only**

Vector search understands **context** to disambiguate meaning.

## Monitoring Search Performance

Use the **System Health** section to monitor:

- **MongoDB Operations:** Check `execution_time_ms` for each search
- **Backend Memory:** Embedding model uses ~500MB RAM
- **Ollama Status:** Chat/RAG requires LLM to be healthy

In production, Ops Manager provides:
- Search query distribution (which types are used most)
- Index performance metrics
- Resource utilization trends

## Key Takeaways for Evaluators

1. **Vector search isn't magic**—it's machine learning-based similarity matching
2. **Both search types have valid use cases**—choose based on user behavior
3. **Embeddings have cost**—storage, compute, and latency overhead
4. **MongoDB Enterprise enables both** through mongot search nodes
5. **Airgapped deployment is viable**—all models run locally

## Next Steps

After testing these scenarios:

- **Evaluate for your data:** Load real documents (sanitized samples)
- **Measure performance:** Record actual response times at scale
- **Test multilingual:** If needed, verify non-English languages
- **Assess hardware:** Determine CPU/RAM requirements for your volume

**Questions to answer:**
- Do your users search with keywords or natural language?
- What's your accuracy vs speed tolerance?
- How much data will you index initially? Growth rate?

---

**Pro Tip:** Take screenshots during your evaluation—they'll be invaluable when presenting findings to stakeholders.

**Ready to go deeper?** Try the RAG demo next to see how vector search powers AI-driven question answering.

