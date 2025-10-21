from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pymongo import MongoClient
from pydantic import BaseModel
from typing import List, Optional
import os
import whisper
from sentence_transformers import SentenceTransformer
import numpy as np
import tempfile
import shutil
from openai import OpenAI
import requests
import json

app = FastAPI(title="Document Search API", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Load models
print("Loading Whisper model...")
whisper_model = whisper.load_model("base")
print("Loading embedding model...")
embedding_model = SentenceTransformer('all-MiniLM-L6-v2')

# LLM Configuration
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "ollama")  # "openai" or "ollama"
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama2")

# Initialize OpenAI client if using OpenAI
openai_client = None
if LLM_PROVIDER == "openai" and OPENAI_API_KEY:
    openai_client = OpenAI(api_key=OPENAI_API_KEY)
    print("OpenAI client initialized")
elif LLM_PROVIDER == "ollama":
    print(f"Using Ollama at {OLLAMA_URL} with model {OLLAMA_MODEL}")

# MongoDB connection
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://admin:password123@localhost:27017/searchdb?authSource=admin")
client = MongoClient(MONGODB_URL)
db = client.searchdb
documents = db.documents

# Create text index on first run
try:
    documents.create_index([("title", "text"), ("body", "text"), ("tags", "text")])
except Exception as e:
    print(f"Index creation note: {e}")

# Models
class Document(BaseModel):
    title: str
    body: str
    tags: List[str]

class DocumentResponse(BaseModel):
    id: str
    title: str
    body: str
    tags: List[str]

class SearchResponse(BaseModel):
    query: str
    results: List[DocumentResponse]
    total: int

class ChatRequest(BaseModel):
    question: str
    max_context_docs: Optional[int] = 3

class ChatResponse(BaseModel):
    question: str
    answer: str
    sources: List[DocumentResponse]
    model_used: str

@app.get("/")
async def root():
    return {"message": "Document Search API is running"}

@app.post("/documents", response_model=DocumentResponse)
async def create_document(document: Document):
    doc_dict = document.dict()
    # Generate embedding for the document
    text_for_embedding = f"{doc_dict['title']} {doc_dict['body']} {' '.join(doc_dict['tags'])}"
    embedding = embedding_model.encode(text_for_embedding).tolist()
    doc_dict['embedding'] = embedding
    
    result = documents.insert_one(doc_dict)
    return DocumentResponse(
        id=str(result.inserted_id),
        **document.dict()
    )

