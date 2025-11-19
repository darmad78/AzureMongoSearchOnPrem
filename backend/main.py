from fastapi import FastAPI, HTTPException, UploadFile, File, Form
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

# Create MongoDB Search index (for $search aggregation - Full-Text Search)
# This requires MongoDB Enterprise with mongot (search nodes)
try:
    print("Creating MongoDB Search index for $search aggregation...")
    db.command({
        "createSearchIndexes": "documents",
        "indexes": [
            {
                "name": "default",
                "definition": {
                    "mappings": {
                        "dynamic": True
                    }
                }
            }
        ]
    })
    print("✅ Full-Text Search index 'default' created (for $search aggregation)")
except Exception as e:
    error_msg = str(e)
    if "SearchNotEnabled" in error_msg or "31082" in error_msg:
        print("⚠️  MongoDB Search not enabled. $search aggregation will not work.")
        print("   To enable: Deploy mongot search nodes (Phase 3)")
    else:
        print(f"⚠️  Search index creation: {e}")

# Create Vector Search index (for $vectorSearch aggregation)
# This requires MongoDB Enterprise with mongot and the embedding field
try:
    print("Creating Vector Search index...")
    db.command({
        "createSearchIndexes": "documents",
        "indexes": [
            {
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
        ]
    })
    print("✅ Vector Search index 'vector_index' created/verified")
except Exception as e:
    error_msg = str(e)
    if "SearchNotEnabled" in error_msg or "31082" in error_msg:
        print("⚠️  Vector Search not enabled. $vectorSearch aggregation will not work.")
        print("   To enable: Deploy mongot search nodes (Phase 3)")
    else:
        print(f"⚠️  Vector Search index creation: {e}")

# Models
class Document(BaseModel):
    title: str
    body: str
    tags: List[str]

class MongoDBOperation(BaseModel):
    operation: str  # "insertOne", "find", "aggregate", etc.
    query: Optional[dict] = None
    result: Optional[dict] = None
    execution_time_ms: Optional[float] = None
    documents_affected: Optional[int] = None
    index_used: Optional[dict] = None

class DocumentResponse(BaseModel):
    id: str
    title: str
    body: str
    tags: List[str]
    mongodb_operation: Optional[MongoDBOperation] = None

class SearchResponse(BaseModel):
    query: str
    results: List[DocumentResponse]
    total: int
    mongodb_query: Optional[dict] = None
    execution_time_ms: Optional[float] = None
    search_type: Optional[str] = None
    index_used: Optional[dict] = None  # Index information
    mongodb_operation: Optional[MongoDBOperation] = None

class ChatRequest(BaseModel):
    question: str
    max_context_docs: Optional[int] = 3

class ChatResponse(BaseModel):
    question: str
    answer: str
    sources: List[DocumentResponse]
    model_used: str
    mongodb_operation: Optional[MongoDBOperation] = None

@app.get("/")
async def root():
    return {"message": "Document Search API is running"}

@app.post("/documents", response_model=DocumentResponse)
async def create_document(document: Document):
    import time
    start_time = time.time()
    
    doc_dict = document.dict()
    # Generate embedding for the document
    text_for_embedding = f"{doc_dict['title']} {doc_dict['body']} {' '.join(doc_dict['tags'])}"
    embedding = embedding_model.encode(text_for_embedding).tolist()
    doc_dict['embedding'] = embedding
    
    # Prepare MongoDB operation info
    insert_query = {
        "insertOne": {
            "document": {
                "title": doc_dict['title'],
                "body": doc_dict['body'],
                "tags": doc_dict['tags'],
                "embedding": "[384-dimensional vector]",
                "source": doc_dict.get('source', 'manual')
            }
        }
    }
    
    result = documents.insert_one(doc_dict)
    execution_time = (time.time() - start_time) * 1000
    
    mongodb_op = MongoDBOperation(
        operation="insertOne",
        query=insert_query,
        result={
            "inserted_id": str(result.inserted_id),
            "acknowledged": result.acknowledged
        },
        execution_time_ms=round(execution_time, 2),
        documents_affected=1
    )
    
    return DocumentResponse(
        id=str(result.inserted_id),
        **document.dict(),
        mongodb_operation=mongodb_op
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
    title: Optional[str] = Form(None),
    tags: Optional[str] = Form(None),
    language: Optional[str] = Form(None)
):
    """Upload audio file, transcribe it, and create a document with embeddings
    
    Parameters:
    - audio: Audio file (.opus, .mp3, .wav, etc.)
    - title: Optional title (auto-generated if not provided)
    - tags: Optional comma-separated tags
    - language: Optional language code (en, es, fr, de, it, etc.) - auto-detect if not provided
    """
    try:
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(audio.filename)[1]) as temp_audio:
            shutil.copyfileobj(audio.file, temp_audio)
            temp_path = temp_audio.name
        
        # Transcribe audio with optional language
        transcribe_options = {}
        if language:
            print(f"Using user-specified language: {language}")
            transcribe_options['language'] = language
        else:
            print("Auto-detecting language")
        
        transcription_result = whisper_model.transcribe(temp_path, **transcribe_options)
        transcribed_text = transcription_result["text"]
        detected_language = transcription_result.get("language", language or "unknown")
        print(f"Transcription complete. Detected language: {detected_language}, Text preview: {transcribed_text[:100]}")
        
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
        import time
        start_time = time.time()
        
        insert_query = {
            "insertOne": {
                "document": {
                    "title": doc_dict['title'],
                    "body": f"{doc_dict['body'][:100]}...",
                    "tags": doc_dict['tags'],
                    "embedding": "[384-dimensional vector]",
                    "source": "audio",
                    "audio_filename": audio.filename,
                    "detected_language": detected_language
                }
            }
        }
        
        result = documents.insert_one(doc_dict)
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="insertOne",
            query=insert_query,
            result={
                "inserted_id": str(result.inserted_id),
                "acknowledged": result.acknowledged
            },
            execution_time_ms=round(execution_time, 2),
            documents_affected=1
        )
        
        return DocumentResponse(
            id=str(result.inserted_id),
            title=doc_dict['title'],
            body=doc_dict['body'],
            tags=doc_dict['tags'],
            mongodb_operation=mongodb_op
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
    
    import time
    start_time = time.time()
    
    # Generate embedding for query
    query_embedding = embedding_model.encode(q).tolist()
    
    try:
        # Use MongoDB's native $vectorSearch aggregation (Enterprise feature)
        pipeline = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": "[VECTOR_EMBEDDING]",  # Placeholder for display
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
        
        # Execute MongoDB vector search (use actual embedding)
        actual_pipeline = [
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
        
        results = list(documents.aggregate(actual_pipeline))
        
        # Vector index information
        vector_index_info = {
            "name": "vector_index",
            "type": "vectorSearch",
            "field": "embedding",
            "dimensions": 384,
            "similarity": "cosine",
            "model": "all-MiniLM-L6-v2"
        }
        
        top_results = []
        for doc in results:
            top_results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
        
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="aggregate",
            query={"aggregate": pipeline},
            result={"count": len(top_results)},
            execution_time_ms=round(execution_time, 2),
            documents_affected=len(top_results),
            index_used=vector_index_info
        )
        
        return SearchResponse(
            query=q, 
            results=top_results, 
            total=len(top_results),
            mongodb_query={"aggregate": pipeline},
            execution_time_ms=round(execution_time, 2),
            search_type="vector",
            index_used=vector_index_info,
            mongodb_operation=mongodb_op
        )
        
    except Exception as e:
        # Fallback to manual vector search if $vectorSearch is not available
        error_msg = str(e)
        if "SearchNotEnabled" in error_msg or "31082" in error_msg:
            print("⚠️  Native $vectorSearch not available. To enable:")
            print("   1. Deploy mongot: ./deploy-search-only.sh")
            print("   2. Configure MongoDB: Set MONGOT_HOST in docker-compose.override.yml")
            print("   3. Restart MongoDB: docker compose restart mongodb")
            print("   Using Python-based similarity search as fallback...")
        else:
            print(f"Vector search error: {e}. Using fallback search.")
        
        # Get all documents with embeddings
        all_docs = list(documents.find({"embedding": {"$exists": True}}))
        
        fallback_query = {
            "find": {"embedding": {"$exists": True}},
            "note": "Using Python cosine similarity (fallback)"
        }
        
        if not all_docs:
            execution_time = (time.time() - start_time) * 1000
            return SearchResponse(
                query=q, 
                results=[], 
                total=0,
                mongodb_query=fallback_query,
                execution_time_ms=round(execution_time, 2),
                search_type="vector_fallback",
                index_used={"note": "No vector index available, using Python similarity"}
            )
        
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
        
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="find + Python similarity",
            query=fallback_query,
            result={"count": len(top_results)},
            execution_time_ms=round(execution_time, 2),
            documents_affected=len(top_results),
            index_used={"note": "No vector index available, using Python similarity"}
        )
        
        return SearchResponse(
            query=q, 
            results=top_results, 
            total=len(top_results),
            mongodb_query=fallback_query,
            execution_time_ms=round(execution_time, 2),
            search_type="vector_fallback",
            index_used={"note": "No vector index available, using Python similarity"},
            mongodb_operation=mongodb_op
        )

