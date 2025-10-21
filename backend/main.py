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

@app.get("/search/semantic")
async def semantic_search(q: str, limit: int = 10):
    """Semantic search using embeddings"""
    if not q.strip():
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required")
    
    # Generate embedding for query
    query_embedding = embedding_model.encode(q).tolist()
    
    # Get all documents with embeddings
    all_docs = list(documents.find({"embedding": {"$exists": True}}))
    
    if not all_docs:
        return SearchResponse(query=q, results=[], total=0)
    
    # Calculate cosine similarity
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
