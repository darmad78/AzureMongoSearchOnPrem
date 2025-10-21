# 🚀 One-Click Deployment Guide

Deploy the entire AI-powered search application with **one command**!

## 📦 What Gets Deployed

All services run in Docker containers:

1. **MongoDB 8.2.1** - Database with replica set
2. **Ollama** - Local LLM server (FREE, no API key needed)
3. **Backend** - FastAPI with Whisper AI, embeddings, RAG
4. **Frontend** - React UI with voice search & chat

## ⚡ Quick Start (One Command!)

```bash
docker-compose up -d
```

**That's it!** 🎉

## 📋 Prerequisites

- **Docker** & **Docker Compose** installed
- **8GB RAM minimum** (16GB recommended)
- **10GB free disk space** (for AI models)

### Install Docker

**macOS:**
```bash
brew install --cask docker
# Then open Docker Desktop
```

**Ubuntu/Linux:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in
```

**Windows:**
- Download Docker Desktop from https://www.docker.com/products/docker-desktop

## 🎯 Step-by-Step Deployment

### 1. Clone & Navigate
```bash
cd /path/to/AzureMongoSearchOnPrem
```

### 2. Deploy Everything
```bash
docker-compose up -d
```

### 3. Wait for Setup (First Time Only)
```bash
# Watch the logs
docker-compose logs -f
```

**What's happening:**
- MongoDB starts and initializes replica set (~30 seconds)
- Ollama starts and downloads llama2 model (~3.8GB, 2-5 minutes)
- Backend downloads Whisper & embedding models (~650MB, 1-2 minutes)
- Frontend installs and builds (~1 minute)

**First deployment:** 5-10 minutes  
**Subsequent starts:** 10-30 seconds

### 4. Check Status
```bash
docker-compose ps
```

You should see:
```
NAME                STATUS
mongodb-search      Up (healthy)
ollama-server       Up (healthy)
search-backend      Up
search-frontend     Up
```

### 5. Access the Application

**Frontend:** http://localhost:5173  
**Backend API:** http://localhost:8000  
**API Docs:** http://localhost:8000/docs  
**MongoDB:** localhost:27017

## 🎮 Using the Application

### Upload & Ask Questions

1. **Go to:** http://localhost:5173
2. **Upload documents:**
   - Type text manually
   - Record voice
   - Upload audio files
3. **Search:**
   - Text search
   - Semantic search (AI-powered)
4. **Ask questions:**
   - Go to chat section
   - Ask: "What are the main topics?"
   - Get AI answers with source citations!

## 🛠️ Management Commands

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f backend
docker-compose logs -f ollama
docker-compose logs -f mongodb
```

### Stop Everything
```bash
docker-compose stop
```

### Restart
```bash
docker-compose restart
```

### Stop & Remove (keeps data)
```bash
docker-compose down
```

### Stop & Remove Everything (including data)
```bash
docker-compose down -v
# ⚠️ This deletes all documents, chat history, and models!
```

### Rebuild After Code Changes
```bash
docker-compose up -d --build
```

## 🔧 Configuration

### Change LLM Model

Edit `docker-compose.yml`:

```yaml
backend:
  environment:
    OLLAMA_MODEL: mistral  # Change from llama2 to mistral
```

Available models:
- `llama2` - Default, balanced (3.8GB)
- `mistral` - Better quality (4.1GB)
- `phi` - Fastest, smaller (1.6GB)
- `llama2:13b` - Highest quality (7.3GB)

Then:
```bash
# Pull new model
docker-compose exec ollama ollama pull mistral

# Restart backend
docker-compose restart backend
```

### Change Ports

Edit `docker-compose.yml`:

```yaml
frontend:
  ports:
    - "3000:5173"  # Change 3000 to your preferred port

backend:
  ports:
    - "8080:8000"  # Change 8080 to your preferred port
```

### Use OpenAI Instead of Ollama

Edit `docker-compose.yml`:

```yaml
backend:
  environment:
    LLM_PROVIDER: openai
    OPENAI_API_KEY: sk-your-key-here
```

Remove ollama services to save resources:
```bash
docker-compose stop ollama ollama-setup
```

## 📊 Resource Usage

| Service | RAM | Disk | CPU |
|---------|-----|------|-----|
| MongoDB | ~500MB | ~1GB | Low |
| Ollama | 4-6GB | ~4GB | High (during inference) |
| Backend | 2-3GB | ~1GB | Medium |
| Frontend | ~200MB | ~500MB | Low |
| **Total** | **7-10GB** | **~6.5GB** | **Varies** |

## 🐛 Troubleshooting

### Services Won't Start

**Check Docker is running:**
```bash
docker info
```

**Check available resources:**
```bash
docker stats
```

**Check logs:**
```bash
docker-compose logs
```