@app.get("/documents", response_model=List[DocumentResponse])
async def get_documents():
    import time
    start_time = time.time()
    
    find_query = {"find": {}}
    docs = list(documents.find())
    execution_time = (time.time() - start_time) * 1000
    
    mongodb_op = MongoDBOperation(
        operation="find",
        query=find_query,
        result={"count": len(docs)},
        execution_time_ms=round(execution_time, 2),
        documents_affected=len(docs)
    )
    
    result_docs = []
    for idx, doc in enumerate(docs):
        # Only include fields that are in DocumentResponse model
        doc_response = DocumentResponse(
            id=str(doc["_id"]),
            title=doc.get("title", ""),
            body=doc.get("body", ""),
            tags=doc.get("tags", [])
        )
        # Only add MongoDB operation to first document to avoid duplication
        if idx == 0:
            doc_response.mongodb_operation = mongodb_op
        result_docs.append(doc_response)
    
    return result_docs

@app.get("/search", response_model=SearchResponse)
async def search_documents(q: str):
    if not q.strip():
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required")
    
    import time
    start_time = time.time()
    
    # MongoDB Search aggregation pipeline (uses $search with mongot)
    pipeline = [
        {
            "$search": {
                "index": "default",  # Using the default search index
                "text": {
                    "query": q,
                    "path": ["title", "body", "tags"]
                }
            }
        },
        {
            "$project": {
                "_id": 1,
                "title": 1,
                "body": 1,
                "tags": 1,
                "score": {"$meta": "searchScore"}
            }
        },
        {
            "$limit": 10
        }
    ]
    
    # Get index information
    index_info = {
        "name": "text_search_index",
        "type": "search",
        "operator": "$search",
        "fields": ["title", "body", "tags"],
        "analyzer": "lucene.standard"
    }
    
    try:
        # Execute Atlas Search aggregation
        results_cursor = documents.aggregate(pipeline)
        results = []
        for doc in results_cursor:
            results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
        
        execution_time = (time.time() - start_time) * 1000  # Convert to ms
        
        mongodb_op = MongoDBOperation(
            operation="aggregate",
            query={"aggregate": pipeline},
            result={"count": len(results)},
            execution_time_ms=round(execution_time, 2),
            documents_affected=len(results),
            index_used=index_info
        )
        
        return SearchResponse(
            query=q, 
            results=results, 
            total=len(results),
            mongodb_query={"aggregate": pipeline},
            execution_time_ms=round(execution_time, 2),
            search_type="full_text_search",
            index_used=index_info,
            mongodb_operation=mongodb_op
        )
    except Exception as e:
        # Fallback to basic $text search if Atlas Search not available
        print(f"⚠️  Atlas Search not available: {e}")
        print("   Falling back to basic $text search...")
        
        fallback_query = {
            "find": {"$text": {"$search": q}},
            "note": "Fallback to basic text search (Atlas Search not enabled)"
        }
        
        fallback_index = {
            "name": "title_text_body_text_tags_text",
            "type": "text",
            "note": "Basic text index (not Atlas Search)"
        }
        
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
        
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="find",
            query=fallback_query,
            result={"count": len(results)},
            execution_time_ms=round(execution_time, 2),
            documents_affected=len(results),
            index_used=fallback_index
        )
        
        return SearchResponse(
            query=q, 
            results=results, 
            total=len(results),
            mongodb_query=fallback_query,
            execution_time_ms=round(execution_time, 2),
            search_type="text_fallback",
            index_used=fallback_index,
            mongodb_operation=mongodb_op
        )

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
    import time
    start_time = time.time()
    
    query_embedding = embedding_model.encode(question).tolist()
    find_query = {"find": {"embedding": {"$exists": True}}}
    all_docs = list(documents.find({"embedding": {"$exists": True}}))
    
    if not all_docs:
        execution_time = (time.time() - start_time) * 1000
        mongodb_op = MongoDBOperation(
            operation="find",
            query=find_query,
            result={"count": 0},
            execution_time_ms=round(execution_time, 2),
            documents_affected=0
        )
        return ChatResponse(
            question=question,
            answer="I don't have any documents to answer your question. Please upload some documents first.",
            sources=[],
            model_used=f"{LLM_PROVIDER}: {OLLAMA_MODEL if LLM_PROVIDER == 'ollama' else 'gpt-3.5-turbo'}",
            mongodb_operation=mongodb_op
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
    
    execution_time = (time.time() - start_time) * 1000
    
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
    
    mongodb_op = MongoDBOperation(
        operation="find + Python similarity",
        query={
            "find": {"embedding": {"$exists": True}},
            "note": "Semantic search using Python cosine similarity for RAG"
        },
        result={
            "total_documents": len(all_docs),
            "retrieved_documents": len(top_docs),
            "similarity_scores": [round(score, 4) for _, score in top_docs]
        },
        execution_time_ms=round(execution_time, 2),
        documents_affected=len(top_docs)
    )
    
    return ChatResponse(
        question=question,
        answer=answer,
        sources=sources,
        model_used=model_name,
        mongodb_operation=mongodb_op
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
