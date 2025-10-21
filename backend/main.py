from fastapi import FastAPI, HTTPException
from pymongo import MongoClient
from pydantic import BaseModel
from typing import List, Optional
import os

app = FastAPI(title="Document Search API", version="1.0.0")

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
    result = documents.insert_one(document.dict())
    return DocumentResponse(
        id=str(result.inserted_id),
        **document.dict()
    )

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
