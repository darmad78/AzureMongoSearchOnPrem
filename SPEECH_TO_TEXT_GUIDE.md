# Speech-to-Text & Semantic Search Features

## New Features Added

### 🎤 Speech-to-Text
- **Whisper AI Integration**: Uses OpenAI's Whisper model for accurate speech recognition
- **Real-time Transcription**: Records audio and converts to text automatically
- **Visual Feedback**: Animated microphone button with recording indicators

### 🧠 Semantic Search
- **Vector Embeddings**: Uses SentenceTransformers for semantic understanding
- **Smart Search**: Finds documents by meaning, not just keywords
- **Toggle Switch**: Easy switch between text and semantic search modes

### 🎨 Modern UI
- **Gradient Designs**: Beautiful color gradients throughout
- **Smooth Animations**: Hover effects, pulse animations for recording
- **Responsive Design**: Works on desktop and mobile devices
- **Status Indicators**: Real-time feedback for recording and transcription

## Installation

### Backend Dependencies

```bash
cd backend
pip install -r requirements.txt
```

**Note**: First run will download AI models (~500MB for Whisper base model and ~100MB for sentence embeddings).

### Frontend Dependencies

```bash
cd frontend
npm install
```

## Usage

### Starting the Application

1. **Start Backend**:
   ```bash
   cd backend
   python main.py
   ```
   Backend runs on `http://localhost:8000`

2. **Start Frontend**:
   ```bash
   cd frontend
   npm run dev
   ```
   Frontend runs on `http://localhost:5173`

### Using Speech-to-Text

1. Click the **🎤 microphone button** to start recording
2. Speak your search query clearly
3. Click the **⏹️ stop button** when done
4. Wait for transcription (usually 1-2 seconds)
5. Results appear automatically

### Using Semantic Search

1. Toggle the **🧠 Semantic Search** switch
2. Enter or speak your query
3. Results are ranked by semantic similarity, not just keyword matching

## API Endpoints

### New Endpoints

- **POST `/speech-to-text`**: Upload audio file, get transcription
  - Accepts: audio file (wav, mp3, etc.)
  - Returns: `{"text": "transcribed text", "language": "en"}`

- **GET `/search/semantic?q=query`**: Semantic search using embeddings
  - Returns: Semantically similar documents ranked by similarity

### Existing Endpoints

- **GET `/`**: Health check
- **POST `/documents`**: Create document (now with automatic embeddings)
- **GET `/documents`**: List all documents
- **GET `/search?q=query`**: Traditional text search

## Browser Compatibility

- **Chrome/Edge**: Full support ✅
- **Firefox**: Full support ✅
- **Safari**: Full support ✅ (requires HTTPS for microphone on production)

**Important**: Microphone access requires either:
- `localhost` (works in development)
- HTTPS connection (required for production)

## Performance Notes

- **First startup**: 30-60 seconds (loads AI models)
- **Subsequent startups**: 10-20 seconds
- **Transcription speed**: 1-3 seconds for typical queries
- **Semantic search**: Scales with document count (optimized for <10k docs)

## Troubleshooting

### Microphone Not Working
- Check browser permissions for microphone access
- Ensure you're on `localhost` or HTTPS
- Try a different browser

### Slow Transcription
- First transcription is slower (model loading)
- Consider upgrading to `tiny` model for faster (but less accurate) results

### Models Not Loading
```bash
# Pre-download models
python -c "import whisper; whisper.load_model('base')"
python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
```

## Configuration

### Change Whisper Model Size

In `backend/main.py`, line 26:
```python
whisper_model = whisper.load_model("base")  # Options: tiny, base, small, medium, large
```

- `tiny`: Fastest, least accurate (~75MB)
- `base`: Balanced (~150MB) **[Default]**
- `small`: Better accuracy (~500MB)
- `medium`: High accuracy (~1.5GB)
- `large`: Best accuracy (~3GB)

### Change Embedding Model

In `backend/main.py`, line 28:
```python
embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
```

Other options:
- `all-mpnet-base-v2`: More accurate, slower
- `paraphrase-multilingual-MiniLM-L12-v2`: Multi-language support

## Tech Stack

- **Backend**: FastAPI, Whisper AI, SentenceTransformers
- **Frontend**: React, Modern CSS with animations
- **Database**: MongoDB with vector storage
- **AI Models**: OpenAI Whisper (speech), all-MiniLM-L6-v2 (embeddings)

## Next Steps

Consider adding:
- [ ] Audio playback of recordings
- [ ] Multi-language support UI
- [ ] Voice commands beyond search
- [ ] Speaker identification
- [ ] Real-time streaming transcription
- [ ] MongoDB Atlas Vector Search for production scale

---

**Enjoy your new AI-powered search! 🚀**

