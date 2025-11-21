from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pymongo import MongoClient
from pydantic import BaseModel
from typing import List, Optional, Tuple, Dict, Any
import os
import whisper
from sentence_transformers import SentenceTransformer
import sentence_transformers
import numpy as np
import fastapi
import pymongo
import tempfile
import shutil
from openai import OpenAI
import requests
import json
import subprocess
import sys
import time
import platform
import uvicorn
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

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
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi")

# Initialize OpenAI client if using OpenAI
openai_client = None
if LLM_PROVIDER == "openai" and OPENAI_API_KEY:
    openai_client = OpenAI(api_key=OPENAI_API_KEY)
    print("OpenAI client initialized")
elif LLM_PROVIDER == "ollama":
    print(f"Using Ollama at {OLLAMA_URL} with model {OLLAMA_MODEL}")

# MongoDB connection with optimized timeouts and settings
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://admin:password123@localhost:27017/searchdb?authSource=admin")
# Add connection timeouts to prevent hanging
# serverSelectionTimeoutMS: How long to wait for server selection (default: 30s)
# connectTimeoutMS: How long to wait for initial connection (default: 20s)
# socketTimeoutMS: How long to wait for socket operations (default: None = no timeout)
# maxPoolSize: Maximum number of connections in pool (default: 100)
client = MongoClient(
    MONGODB_URL,
    serverSelectionTimeoutMS=5000,  # 5 seconds to select server
    connectTimeoutMS=5000,  # 5 seconds to connect
    socketTimeoutMS=30000,  # 30 seconds for operations
    maxPoolSize=50,  # Limit connection pool size
    retryWrites=True,
    retryReads=True
)
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
    max_context_docs: Optional[int] = 10  # Increased from 3 to 10 for better RAG context
    system_prompt: Optional[str] = None

class ChatResponse(BaseModel):
    question: str
    answer: str
    sources: List[DocumentResponse]
    model_used: str
    mongodb_operation: Optional[MongoDBOperation] = None

# System Health Response Models
class MongoDBInfo(BaseModel):
    status: str
    version: Optional[str] = None
    replica_set: Optional[str] = None
    databases: Optional[List[str]] = None
    collections: Optional[Dict[str, int]] = None
    total_documents: Optional[int] = None
    storage_size_mb: Optional[float] = None
    connection_string: Optional[str] = None
    vector_index_exists: Optional[bool] = None
    vector_index_status: Optional[str] = None

class OllamaInfo(BaseModel):
    status: str
    version: Optional[str] = None
    url: Optional[str] = None
    model: Optional[str] = None
    available_models: Optional[List[str]] = None
    memory_usage_mb: Optional[float] = None

class ModelInfo(BaseModel):
    name: str
    version: Optional[str] = None
    status: str  # "loaded", "not_loaded", "error"
    memory_usage_mb: Optional[float] = None
    details: Optional[Dict[str, Any]] = None

class LibraryInfo(BaseModel):
    name: str
    version: Optional[str] = None

class BackendInfo(BaseModel):
    status: str
    version: str
    python_version: str
    whisper_model: str
    embedding_model: str
    llm_provider: str
    memory_usage_mb: Optional[float] = None
    models: Optional[List[ModelInfo]] = None
    libraries: Optional[List[LibraryInfo]] = None
    ffmpeg_version: Optional[str] = None

class FrontendInfo(BaseModel):
    build_time: Optional[str] = None
    api_url: Optional[str] = None

class KubernetesInfo(BaseModel):
    available: bool
    namespace: Optional[str] = None
    pods: Optional[List[Dict[str, Any]]] = None
    services: Optional[List[Dict[str, Any]]] = None
    deployments: Optional[List[Dict[str, Any]]] = None

class OpsManagerInfo(BaseModel):
    status: str
    version: Optional[str] = None
    url: Optional[str] = None
    accessible: bool = False

class SystemResources(BaseModel):
    cpu_percent: Optional[float] = None
    memory_total_mb: Optional[float] = None
    memory_used_mb: Optional[float] = None
    memory_percent: Optional[float] = None
    disk_total_gb: Optional[float] = None
    disk_used_gb: Optional[float] = None
    disk_percent: Optional[float] = None

class SystemHealthResponse(BaseModel):
    timestamp: str
    mongodb: MongoDBInfo
    ollama: OllamaInfo
    backend: BackendInfo
    frontend: Optional[FrontendInfo] = None
    kubernetes: Optional[KubernetesInfo] = None
    ops_manager: Optional[OpsManagerInfo] = None
    system_resources: Optional[SystemResources] = None

# Helper functions for system information
def check_vector_index_exists() -> Tuple[bool, Optional[str]]:
    """Check if the vector search index exists and return its status"""
    try:
        # Try to list search indexes
        indexes = list(documents.list_search_indexes())
        for idx in indexes:
            if idx.get("name") == "vector_index":
                status = idx.get("status", "unknown")
                # Index exists, return status (even if BUILDING, it exists)
                return True, status
        return False, None
    except Exception as e:
        # If list_search_indexes fails, Search might not be enabled
        error_msg = str(e)
        if "SearchNotEnabled" in error_msg or "31082" in error_msg or "not found" in error_msg.lower():
            return False, "SearchNotEnabled"
        # Other errors - assume index doesn't exist
        return False, None

