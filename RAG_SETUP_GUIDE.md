# RAG (Retrieval-Augmented Generation) Setup Guide

## 🤖 What is RAG?

RAG combines:
1. **Retrieval**: Search your documents using semantic search
2. **Augmented**: Use found documents as context
3. **Generation**: LLM generates answers based on your actual data

## 🎯 How It Works

```
User Question → Semantic Search → Find Relevant Docs → LLM + Context → Answer
```

**Example:**
- **Question**: "What did we discuss in the meeting?"
- **System**: Searches documents → Finds top 3 matching docs
- **LLM**: Reads those docs + answers your question
- **Result**: "In the meeting, you discussed quarterly sales targets..."

## 🛠️ Setup Options

You have **two options** for the LLM:

### Option 1: Ollama (FREE, Local, No API Key Needed) ⭐ Recommended

**Install Ollama:**

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh

# Windows
# Download from https://ollama.com/download
```

**Start Ollama and pull a model:**

```bash
# Start Ollama service
ollama serve

# In a new terminal, pull a model (choose one)
ollama pull llama2           # 3.8GB, good balance
ollama pull mistral          # 4.1GB, better quality
ollama pull llama2:13b       # 7.3GB, highest quality
ollama pull phi              # 1.6GB, fastest, lower quality
```

**Set environment variables (optional):**

```bash
# In .env file or terminal
export LLM_PROVIDER=ollama
export OLLAMA_URL=http://localhost:11434
export OLLAMA_MODEL=llama2
```

**That's it!** Start your backend and it will use Ollama automatically.

### Option 2: OpenAI (Paid, Cloud-based)

**Get API Key:**
1. Go to https://platform.openai.com/api-keys
2. Create new API key
3. Copy the key

**Set environment variables:**

```bash
# In .env file or terminal
export LLM_PROVIDER=openai
export OPENAI_API_KEY=sk-your-key-here
```

**Cost:** ~$0.002 per question (very cheap)

## 🚀 Starting the Application

### Backend:

```bash
cd backend
pip install -r requirements.txt
python main.py
```

### Frontend:

```bash
cd frontend
npm install
npm run dev
```

## 💬 Using the Chat Interface

1. **Upload some documents** first (text or audio)
2. Go to the **"Ask Questions About Your Documents"** section
3. Type a question like:
   - "What are the main topics?"
   - "Summarize the key points"
   - "What was said about [topic]?"
4. Click **"Ask"** or press Enter
5. The AI will:
   - Search your documents
   - Find the most relevant ones
   - Use them to answer your question
   - Show you the source documents

## 📊 Example Interaction

**Your Documents:**
- Document 1: "Meeting notes: We decided to launch the product in Q3..."
- Document 2: "Budget: Allocated $50k for marketing..."
- Document 3: "Recipe for chocolate cake..."

**You Ask:** "When are we launching the product?"

**AI Response:** 
> "Based on the meeting notes, you decided to launch the product in Q3."
> 
> **Sources:**
> - Meeting notes: We decided to launch the product in Q3...

## ⚙️ Configuration

### Environment Variables:

Create a `.env` file in the backend folder:

```bash
# LLM Provider
LLM_PROVIDER=ollama  # or "openai"

# Ollama Settings (if using Ollama)
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=llama2  # or mistral, phi, etc.

# OpenAI Settings (if using OpenAI)
OPENAI_API_KEY=sk-your-key-here

# MongoDB
MONGODB_URL=mongodb://admin:password123@localhost:27017/searchdb?authSource=admin
```

### Adjust RAG Parameters:

In frontend, when calling the API:
```javascript
{
  question: "Your question",
  max_context_docs: 3  // Number of documents to use as context
}
```

More docs = better context but slower/more expensive.

## 🔍 How RAG Works (Technical)

### Backend Flow (`/chat` endpoint):

```python
# 1. User asks question
question = "What are the main topics?"

# 2. Create embedding from question
query_embedding = embedding_model.encode(question)

# 3. Search documents by similarity
for doc in all_documents:
    similarity = cosine_similarity(query_embedding, doc.embedding)

# 4. Get top 3 most relevant documents
top_docs = sorted_docs[:3]

# 5. Build context from documents
context = """
Document 1: [content]
Document 2: [content]
Document 3: [content]
"""

# 6. Send to LLM
prompt = f"Context: {context}\n\nQuestion: {question}\n\nAnswer:"
answer = llm.generate(prompt)

# 7. Return answer + sources
return {
    "answer": answer,
    "sources": top_docs
}
```

## 🆚 RAG vs Regular Search

| Feature | Regular Search | RAG Chat |
|---------|---------------|----------|
| Input | Keywords | Natural questions |
| Output | List of documents | Direct answers |
| Context | None | Uses document content |
| Understanding | Keyword matching | Semantic understanding |
| Best for | Finding docs | Getting answers |

## 🐛 Troubleshooting

### "Ollama error: Connection refused"

**Solution:**
```bash
# Make sure Ollama is running
ollama serve

# Check if it's working
curl http://localhost:11434/api/version
```

### "No LLM configured"

**Solution:**
- Set `LLM_PROVIDER=ollama` in environment
- OR set `OPENAI_API_KEY=sk-...` for OpenAI

### "I don't have any documents..."

**Solution:**
- Upload at least one document first
- Make sure it has content (not empty)

### Slow responses

**Solutions:**
- Use smaller Ollama model: `phi` instead of `llama2`
- Reduce `max_context_docs` from 3 to 1 or 2
- Use OpenAI (faster but costs money)

### Answers not relevant

**Solutions:**
- Upload more relevant documents
- Make question more specific
- Increase `max_context_docs` to 5

## 📈 Performance

### Ollama (Local):
- **First query**: 10-30 seconds (loads model)
- **Subsequent**: 3-10 seconds
- **RAM usage**: 4-8GB depending on model
- **Cost**: FREE

### OpenAI:
- **Every query**: 1-3 seconds
- **RAM usage**: Minimal
- **Cost**: ~$0.002 per question

## 🔒 Privacy

- **Ollama**: 100% private, everything runs locally
- **OpenAI**: Data sent to OpenAI servers (see their privacy policy)

## 🎓 Advanced Tips

1. **Better questions** = better answers
   - ✅ "What budget was allocated for marketing?"
   - ❌ "Budget?"

2. **Upload structured content**
   - Clear titles
   - Organized text
   - Relevant tags

3. **Monitor sources**
   - Check which documents the AI used
   - Verify answers against sources

4. **Tune parameters**
   - More docs = more context but slower
   - Different models have different strengths

## 🚀 Next Steps

Try asking:
- Summarization: "Summarize all meeting notes"
- Comparison: "Compare the two proposals"
- Extraction: "List all action items"
- Analysis: "What are the main challenges mentioned?"

---

**Enjoy your AI-powered document assistant! 🎉**