### "Port already in use"

**Find what's using the port:**
```bash
# macOS/Linux
lsof -i :8000
lsof -i :5173
lsof -i :27017

# Windows
netstat -ano | findstr :8000
```

**Change ports in docker-compose.yml**

### Ollama Model Download Fails

**Check internet connection and retry:**
```bash
docker-compose restart ollama-setup
```

**Or download manually:**
```bash
docker-compose exec ollama ollama pull llama2
```

### Backend Can't Connect to MongoDB

**Wait for MongoDB to be healthy:**
```bash
docker-compose logs mongodb
```

**Restart backend:**
```bash
docker-compose restart backend
```

### Frontend Shows API Errors

**Check backend is running:**
```bash
curl http://localhost:8000
```

**Check CORS settings in backend**

### Out of Disk Space

**Clean up Docker:**
```bash
docker system prune -a --volumes
```

**Use smaller models:**
- Change `llama2` to `phi` in docker-compose.yml
- `phi` is only 1.6GB vs 3.8GB

### Slow Performance

**Reduce model size:**
- Use `phi` instead of `llama2`

**Allocate more RAM to Docker:**
- Docker Desktop → Settings → Resources → Memory (16GB recommended)

**Limit concurrent operations:**
- Don't run multiple AI operations simultaneously

## 🔒 Security Notes

### For Production:

1. **Change default passwords** in docker-compose.yml:
```yaml
mongodb:
  environment:
    MONGO_INITDB_ROOT_PASSWORD: YOUR_SECURE_PASSWORD
```

2. **Use environment variables:**
```bash
cp .env.example .env
# Edit .env with your credentials
```

3. **Enable HTTPS** (use nginx reverse proxy)

4. **Restrict network access:**
```yaml
networks:
  search-network:
    driver: bridge
    internal: true  # Add this
```

5. **Use secrets management** for API keys

### For Development:

Current setup is fine! Default passwords are only accessible locally.

## 📈 Monitoring

### Health Checks
```bash
# MongoDB
docker-compose exec mongodb mongosh --eval "db.adminCommand('ping')"

# Ollama
curl http://localhost:11434/api/version

# Backend
curl http://localhost:8000

# Frontend
curl http://localhost:5173
```

### Performance Monitoring
```bash
# Watch resource usage
docker stats

# Detailed container info
docker-compose top
```

## 🎓 Advanced Usage

### Access MongoDB Shell
```bash
docker-compose exec mongodb mongosh -u admin -p password123 --authenticationDatabase admin
```

### Access Ollama CLI
```bash
docker-compose exec ollama ollama list
docker-compose exec ollama ollama run llama2
```

### Run Backend Commands
```bash
docker-compose exec backend python -c "print('Hello from backend!')"
```

### View Backend Logs (Real-time)
```bash
docker-compose logs -f backend
```

## 🚀 Production Deployment

### Using Docker Swarm
```bash
docker swarm init
docker stack deploy -c docker-compose.yml search-app
```

### Using Kubernetes
See `deploy.sh` for Kubernetes deployment with MongoDB Enterprise.

### Cloud Deployment

**AWS ECS/Fargate:**
- Use AWS ECS with docker-compose support
- Store volumes in EFS

**Google Cloud Run:**
- Deploy each service separately
- Use Cloud SQL for MongoDB (or MongoDB Atlas)

**Azure Container Instances:**
- Use Azure Container Apps
- Connect to Azure CosmosDB MongoDB API

## 📦 Backup & Restore

### Backup
```bash
# Backup MongoDB
docker-compose exec mongodb mongodump -u admin -p password123 --authenticationDatabase admin --out /tmp/backup

# Copy to host
docker cp mongodb-search:/tmp/backup ./mongodb-backup

# Backup volumes
docker run --rm \
  -v azuremongoearchonprem_mongodb_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/mongodb-data.tar.gz /data
```

### Restore
```bash
# Copy backup to container
docker cp ./mongodb-backup mongodb-search:/tmp/backup

# Restore
docker-compose exec mongodb mongorestore -u admin -p password123 --authenticationDatabase admin /tmp/backup
```

## 🎉 Success!

Your AI-powered search application is now running with:

✅ MongoDB database  
✅ Ollama LLM (FREE, local)  
✅ Speech-to-text (Whisper AI)  
✅ Semantic search (Embeddings)  
✅ RAG Chat (Ask questions)  
✅ Beautiful web UI  

**All with ONE command:** `docker-compose up -d`

## 📞 Need Help?

- Check logs: `docker-compose logs -f`
- Read guides: `RAG_SETUP_GUIDE.md`, `SPEECH_TO_TEXT_GUIDE.md`
- Check status: `docker-compose ps`
- Restart everything: `docker-compose restart`

---

**Happy Searching! 🔍🤖**