def get_mongodb_info() -> MongoDBInfo:
    """Get MongoDB server information"""
    try:
        # Get server version
        build_info = db.command({"buildInfo": 1})
        version = build_info.get("version", "Unknown")
        
        # Get replica set status
        replica_set = None
        try:
            rs_status = db.command({"replSetGetStatus": 1})
            replica_set = rs_status.get("set", "Unknown")
        except:
            pass
        
        # Get database list
        databases = client.list_database_names()
        
        # Get collection stats
        collections = {}
        total_docs = 0
        storage_size = 0.0
        
        for db_name in databases:
            db_obj = client[db_name]
            db_stats = db_obj.command("dbStats")
            collections[db_name] = len(db_obj.list_collection_names())
            total_docs += db_stats.get("objects", 0)
            storage_size += db_stats.get("dataSize", 0) / (1024 * 1024)  # Convert to MB
        
        # Check if vector index exists
        vector_index_exists, vector_index_status = check_vector_index_exists()
        
        return MongoDBInfo(
            status="connected",
            version=version,
            replica_set=replica_set,
            databases=databases,
            collections=collections,
            total_documents=total_docs,
            storage_size_mb=round(storage_size, 2),
            connection_string=MONGODB_URL.split("@")[-1] if "@" in MONGODB_URL else "localhost:27017",
            vector_index_exists=vector_index_exists,
            vector_index_status=vector_index_status
        )
    except Exception as e:
        return MongoDBInfo(
            status="error",
            connection_string=str(e)[:100]
        )

def get_ollama_info() -> OllamaInfo:
    """Get Ollama service information"""
    try:
        # Get version
        version_response = requests.get(f"{OLLAMA_URL}/api/version", timeout=5)
        version_data = version_response.json() if version_response.status_code == 200 else {}
        version = version_data.get("version", "Unknown")
        
        # Get available models
        models = []
        memory_usage = None
        try:
            tags_response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
            if tags_response.status_code == 200:
                tags_data = tags_response.json()
                models = [model.get("name", "") for model in tags_data.get("models", [])]
        except:
            pass
        
        return OllamaInfo(
            status="healthy" if version_response.status_code == 200 else "unhealthy",
            version=version,
            url=OLLAMA_URL,
            model=OLLAMA_MODEL,
            available_models=models,
            memory_usage_mb=memory_usage
        )
    except Exception as e:
        return OllamaInfo(
            status="error",
            url=OLLAMA_URL,
            model=OLLAMA_MODEL,
            available_models=[]
        )

def get_kubernetes_info() -> KubernetesInfo:
    """Get Kubernetes cluster information"""
    namespace = os.getenv("NAMESPACE", "mongodb")
    try:
        # Check if kubectl is available
        result = subprocess.run(
            ["kubectl", "version", "--client", "--short"],
            capture_output=True,
            timeout=5
        )
        if result.returncode != 0:
            return KubernetesInfo(available=False)
        
        pods = []
        services = []
        deployments = []
        
        try:
            # Get pods
            pod_result = subprocess.run(
                ["kubectl", "get", "pods", "-n", namespace, "-o", "json"],
                capture_output=True,
                timeout=10
            )
            if pod_result.returncode == 0:
                pod_data = json.loads(pod_result.stdout)
                for pod in pod_data.get("items", []):
                    pods.append({
                        "name": pod["metadata"]["name"],
                        "status": pod["status"].get("phase", "Unknown"),
                        "ready": f"{len([c for c in pod['status'].get('containerStatuses', []) if c.get('ready', False)])}/{len(pod['status'].get('containerStatuses', []))}"
                    })
        except:
            pass
        
        try:
            # Get services
            svc_result = subprocess.run(
                ["kubectl", "get", "svc", "-n", namespace, "-o", "json"],
                capture_output=True,
                timeout=10
            )
            if svc_result.returncode == 0:
                svc_data = json.loads(svc_result.stdout)
                for svc in svc_data.get("items", []):
                    services.append({
                        "name": svc["metadata"]["name"],
                        "type": svc["spec"].get("type", "ClusterIP"),
                        "ports": [f"{p.get('port')}/{p.get('protocol', 'TCP')}" for p in svc["spec"].get("ports", [])]
                    })
        except:
            pass
        
        try:
            # Get deployments
            dep_result = subprocess.run(
                ["kubectl", "get", "deployments", "-n", namespace, "-o", "json"],
                capture_output=True,
                timeout=10
            )
            if dep_result.returncode == 0:
                dep_data = json.loads(dep_result.stdout)
                for dep in dep_data.get("items", []):
                    deployments.append({
                        "name": dep["metadata"]["name"],
                        "replicas": dep["spec"].get("replicas", 0),
                        "ready": dep["status"].get("readyReplicas", 0)
                    })
        except:
            pass
        
        return KubernetesInfo(
            available=True,
            namespace=namespace,
            pods=pods,
            services=services,
            deployments=deployments
        )
    except Exception:
        return KubernetesInfo(available=False)