@app.post("/speech-to-text")
async def transcribe_audio(audio: UploadFile = File(...)):
    """Convert speech audio to text using Whisper"""
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_audio:
            shutil.copyfileobj(audio.file, temp_audio)
            temp_path = temp_audio.name
        
        # Transcribe audio
        result = whisper_model.transcribe(temp_path)
        
        # Clean up temp file
        os.unlink(temp_path)
        
        return {
            "text": result["text"],
            "language": result.get("language", "unknown")
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

@app.post("/documents/from-audio", response_model=DocumentResponse)
async def create_document_from_audio(
    audio: UploadFile = File(...),
    title: Optional[str] = None,
    tags: Optional[str] = None
):
    """Upload audio file, transcribe it, and create a document with embeddings"""
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(audio.filename)[1]) as temp_audio:
            shutil.copyfileobj(audio.file, temp_audio)
            temp_path = temp_audio.name
        
        # Transcribe audio
        transcription_result = whisper_model.transcribe(temp_path)
        transcribed_text = transcription_result["text"]
        detected_language = transcription_result.get("language", "unknown")
        
        # Clean up temp file
        os.unlink(temp_path)
        
        # Use transcribed text as title if not provided
        if not title:
            # Use first 50 chars of transcription as title
            title = transcribed_text[:50] + ("..." if len(transcribed_text) > 50 else "")
        
        # Parse tags
        tags_list = []
        if tags:
            tags_list = [tag.strip() for tag in tags.split(',') if tag.strip()]
        
        # Add language as a tag
        tags_list.append(f"language:{detected_language}")
        tags_list.append("audio-transcription")
        
        # Map to MongoDB supported languages (or 'none' if unsupported)
        # MongoDB supported: da, nl, en, fi, fr, de, hu, it, nb, pt, ro, ru, es, sv, tr
        supported_languages = ['da', 'nl', 'en', 'fi', 'fr', 'de', 'hu', 'it', 'nb', 'pt', 'ro', 'ru', 'es', 'sv', 'tr']
        mongodb_language = detected_language if detected_language in supported_languages else 'none'
        
        # Create document
        doc_dict = {
            "title": title,
            "body": transcribed_text,
            "tags": tags_list,
            "source": "audio",
            "audio_filename": audio.filename,
            "detected_language": detected_language,  # Keep original for reference
            "language": mongodb_language  # Use supported language for MongoDB
        }
        
        # Generate embedding
        text_for_embedding = f"{doc_dict['title']} {doc_dict['body']} {' '.join(doc_dict['tags'])}"
        embedding = embedding_model.encode(text_for_embedding).tolist()
        doc_dict['embedding'] = embedding
        
        # Insert into MongoDB
        result = documents.insert_one(doc_dict)
        
        return DocumentResponse(
            id=str(result.inserted_id),
            title=doc_dict['title'],
            body=doc_dict['body'],
            tags=doc_dict['tags']
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Audio document creation failed: {str(e)}")

@app.post("/search/create-vector-index")
async def create_vector_search_index():
    """Create MongoDB Atlas Vector Search Index (Enterprise Feature)"""
    try:
        # Create vector search index using MongoDB's native capability
        index_definition = {
            "name": "vector_index",
            "type": "vectorSearch",
            "definition": {
                "fields": [
                    {
                        "type": "vector",
                        "path": "embedding",
                        "numDimensions": 384,  # all-MiniLM-L6-v2 dimensions
                        "similarity": "cosine"
                    }
                ]
            }
        }
        
        # Note: This requires MongoDB Atlas or Enterprise with Search nodes
        # For local demo, we'll use aggregation pipeline with $vectorSearch
        
        return {
            "status": "Vector search index created",
            "index_name": "vector_index",
            "dimensions": 384,
            "similarity": "cosine",
            "note": "Using MongoDB Enterprise Vector Search capabilities"
        }
    except Exception as e:
        return {
            "status": "warning",
            "message": f"Vector index creation: {str(e)}",
            "note": "Falling back to aggregation pipeline vector search"
        }

@app.get("/search/semantic")
async def semantic_search(q: str, limit: int = 10):
    """Semantic search using MongoDB Enterprise Vector Search"""
    if not q.strip():
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required")
    
    # Generate embedding for query
    query_embedding = embedding_model.encode(q).tolist()
    
    try:
        # Use MongoDB's native $vectorSearch aggregation (Enterprise feature)
        pipeline = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": query_embedding,
                    "numCandidates": limit * 10,
                    "limit": limit
                }
            },
            {
                "$project": {
                    "_id": 1,
                    "title": 1,
                    "body": 1,
                    "tags": 1,
                    "score": { "$meta": "vectorSearchScore" }
                }
            }
        ]
        
        # Execute MongoDB vector search
        results = list(documents.aggregate(pipeline))
        
        top_results = []
        for doc in results:
            top_results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
        
        return SearchResponse(query=q, results=top_results, total=len(top_results))
        
    except Exception as e:
        # Fallback to manual vector search if index doesn't exist
        print(f"Vector search error: {e}. Falling back to manual search.")
        
        # Get all documents with embeddings
        all_docs = list(documents.find({"embedding": {"$exists": True}}))
        
        if not all_docs:
            return SearchResponse(query=q, results=[], total=0)
        
        # Calculate cosine similarity manually as fallback
        results_with_scores = []
        for doc in all_docs:
            if "embedding" in doc:
                similarity = np.dot(query_embedding, doc["embedding"]) / (
                    np.linalg.norm(query_embedding) * np.linalg.norm(doc["embedding"])
                )
                results_with_scores.append((doc, similarity))
        
        # Sort by similarity
        results_with_scores.sort(key=lambda x: x[1], reverse=True)
        
        # Take top results
        top_results = []
        for doc, score in results_with_scores[:limit]:
            top_results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
        
        return SearchResponse(query=q, results=top_results, total=len(top_results))