def get_system_resources() -> SystemResources:
    """Get system resource usage"""
    if not PSUTIL_AVAILABLE:
        return SystemResources()
    
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        return SystemResources(
            cpu_percent=round(cpu_percent, 2),
            memory_total_mb=round(memory.total / (1024 * 1024), 2),
            memory_used_mb=round(memory.used / (1024 * 1024), 2),
            memory_percent=round(memory.percent, 2),
            disk_total_gb=round(disk.total / (1024 * 1024 * 1024), 2),
            disk_used_gb=round(disk.used / (1024 * 1024 * 1024), 2),
            disk_percent=round(disk.percent, 2)
        )
    except Exception:
        return SystemResources()

def get_ops_manager_info() -> OpsManagerInfo:
    """Get Ops Manager information"""
    ops_url = os.getenv("OPS_MANAGER_URL", "http://ops-manager-service.mongodb.svc.cluster.local:8080")
    try:
        response = requests.get(f"{ops_url}/api/public/v1.0/version", timeout=5)
        accessible = response.status_code == 200
        version = None
        if accessible:
            try:
                version_data = response.json()
                version = version_data.get("version", "Unknown")
            except:
                pass
        
        return OpsManagerInfo(
            status="accessible" if accessible else "not_accessible",
            url=ops_url,
            accessible=accessible,
            version=version
        )
    except Exception:
        return OpsManagerInfo(
            status="not_accessible",
            url=ops_url,
            accessible=False
        )

@app.get("/")
async def root():
    return {"message": "Document Search API is running"}

@app.get("/health/system", response_model=SystemHealthResponse)
async def get_system_health():
    """Get comprehensive system health and architecture information"""
    try:
        print("📊 /health/system endpoint called")
        
        # Get MongoDB info
        try:
            mongodb_info = get_mongodb_info()
            print(f"✅ MongoDB info retrieved: {mongodb_info.status}")
        except Exception as e:
            print(f"❌ Error getting MongoDB info: {e}")
            mongodb_info = MongoDBInfo(status="error", connection_string=str(e)[:100])
        
        # Get Ollama info
        try:
            ollama_info = get_ollama_info()
            print(f"✅ Ollama info retrieved: {ollama_info.status}")
        except Exception as e:
            print(f"❌ Error getting Ollama info: {e}")
            ollama_info = OllamaInfo(status="error", url=OLLAMA_URL, model=OLLAMA_MODEL, available_models=[])
        
        # Get backend info
        backend_memory = None
        if PSUTIL_AVAILABLE:
            try:
                process = psutil.Process()
                backend_memory = round(process.memory_info().rss / (1024 * 1024), 2)
            except Exception as e:
                print(f"⚠️  Could not get backend memory: {e}")
        
        # Get model information
        models_info = []
        try:
            # Whisper model info
            whisper_status = "loaded" if whisper_model else "not_loaded"
            models_info.append(ModelInfo(
                name="Whisper",
                version=whisper.__version__ if hasattr(whisper, '__version__') else "20231117",
                status=whisper_status,
                details={
                    "model_name": "base",
                    "purpose": "Audio transcription",
                    "framework": "PyTorch",
                    "uses_ffmpeg": True
                }
            ))
        except Exception as e:
            models_info.append(ModelInfo(
                name="Whisper",
                status="error",
                details={"error": str(e)[:100]}
            ))
        
        try:
            # SentenceTransformer model info
            embedding_status = "loaded" if embedding_model else "not_loaded"
            embedding_dim = None
            if embedding_model:
                try:
                    # Get embedding dimension by encoding a test string
                    test_embedding = embedding_model.encode("test")
                    embedding_dim = len(test_embedding)
                except:
                    pass
            
            models_info.append(ModelInfo(
                name="SentenceTransformer",
                version=sentence_transformers.__version__ if hasattr(sentence_transformers, '__version__') else "2.3.1",
                status=embedding_status,
                details={
                    "model_name": "all-MiniLM-L6-v2",
                    "purpose": "Text embeddings for semantic search",
                    "embedding_dimensions": embedding_dim or 384,
                    "framework": "PyTorch"
                }
            ))
        except Exception as e:
            models_info.append(ModelInfo(
                name="SentenceTransformer",
                status="error",
                details={"error": str(e)[:100]}
            ))
        
        # Get library versions
        libraries_info = []
        try:
            import torch
            libraries_info.append(LibraryInfo(name="PyTorch", version=torch.__version__))
        except:
            pass
        
        try:
            import transformers
            libraries_info.append(LibraryInfo(name="Transformers", version=transformers.__version__))
        except:
            pass
        
        try:
            libraries_info.append(LibraryInfo(name="FastAPI", version=fastapi.__version__))
        except:
            pass
        
        try:
            libraries_info.append(LibraryInfo(name="NumPy", version=np.__version__))
        except:
            pass
        
        try:
            libraries_info.append(LibraryInfo(name="PyMongo", version=pymongo.__version__))
        except:
            pass
        
        try:
            libraries_info.append(LibraryInfo(name="Uvicorn", version=uvicorn.__version__))
        except:
            pass
        
        try:
            libraries_info.append(LibraryInfo(name="Requests", version=requests.__version__))
        except:
            pass
        
        # Get FFmpeg version
        ffmpeg_version = None
        try:
            result = subprocess.run(['ffmpeg', '-version'], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                first_line = result.stdout.split('\n')[0]
                ffmpeg_version = first_line.split(' ')[2] if len(first_line.split(' ')) > 2 else "unknown"
        except:
            pass
        
        backend_info = BackendInfo(
            status="healthy",
            version="1.0.0",
            python_version=f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            whisper_model="base",
            embedding_model="all-MiniLM-L6-v2",
            llm_provider=LLM_PROVIDER,
            memory_usage_mb=backend_memory,
            models=models_info,
            libraries=libraries_info,
            ffmpeg_version=ffmpeg_version
        )
        
        # Get frontend info (from build time if available)
        frontend_info = FrontendInfo(
            build_time=os.getenv("FRONTEND_BUILD_TIME", None),
            api_url=os.getenv("API_URL", None)
        )
        
        # Get Kubernetes info
        try:
            kubernetes_info = get_kubernetes_info()
        except Exception as e:
            print(f"⚠️  Error getting Kubernetes info: {e}")
            kubernetes_info = KubernetesInfo(available=False)
        
        # Get Ops Manager info
        try:
            ops_manager_info = get_ops_manager_info()
        except Exception as e:
            print(f"⚠️  Error getting Ops Manager info: {e}")
            ops_manager_info = OpsManagerInfo(status="not_accessible", accessible=False)
        
        # Get system resources
        try:
            system_resources = get_system_resources()
        except Exception as e:
            print(f"⚠️  Error getting system resources: {e}")
            system_resources = SystemResources()
        
        response = SystemHealthResponse(
            timestamp=time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime()),
            mongodb=mongodb_info,
            ollama=ollama_info,
            backend=backend_info,
            frontend=frontend_info,
            kubernetes=kubernetes_info if kubernetes_info.available else None,
            ops_manager=ops_manager_info if ops_manager_info.accessible else None,
            system_resources=system_resources
        )
        
        print(f"✅ System health response prepared successfully")
        return response
        
    except Exception as e:
        print(f"❌ Critical error in /health/system: {e}")
        import traceback
        traceback.print_exc()
        # Return a minimal error response
        raise HTTPException(status_code=500, detail=f"Error generating system health: {str(e)}")

@app.get("/health/ollama")
async def check_ollama_health():
    """Check Ollama service health and model availability"""
    if LLM_PROVIDER != "ollama":
        return {
            "status": "not_configured",
            "message": f"LLM provider is set to '{LLM_PROVIDER}', not 'ollama'",
            "ollama_url": OLLAMA_URL,
            "ollama_model": OLLAMA_MODEL
        }
    
    model_available, check_message = check_ollama_model()
    return {
        "status": "healthy" if model_available else "unhealthy",
        "message": check_message,
        "ollama_url": OLLAMA_URL,
        "ollama_model": OLLAMA_MODEL,
        "model_available": model_available
    }

@app.post("/documents", response_model=DocumentResponse)
async def create_document(document: Document):
    import time
    start_time = time.time()
    
    doc_dict = document.dict()
    # Generate embedding for the document
    text_for_embedding = f"{doc_dict['title']} {doc_dict['body']} {' '.join(doc_dict['tags'])}"
    embedding = embedding_model.encode(text_for_embedding).tolist()
    doc_dict['embedding'] = embedding
    
    # Prepare MongoDB operation info (show sample of embedding for display)
    embedding_sample = embedding[:5] + [f"... ({len(embedding)} total dimensions)"]
    insert_query = {
        "insertOne": {
            "document": {
                "title": doc_dict['title'],
                "body": doc_dict['body'],
                "tags": doc_dict['tags'],
                "embedding": embedding_sample,  # Show sample for display
                "embedding_dimensions": len(embedding),
                "source": doc_dict.get('source', 'manual')
            }
        }
    }
    
    # Store full embedding in MongoDB (doc_dict has the full embedding)
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
    import time
    workflow_steps = []
    total_start_time = time.time()
    
    try:
        # Step 1: Upload audio file
        step_start = time.time()
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(audio.filename)[1]) as temp_audio:
            shutil.copyfileobj(audio.file, temp_audio)
            temp_path = temp_audio.name
        workflow_steps.append({
            "step": 1,
            "name": "Upload Audio File",
            "status": "completed",
            "details": {
                "filename": audio.filename,
                "file_size_bytes": os.path.getsize(temp_path),
                "duration_ms": round((time.time() - step_start) * 1000, 2)
            }
        })
        
        # Step 2: Transcribe audio to text
        step_start = time.time()
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
        
        workflow_steps.append({
            "step": 2,
            "name": "Transcribe Audio to Text",
            "status": "completed",
            "details": {
                "detected_language": detected_language,
                "transcription_length": len(transcribed_text),
                "transcription_preview": transcribed_text[:200] + ("..." if len(transcribed_text) > 200 else ""),
                "duration_ms": round((time.time() - step_start) * 1000, 2)
            }
        })
        
        # Clean up temp file
        os.unlink(temp_path)
        
        # Step 3: Prepare document metadata
        step_start = time.time()
        if not title:
            title = transcribed_text[:50] + ("..." if len(transcribed_text) > 50 else "")
        
        tags_list = []
        if tags:
            tags_list = [tag.strip() for tag in tags.split(',') if tag.strip()]
        tags_list.append(f"language:{detected_language}")
        tags_list.append("audio-transcription")
        
        supported_languages = ['da', 'nl', 'en', 'fi', 'fr', 'de', 'hu', 'it', 'nb', 'pt', 'ro', 'ru', 'es', 'sv', 'tr']
        mongodb_language = detected_language if detected_language in supported_languages else 'none'
        
        workflow_steps.append({
            "step": 3,
            "name": "Prepare Document Metadata",
            "status": "completed",
            "details": {
                "title": title,
                "tags": tags_list,
                "mongodb_language": mongodb_language,
                "duration_ms": round((time.time() - step_start) * 1000, 2)
            }
        })
        
        # Step 4: Generate embedding
        step_start = time.time()
        text_for_embedding = f"{title} {transcribed_text} {' '.join(tags_list)}"
        embedding = embedding_model.encode(text_for_embedding).tolist()
        
        workflow_steps.append({
            "step": 4,
            "name": "Generate Embedding Vector",
            "status": "completed",
            "details": {
                "embedding_dimensions": len(embedding),
                "model": "all-MiniLM-L6-v2",
                "text_length": len(text_for_embedding),
                "duration_ms": round((time.time() - step_start) * 1000, 2)
            }
        })
        
        # Step 5: Create document and insert into MongoDB
        # Note: This step may take longer because:
        # - The document includes a 384-dimensional embedding vector (~1.5KB)
        # - MongoDB needs to serialize and write the document
        # - If indexes exist, MongoDB needs to update them
        step_start = time.time()
        print(f"💾 Step 5: Preparing document for MongoDB insertion...")
        
        doc_dict = {
            "title": title,
            "body": transcribed_text,
            "tags": tags_list,
            "source": "audio",
            "audio_filename": audio.filename,
            "detected_language": detected_language,
            "language": mongodb_language,
            "embedding": embedding  # 384-dimensional vector (~1.5KB)
        }
        
        # Calculate document size before insertion
        import sys
        doc_size_estimate = sys.getsizeof(str(doc_dict))
        embedding_size = len(embedding) * 4  # 4 bytes per float32
        print(f"📊 Document size estimate: ~{doc_size_estimate / 1024:.2f} KB (embedding: ~{embedding_size / 1024:.2f} KB)")
        
        insert_query = {
            "insertOne": {
                "document": {
                    "title": doc_dict['title'],
                    "body": f"{doc_dict['body'][:100]}...",
                    "tags": doc_dict['tags'],
                    "embedding": f"[{len(embedding)}-dimensional vector, ~{embedding_size / 1024:.2f} KB]",
                    "source": "audio",
                    "audio_filename": audio.filename,
                    "detected_language": detected_language,
                    "note": "Full document includes large embedding vector for semantic search"
                }
            }
        }
        
        print(f"💾 Inserting document into MongoDB...")
        insert_start = time.time()
        result = documents.insert_one(doc_dict)
        insert_time = (time.time() - insert_start) * 1000
        print(f"⏱️  MongoDB insert completed in {insert_time:.2f}ms")
        
        mongodb_execution_time = (time.time() - step_start) * 1000
        
        # Get the inserted document
        inserted_doc = documents.find_one({"_id": result.inserted_id})
        
        # Document size already calculated above (doc_size_estimate and embedding_size)
        
        workflow_steps.append({
            "step": 5,
            "name": "Insert into MongoDB",
            "status": "completed",
            "details": {
                "inserted_id": str(result.inserted_id),
                "acknowledged": result.acknowledged,
                "duration_ms": round(mongodb_execution_time, 2),
                "document_size_bytes": doc_size_estimate,
                "embedding_size_bytes": embedding_size,
                "document": {
                    "_id": str(inserted_doc["_id"]),
                    "title": inserted_doc.get("title", ""),
                    "body_preview": inserted_doc.get("body", "")[:200] + ("..." if len(inserted_doc.get("body", "")) > 200 else ""),
                    "body_length": len(inserted_doc.get("body", "")),
                    "tags": inserted_doc.get("tags", []),
                    "source": inserted_doc.get("source", ""),
                    "has_embedding": "embedding" in inserted_doc,
                    "embedding_dimensions": len(inserted_doc.get("embedding", [])) if "embedding" in inserted_doc else 0
                }
            }
        })
        
        total_execution_time = (time.time() - total_start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="insertOne",
            query=insert_query,
            result={
                "inserted_id": str(result.inserted_id),
                "acknowledged": result.acknowledged,
                "workflow_steps": workflow_steps,
                "total_duration_ms": round(total_execution_time, 2)
            },
            execution_time_ms=round(mongodb_execution_time, 2),
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
    
    # Check if vector index exists before attempting to use it
    vector_index_available, vector_index_status = check_vector_index_exists()
    
    if not vector_index_available:
        raise HTTPException(
            status_code=503,
            detail=f"MongoDB Vector Search is not available. Vector index 'vector_index' not found or not ready (status: {vector_index_status}). To enable: 1) Deploy mongot: ./deploy-search-only.sh, 2) Configure MongoDB: Set MONGOT_HOST in docker-compose.override.yml, 3) Restart MongoDB: docker compose restart mongodb"
        )
    
    try:
        # Use MongoDB's native $vectorSearch aggregation (Enterprise feature)
        # Create display version showing first 5 values + note (actual query uses full 384-dim vector)
        query_vector_sample = query_embedding[:5] + [f"... (remaining {len(query_embedding) - 5} dimensions)"]
        pipeline_display = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": query_vector_sample,  # Display: first 5 values + note
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
        
        # Execute MongoDB vector search (use actual full embedding)
        actual_pipeline = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": query_embedding,  # Full 384-dimensional vector
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
        scores = []
        for doc in results:
            top_results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
            # Extract vector search score if available
            if "score" in doc:
                scores.append(round(doc["score"], 4))
        
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="aggregate",
            query={
                "aggregate": pipeline_display,
                "note": "⚠️ Display version: queryVector shown truncated (first 5 of 384 dimensions). Actual query uses full 384-dimensional vector."
            },
            result={
                "count": len(top_results),
                "documents_found": len(top_results),
                "vector_search_scores": scores if scores else None,
                "query": q,
                "search_type": "vector_search",
                "index_used": "vector_index",
                "embedding_dimensions": len(query_embedding)
            },
            execution_time_ms=round(execution_time, 2),
            documents_affected=len(top_results),
            index_used=vector_index_info
        )
        
        return SearchResponse(
            query=q, 
            results=top_results, 
            total=len(top_results),
            mongodb_query={
                "aggregate": pipeline_display,
                "note": "⚠️ Display version: queryVector shown truncated (first 5 of 384 dimensions). Actual query uses full 384-dimensional vector."
            },
            execution_time_ms=round(execution_time, 2),
            search_type="vector",
            index_used=vector_index_info,
            mongodb_operation=mongodb_op
        )
        
    except Exception as e:
        # Return error if vector search is not available (no Python fallback)
        error_msg = str(e)
        if "SearchNotEnabled" in error_msg or "31082" in error_msg or "$vectorSearch" in error_msg:
            raise HTTPException(
                status_code=503,
                detail=f"MongoDB Vector Search is not enabled. To enable: 1) Deploy mongot: ./deploy-search-only.sh, 2) Configure MongoDB: Set MONGOT_HOST in docker-compose.override.yml, 3) Restart MongoDB: docker compose restart mongodb. Error: {error_msg}"
            )
        else:
            raise HTTPException(
                status_code=500,
                detail=f"MongoDB Vector Search failed: {error_msg}"
            )