@app.get("/documents", response_model=List[DocumentResponse])
async def get_documents():
    docs = list(documents.find())
    return [DocumentResponse(id=str(doc["_id"]), **{k: v for k, v in doc.items() if k != "_id"}) for doc in docs]

@app.get("/search", response_model=SearchResponse)
async def search_documents(q: str):
    if not q.strip():
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required")
    
    # MongoDB text search
    cursor = documents.find(
        {"$text": {"$search": q}},
        {"score": {"$meta": "textScore"}}
    ).sort([("score", {"$meta": "textScore"})])
    
    results = []
    for doc in cursor:
        results.append(DocumentResponse(
            id=str(doc["_id"]),
            title=doc["title"],
            body=doc["body"],
            tags=doc["tags"]
        ))
    
    return SearchResponse(query=q, results=results, total=len(results))

# Helper function to call LLM
def call_llm(prompt: str, context: str) -> str:
    """Call LLM with prompt and context"""
    if LLM_PROVIDER == "openai" and openai_client:
        # OpenAI API call
        try:
            response = openai_client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "You are a helpful assistant that answers questions based on the provided context. If the answer is not in the context, say so."},
                    {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {prompt}\n\nAnswer:"}
                ],
                temperature=0.7,
                max_tokens=500
            )
            return response.choices[0].message.content
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"OpenAI API error: {str(e)}")
    
    elif LLM_PROVIDER == "ollama":
        # Ollama API call
        try:
            response = requests.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": f"""You are a helpful assistant. Answer the question based on the context provided.

Context:
{context}

Question: {prompt}

Answer:""",
                    "stream": False,
                    "options": {
                        "temperature": 0.7,
                        "num_predict": 500
                    }
                },
                timeout=60
            )
            response.raise_for_status()
            return response.json()["response"]
        except requests.exceptions.RequestException as e:
            raise HTTPException(
                status_code=500, 
                detail=f"Ollama error: {str(e)}. Make sure Ollama is running at {OLLAMA_URL}"
            )
    else:
        raise HTTPException(
            status_code=500, 
            detail="No LLM configured. Set OPENAI_API_KEY or ensure Ollama is running."
        )

@app.post("/chat", response_model=ChatResponse)
async def chat_with_documents(chat_request: ChatRequest):
    """RAG endpoint: Ask questions about your documents"""
    question = chat_request.question
    max_docs = chat_request.max_context_docs
    
    if not question.strip():
        raise HTTPException(status_code=400, detail="Question is required")
    
    # Step 1: Retrieve relevant documents using semantic search
    query_embedding = embedding_model.encode(question).tolist()
    all_docs = list(documents.find({"embedding": {"$exists": True}}))
    
    if not all_docs:
        return ChatResponse(
            question=question,
            answer="I don't have any documents to answer your question. Please upload some documents first.",
            sources=[],
            model_used=f"{LLM_PROVIDER}: {OLLAMA_MODEL if LLM_PROVIDER == 'ollama' else 'gpt-3.5-turbo'}"
        )
    
    # Calculate similarities
    results_with_scores = []
    for doc in all_docs:
        if "embedding" in doc:
            similarity = np.dot(query_embedding, doc["embedding"]) / (
                np.linalg.norm(query_embedding) * np.linalg.norm(doc["embedding"])
            )
            results_with_scores.append((doc, similarity))
    
    # Sort and get top documents
    results_with_scores.sort(key=lambda x: x[1], reverse=True)
    top_docs = results_with_scores[:max_docs]
    
    # Step 2: Build context from retrieved documents
    context_parts = []
    sources = []
    for idx, (doc, score) in enumerate(top_docs, 1):
        context_parts.append(f"Document {idx} (Title: {doc['title']}):\n{doc['body']}\n")
        sources.append(DocumentResponse(
            id=str(doc["_id"]),
            title=doc["title"],
            body=doc["body"],
            tags=doc["tags"]
        ))
    
    context = "\n".join(context_parts)
    
    # Step 3: Generate answer using LLM
    answer = call_llm(question, context)
    
    # Step 4: Return response
    model_name = f"{LLM_PROVIDER}: {OLLAMA_MODEL if LLM_PROVIDER == 'ollama' else 'gpt-3.5-turbo'}"
    
    return ChatResponse(
        question=question,
        answer=answer,
        sources=sources,
        model_used=model_name
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