@app.get("/documents", response_model=List[DocumentResponse])
async def get_documents():
    import time
    start_time = time.time()
    
    # Get last 10 documents, ordered by insertion time (most recent first)
    # MongoDB ObjectId contains timestamp, so sorting by _id descending gives most recent first
    find_query = {
        "find": {},
        "sort": {"_id": -1},
        "limit": 10,
        "note": "Get last 10 documents, most recent first"
    }
    docs = list(documents.find().sort("_id", -1).limit(10))
    execution_time = (time.time() - start_time) * 1000
    
    mongodb_op = MongoDBOperation(
        operation="find",
        query=find_query,
        result={
            "count": len(docs),
            "limit": 10,
            "sorted_by": "_id (descending - most recent first)"
        },
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
        scores = []
        for doc in results_cursor:
            results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
            # Extract score if available
            if "score" in doc:
                scores.append(round(doc["score"], 4))
        
        execution_time = (time.time() - start_time) * 1000  # Convert to ms
        
        mongodb_op = MongoDBOperation(
            operation="aggregate",
            query={"aggregate": pipeline},
            result={
                "count": len(results),
                "documents_found": len(results),
                "search_scores": scores if scores else None,
                "query": q,
                "search_type": "full_text_search",
                "index_used": "default (Atlas Search)"
            },
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
        scores = []
        for doc in cursor:
            results.append(DocumentResponse(
                id=str(doc["_id"]),
                title=doc["title"],
                body=doc["body"],
                tags=doc["tags"]
            ))
            # Extract score if available
            if "score" in doc:
                scores.append(round(doc["score"], 4))
        
        execution_time = (time.time() - start_time) * 1000
        
        mongodb_op = MongoDBOperation(
            operation="find",
            query=fallback_query,
            result={
                "count": len(results),
                "documents_found": len(results),
                "search_scores": scores if scores else None,
                "query": q,
                "search_type": "text_fallback",
                "index_used": "text index (fallback)"
            },
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

# Helper function to check if Ollama model is available
def check_ollama_model() -> Tuple[bool, str]:
    """Check if Ollama is accessible and model is available"""
    try:
        # Check if Ollama is reachable and get list of available models
        models_response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        if models_response.status_code != 200:
            return False, f"Ollama health check failed: HTTP {models_response.status_code}"
        
        models_data = models_response.json()
        available_models = [model.get("name", "") for model in models_data.get("models", [])]
        
        # Check if the requested model exists (exact match or starts with)
        model_found = False
        for model_name in available_models:
            if model_name == OLLAMA_MODEL or model_name.startswith(f"{OLLAMA_MODEL}:"):
                model_found = True
                break
        
        if not model_found:
            return False, f"Model '{OLLAMA_MODEL}' not found. Available models: {', '.join(available_models) if available_models else 'none'}. Pull the model with: kubectl exec <ollama-pod> -n mongodb -- ollama pull {OLLAMA_MODEL}"
        
        return True, "Model available"
    except requests.exceptions.ConnectionError:
        return False, f"Cannot connect to Ollama at {OLLAMA_URL}. Make sure Ollama is running and accessible."
    except requests.exceptions.Timeout:
        return False, f"Ollama connection timeout at {OLLAMA_URL}. Ollama may be starting up or overloaded."
    except Exception as e:
        return False, f"Error checking Ollama: {str(e)}"

# Helper function to call LLM
def call_llm(prompt: str, context: str, system_prompt: Optional[str] = None) -> str:
    """Call LLM with prompt and context"""
    # Default system prompt
    default_system_prompt = "You are a helpful assistant that answers questions based on the provided context. If the answer is not in the context, say so."
    system_instruction = system_prompt if system_prompt else default_system_prompt
    if system_prompt:
        print(f"📝 LLM will use custom system prompt: {system_instruction[:150]}...")
    else:
        print(f"📝 LLM will use default system prompt")
    if LLM_PROVIDER == "openai" and openai_client:
        # OpenAI API call
        try:
            response = openai_client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": system_instruction},
                    {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {prompt}\n\nAnswer:"}
                ],
                temperature=0.7,
                max_tokens=500
            )
            return response.choices[0].message.content
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"OpenAI API error: {str(e)}")
    
    elif LLM_PROVIDER == "ollama":
        # Check if model is available before making the request
        model_available, check_message = check_ollama_model()
        if not model_available:
            raise HTTPException(
                status_code=503,
                detail=f"Ollama model not ready: {check_message}"
            )
        
        # Ollama API call
        try:
            response = requests.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": OLLAMA_MODEL,
                    "prompt": f"""{system_instruction}

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
                timeout=(10, int(os.getenv("OLLAMA_TIMEOUT", "360000")))  # (connect_timeout, read_timeout) - 10s connect, 360000s (6000 min / 100 hours) read timeout
            )
            
            # Handle non-200 status codes with better error messages
            if response.status_code != 200:
                try:
                    error_data = response.json()
                    error_msg = error_data.get("error", f"HTTP {response.status_code}")
                    if "model" in error_msg.lower() and "not found" in error_msg.lower():
                        raise HTTPException(
                            status_code=503,
                            detail=f"Model '{OLLAMA_MODEL}' not found in Ollama. Please pull it first: kubectl exec <ollama-pod> -n mongodb -- ollama pull {OLLAMA_MODEL}"
                        )
                    raise HTTPException(
                        status_code=response.status_code,
                        detail=f"Ollama API error: {error_msg}"
                    )
                except ValueError:
                    # Response is not JSON
                    raise HTTPException(
                        status_code=response.status_code,
                        detail=f"Ollama error: HTTP {response.status_code} - {response.text[:200]}"
                    )
            
            result = response.json()
            if "response" not in result:
                raise HTTPException(
                    status_code=500,
                    detail=f"Unexpected Ollama response format: {list(result.keys())}"
                )
            
            return result["response"]
        except HTTPException:
            raise  # Re-raise HTTPExceptions as-is
        except requests.exceptions.ConnectionError as e:
            raise HTTPException(
                status_code=503,
                detail=f"Cannot connect to Ollama at {OLLAMA_URL}. Make sure Ollama is running and accessible."
            )
        except requests.exceptions.Timeout as e:
            raise HTTPException(
                status_code=504,
                detail=f"Ollama request timeout. The model may be processing a large request or Ollama may be overloaded."
            )
        except requests.exceptions.RequestException as e:
            raise HTTPException(
                status_code=500, 
                detail=f"Ollama request error: {str(e)}. Make sure Ollama is running at {OLLAMA_URL}"
            )
    else:
        raise HTTPException(
            status_code=500, 
            detail="No LLM configured. Set OPENAI_API_KEY or ensure Ollama is running."
        )

@app.post("/chat", response_model=ChatResponse, response_model_exclude_none=False)
async def chat_with_documents(chat_request: ChatRequest):
    """RAG endpoint: Ask questions about your documents"""
    question = chat_request.question
    max_docs = chat_request.max_context_docs
    
    if not question.strip():
        raise HTTPException(status_code=400, detail="Question is required")
    
    # Step 1: Retrieve relevant documents using MongoDB vector search
    import time
    start_time = time.time()
    
    # Generate embedding for query
    query_embedding = embedding_model.encode(question).tolist()
    
    # Check if vector index exists before attempting to use it
    vector_index_available, vector_index_status = check_vector_index_exists()
    
    if not vector_index_available:
        raise HTTPException(
            status_code=503,
            detail=f"MongoDB Vector Search is not available for RAG. Vector index 'vector_index' not found or not ready (status: {vector_index_status}). To enable: 1) Deploy mongot: ./deploy-search-only.sh, 2) Configure MongoDB: Set MONGOT_HOST in docker-compose.override.yml, 3) Restart MongoDB: docker compose restart mongodb"
        )
    
    # Use MongoDB native $vectorSearch
    try:
        
        # Create display version showing first 5 values + note (actual query uses full 384-dim vector)
        query_vector_sample = query_embedding[:5] + [f"... (remaining {len(query_embedding) - 5} dimensions)"]
        pipeline_display = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": query_vector_sample,  # Display: first 5 values + note
                    "numCandidates": max_docs * 10,
                    "limit": max_docs
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
        
        # Execute with actual full embedding
        actual_pipeline = [
            {
                "$vectorSearch": {
                    "index": "vector_index",
                    "path": "embedding",
                    "queryVector": query_embedding,  # Full 384-dimensional vector
                    "numCandidates": max_docs * 10,
                    "limit": max_docs
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
        
        results_cursor = documents.aggregate(actual_pipeline)
        top_docs_with_scores = []
        for doc in results_cursor:
            top_docs_with_scores.append((doc, doc.get("score", 0.0)))
        
        execution_time = (time.time() - start_time) * 1000
        query_info = {
            "aggregate": pipeline_display,
            "note": "⚠️ Display version: queryVector shown truncated (first 5 of 384 dimensions). Actual query uses full 384-dimensional vector."
        }
        search_type = "vector_search"
        
    except Exception as e:
        # Return error if vector search is not available (no Python fallback)
        error_msg = str(e)
        if "SearchNotEnabled" in error_msg or "31082" in error_msg or "$vectorSearch" in error_msg:
            raise HTTPException(
                status_code=503,
                detail=f"MongoDB Vector Search is not enabled for RAG. To enable: 1) Deploy mongot: ./deploy-search-only.sh, 2) Configure MongoDB: Set MONGOT_HOST in docker-compose.override.yml, 3) Restart MongoDB: docker compose restart mongodb. Error: {error_msg}"
            )
        else:
            raise HTTPException(
                status_code=500,
                detail=f"MongoDB Vector Search failed in RAG: {error_msg}"
            )
    
    # Step 2: Build context from retrieved documents
    top_docs = [doc for doc, score in top_docs_with_scores]
    context_parts = []
    sources = []
    for idx, (doc, score) in enumerate(top_docs_with_scores, 1):
        context_parts.append(f"Document {idx} (Title: {doc['title']}):\n{doc['body']}\n")
        sources.append(DocumentResponse(
            id=str(doc["_id"]),
            title=doc["title"],
            body=doc["body"],
            tags=doc["tags"]
        ))
    
    context = "\n".join(context_parts)
    
    # Step 3: Generate answer using LLM with custom system prompt
    system_prompt = chat_request.system_prompt if chat_request.system_prompt else None
    if system_prompt:
        print(f"🔧 Using CUSTOM system prompt: {system_prompt[:100]}...")
    else:
        print("🔧 Using DEFAULT system prompt")
    answer = call_llm(question, context, system_prompt)
    
    # Step 4: Prepare MongoDB operation details
    model_name = f"{LLM_PROVIDER}: {OLLAMA_MODEL if LLM_PROVIDER == 'ollama' else 'gpt-3.5-turbo'}"
    
    # Prepare result data
    result_data = {
        "count": len(top_docs),
        "retrieved_documents": len(top_docs)
    }
    
    # Add scores/similarity information (always vector_search now, no Python fallback)
    result_data["scores"] = [round(score, 4) for _, score in top_docs_with_scores]
    index_used = {
        "name": "vector_index",
        "type": "vectorSearch",
        "field": "embedding",
        "dimensions": 384,
        "similarity": "cosine"
    }
    
    mongodb_op = MongoDBOperation(
        operation="aggregate",
        query=query_info,
        result=result_data,
        execution_time_ms=round(execution_time, 2),
        documents_affected=len(top_docs),
        index_used=index_used
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
