import React, { useState, useEffect, useRef } from 'react';
import './App.css';

// Determine API URL: use env var, or construct from current location
const getApiUrl = () => {
  // Allow override via environment variable
  if (import.meta.env.VITE_API_URL) {
    return import.meta.env.VITE_API_URL;
  }
  
  // Otherwise construct dynamically
  const hostname = window.location.hostname;
  const protocol = window.location.protocol;
  return `${protocol}//${hostname}:30888`;
};
const API_URL = getApiUrl();
console.log('Frontend API_URL:', API_URL);
console.log('VITE_API_URL env:', import.meta.env.VITE_API_URL);
console.log('Window location:', window.location.href);

function App() {
  const [documents, setDocuments] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [newDoc, setNewDoc] = useState({ title: '', body: '', tags: '' });
  const [isSearching, setIsSearching] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [useSemanticSearch, setUseSemanticSearch] = useState(false);
  const [queryDetails, setQueryDetails] = useState(null);
  const [audioFile, setAudioFile] = useState(null);
  const [audioTitle, setAudioTitle] = useState('');
  const [audioTags, setAudioTags] = useState('');
  const [audioLanguage, setAudioLanguage] = useState('');
  const [isUploadingAudio, setIsUploadingAudio] = useState(false);
  const [uploadStatus, setUploadStatus] = useState('');
  const [chatQuestion, setChatQuestion] = useState('');
  const [chatHistory, setChatHistory] = useState([]);
  const [isAsking, setIsAsking] = useState(false);
  // MongoDB operation details for each operation type
  const [mongodbOps, setMongodbOps] = useState({
    createDocument: null,
    uploadAudio: null,
    chat: null,
    fetchDocuments: null
  });
  const mediaRecorderRef = useRef(null);
  const audioChunksRef = useRef([]);
  const chatEndRef = useRef(null);
  
  // Collapsible sections state
  const [expandedSections, setExpandedSections] = useState({
    addDocument: false,
    search: true,
    chat: false,
    documents: true  // Expanded by default to show documents
  });
  const [isLoadingDocuments, setIsLoadingDocuments] = useState(true);
  
  const toggleSection = (section) => {
    setExpandedSections(prev => ({
      ...prev,
      [section]: !prev[section]
    }));
  };

  // MongoDB Operation Details Component
  const MongoDBOperationDetails = ({ operation, title }) => {
    if (!operation) return null;
    
    return (
      <div className="mongodb-operation-box" style={{
        marginTop: '15px',
        padding: '15px',
        backgroundColor: '#f8f9fa',
        border: '1px solid #dee2e6',
        borderRadius: '8px',
        fontSize: '0.9em'
      }}>
        <h4 style={{ marginTop: 0, marginBottom: '10px', color: '#495057' }}>
          🗄️ MongoDB Operation: {title}
        </h4>
        <div style={{ marginBottom: '10px' }}>
          <strong>Operation:</strong> <span style={{ 
            backgroundColor: '#007bff', 
            color: 'white', 
            padding: '2px 8px', 
            borderRadius: '4px',
            fontSize: '0.85em'
          }}>{operation.operation}</span>
        </div>
        {operation.execution_time_ms && (
          <div style={{ marginBottom: '10px' }}>
            <strong>Execution Time:</strong> {operation.execution_time_ms}ms
          </div>
        )}
        {operation.documents_affected !== null && operation.documents_affected !== undefined && (
          <div style={{ marginBottom: '10px' }}>
            <strong>Documents Affected:</strong> {operation.documents_affected}
          </div>
        )}
        {operation.query && (
          <div style={{ marginBottom: '10px' }}>
            <strong>Query:</strong>
            <pre style={{ 
              backgroundColor: '#fff', 
              padding: '10px', 
              borderRadius: '4px',
              overflow: 'auto',
              fontSize: '0.85em',
              marginTop: '5px'
            }}>
              {JSON.stringify(operation.query, null, 2)}
            </pre>
          </div>
        )}
        {operation.result && (
          <div style={{ marginBottom: '10px' }}>
            <strong>Result:</strong>
            <pre style={{ 
              backgroundColor: '#fff', 
              padding: '10px', 
              borderRadius: '4px',
              overflow: 'auto',
              fontSize: '0.85em',
              marginTop: '5px'
            }}>
              {JSON.stringify(operation.result, null, 2)}
            </pre>
          </div>
        )}
        {operation.index_used && (
          <div style={{ marginBottom: '10px' }}>
            <strong>Index Used:</strong>
            <pre style={{ 
              backgroundColor: '#e7f3ff', 
              padding: '10px', 
              borderRadius: '4px',
              overflow: 'auto',
              fontSize: '0.85em',
              marginTop: '5px'
            }}>
              {JSON.stringify(operation.index_used, null, 2)}
            </pre>
          </div>
        )}
      </div>
    );
  };

  // Fetch all documents
  const fetchDocuments = async () => {
    setIsLoadingDocuments(true);
    try {
      const url = `${API_URL}/documents`;
      console.log('Fetching documents from:', url);
      const response = await fetch(url);
      
      if (!response.ok) {
        const errorText = await response.text();
        console.error(`Failed to fetch documents: ${response.status} ${response.statusText}`, errorText);
        alert(`Failed to load documents: ${response.status} ${response.statusText}`);
        setIsLoadingDocuments(false);
        return;
      }
      
      const data = await response.json();
      console.log(`Successfully fetched ${data.length} documents`);
      setDocuments(data);
      // Capture MongoDB operation from first document (if available)
      if (data.length > 0 && data[0].mongodb_operation) {
        setMongodbOps(prev => ({ ...prev, fetchDocuments: data[0].mongodb_operation }));
      }
    } catch (error) {
      console.error('Error fetching documents:', error);
      alert(`Error fetching documents: ${error.message}. Check console for details.`);
    } finally {
      setIsLoadingDocuments(false);
    }
  };

  // Start recording audio
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      mediaRecorderRef.current = new MediaRecorder(stream);
      audioChunksRef.current = [];

      mediaRecorderRef.current.ondataavailable = (event) => {
        audioChunksRef.current.push(event.data);
      };

      mediaRecorderRef.current.onstop = async () => {
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/wav' });
        await transcribeAudio(audioBlob);
        stream.getTracks().forEach(track => track.stop());
      };

      mediaRecorderRef.current.start();
      setIsRecording(true);
    } catch (error) {
      console.error('Error accessing microphone:', error);
      alert('Could not access microphone. Please check permissions.');
    }
  };

  // Stop recording audio
  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
    }
  };

  // Transcribe audio using backend
  const transcribeAudio = async (audioBlob) => {
    setIsTranscribing(true);
    try {
      const formData = new FormData();
      formData.append('audio', audioBlob, 'recording.wav');

      const response = await fetch(`${API_URL}/speech-to-text`, {
        method: 'POST',
        body: formData,
      });

      const data = await response.json();
      setSearchQuery(data.text);
      // Automatically search with transcribed text
      if (data.text.trim()) {
        await searchDocuments(data.text);
      }
    } catch (error) {
      console.error('Error transcribing audio:', error);
      alert('Failed to transcribe audio. Please try again.');
    } finally {
      setIsTranscribing(false);
    }
  };

  // Search documents
  const searchDocuments = async (query) => {
    if (!query.trim()) return;
    
    setIsSearching(true);
    try {
      const endpoint = useSemanticSearch ? '/search/semantic' : '/search';
      const response = await fetch(`${API_URL}${endpoint}?q=${encodeURIComponent(query)}`);
      const data = await response.json();
      setSearchResults(data.results);
      
      // Store query details for display (including MongoDB operation)
      setQueryDetails({
        query: data.query,
        mongodb_query: data.mongodb_query,
        execution_time_ms: data.execution_time_ms,
        search_type: data.search_type,
        total: data.total,
        index_used: data.index_used,
        mongodb_operation: data.mongodb_operation,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error('Error searching documents:', error);
    } finally {
      setIsSearching(false);
    }
  };

  // Submit new document
  const submitDocument = async (e) => {
    e.preventDefault();
    try {
      const tagsArray = newDoc.tags.split(',').map(tag => tag.trim()).filter(tag => tag);
      const response = await fetch(`${API_URL}/documents`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          title: newDoc.title,
          body: newDoc.body,
          tags: tagsArray
        }),
      });
      
      if (response.ok) {
        const result = await response.json();
        // Capture MongoDB operation details
        if (result.mongodb_operation) {
          setMongodbOps(prev => ({ ...prev, createDocument: result.mongodb_operation }));
        }
        setNewDoc({ title: '', body: '', tags: '' });
        fetchDocuments(); // Refresh the list
      }
    } catch (error) {
      console.error('Error submitting document:', error);
    }
  };

  // Handle audio file selection
  const handleAudioFileChange = (e) => {
    const file = e.target.files[0];
    if (file) {
      // Check if it's an audio file
      if (file.type.startsWith('audio/')) {
        setAudioFile(file);
        setUploadStatus('');
      } else {
        alert('Please select a valid audio file');
        e.target.value = '';
      }
    }
  };

  // Upload audio file and create document
  const uploadAudioDocument = async (e) => {
    e.preventDefault();
    if (!audioFile) {
      alert('Please select an audio file');
      return;
    }

    setIsUploadingAudio(true);
    setUploadStatus('Uploading and transcribing audio...');

    try {
      const formData = new FormData();
      formData.append('audio', audioFile);
      if (audioTitle) formData.append('title', audioTitle);
      if (audioTags) formData.append('tags', audioTags);
      if (audioLanguage) formData.append('language', audioLanguage);

      const response = await fetch(`${API_URL}/documents/from-audio`, {
        method: 'POST',
        body: formData,
      });

      if (response.ok) {
        const result = await response.json();
        setUploadStatus(`✅ Successfully created document: "${result.title}"`);
        
        // Capture MongoDB operation details
        if (result.mongodb_operation) {
          setMongodbOps(prev => ({ ...prev, uploadAudio: result.mongodb_operation }));
        }
        
        // Reset form
        setAudioFile(null);
        setAudioTitle('');
        setAudioTags('');
        setAudioLanguage('');
        document.getElementById('audio-file-input').value = '';
        
        // Refresh documents list
        fetchDocuments();
        
        // Clear status after 3 seconds
        setTimeout(() => setUploadStatus(''), 3000);
      } else {
        const error = await response.json();
        setUploadStatus(`❌ Error: ${error.detail}`);
      }
    } catch (error) {
      console.error('Error uploading audio:', error);
      setUploadStatus('❌ Upload failed. Please try again.');
    } finally {
      setIsUploadingAudio(false);
    }
  };

  // Ask question using RAG
  const askQuestion = async (e) => {
    e.preventDefault();
    if (!chatQuestion.trim()) return;

    const userQuestion = chatQuestion;
    setChatQuestion('');
    setIsAsking(true);

    // Add user question to chat history
    const userMessage = { type: 'user', content: userQuestion };
    setChatHistory(prev => [...prev, userMessage]);

    try {
      const response = await fetch(`${API_URL}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          question: userQuestion,
          max_context_docs: 3
        }),
      });

      if (response.ok) {
        const data = await response.json();
        
        // Capture MongoDB operation details
        if (data.mongodb_operation) {
          setMongodbOps(prev => ({ ...prev, chat: data.mongodb_operation }));
        }
        
        // Add AI response to chat history
        const aiMessage = {
          type: 'ai',
          content: data.answer,
          sources: data.sources,
          model: data.model_used
        };
        setChatHistory(prev => [...prev, aiMessage]);
      } else {
        const error = await response.json();
        const errorMessage = {
          type: 'error',
          content: `Error: ${error.detail || 'Failed to get answer'}`
        };
        setChatHistory(prev => [...prev, errorMessage]);
      }
    } catch (error) {
      console.error('Error asking question:', error);
      const errorMessage = {
        type: 'error',
        content: 'Failed to connect to the server. Please try again.'
      };
      setChatHistory(prev => [...prev, errorMessage]);
    } finally {
      setIsAsking(false);
    }
  };

  // Scroll to bottom of chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [chatHistory]);

  useEffect(() => {
    fetchDocuments();
  }, []);

  return (
    <div className="App">
      <header className="App-header">
        <h1>Document Search App</h1>
      </header>

      <div className="app-container">
        <main className="main-content">
        {/* Audio Upload Section - Always visible at top */}
        <section className="form-section audio-upload-section">
          <h2>🎵 Upload Audio File</h2>
          <p className="section-description">
            Upload an audio file to automatically transcribe, generate embeddings, and store it as a searchable document
          </p>
          <form onSubmit={uploadAudioDocument} className="document-form">
            <div className="form-group">
              <label>Audio File:</label>
              <div className="file-input-wrapper">
                <input
                  id="audio-file-input"
                  type="file"
                  accept="audio/*"
                  onChange={handleAudioFileChange}
                  className="file-input"
                  required
                />
                <label htmlFor="audio-file-input" className="file-input-label">
                  {audioFile ? `📎 ${audioFile.name}` : '🎤 Choose Audio File'}
                </label>
              </div>
            </div>
            <div className="form-group">
              <label>Title (optional):</label>
              <input
                type="text"
                value={audioTitle}
                onChange={(e) => setAudioTitle(e.target.value)}
                placeholder="Leave empty to auto-generate from transcription"
              />
            </div>
            <div className="form-group">
              <label>Tags (optional, comma-separated):</label>
              <input
                type="text"
                value={audioTags}
                onChange={(e) => setAudioTags(e.target.value)}
                placeholder="meeting, notes, interview"
              />
            </div>
            <div className="form-group">
              <label>Language (optional, auto-detect if empty):</label>
              <select
                value={audioLanguage}
                onChange={(e) => setAudioLanguage(e.target.value)}
              >
                <option value="">Auto-detect</option>
                <option value="en">English</option>
                <option value="es">Spanish</option>
                <option value="fr">French</option>
                <option value="de">German</option>
                <option value="it">Italian</option>
                <option value="pt">Portuguese</option>
                <option value="nl">Dutch</option>
                <option value="ru">Russian</option>
                <option value="zh">Chinese</option>
                <option value="ja">Japanese</option>
                <option value="ko">Korean</option>
                <option value="ar">Arabic</option>
                <option value="hi">Hindi</option>
                <option value="pl">Polish</option>
                <option value="tr">Turkish</option>
                <option value="vi">Vietnamese</option>
                <option value="uk">Ukrainian</option>
                <option value="cs">Czech</option>
                <option value="sv">Swedish</option>
                <option value="da">Danish</option>
                <option value="fi">Finnish</option>
                <option value="no">Norwegian</option>
                <option value="hu">Hungarian</option>
                <option value="ro">Romanian</option>
              </select>
            </div>
            <button type="submit" disabled={isUploadingAudio || !audioFile}>
              {isUploadingAudio ? '⏳ Processing...' : '🚀 Upload & Transcribe'}
            </button>
          </form>
          
          {uploadStatus && (
            <div className={`upload-status ${uploadStatus.includes('✅') ? 'success' : 'error'}`}>
              {uploadStatus}
            </div>
          )}
          {mongodbOps.uploadAudio && (
            <MongoDBOperationDetails 
              operation={mongodbOps.uploadAudio} 
              title="Upload Audio Document"
            />
          )}
        </section>

        {/* Add Text Document Section - Collapsible */}
        <section className="form-section collapsible-section">
          <h2 className="collapsible-header" onClick={() => toggleSection('addDocument')}>
            <span className="expand-icon">{expandedSections.addDocument ? '▼' : '▶'}</span>
            📝 Add Text Document
          </h2>
          {expandedSections.addDocument && (
            <div className="collapsible-content">
              <form onSubmit={submitDocument} className="document-form">
                <div className="form-group">
                  <label>Title:</label>
                  <input
                    type="text"
                    value={newDoc.title}
                    onChange={(e) => setNewDoc({...newDoc, title: e.target.value})}
                    required
                  />
                </div>
                <div className="form-group">
                  <label>Body:</label>
                  <textarea
                    value={newDoc.body}
                    onChange={(e) => setNewDoc({...newDoc, body: e.target.value})}
                    required
                    rows="4"
                  />
                </div>
                <div className="form-group">
                  <label>Tags (comma-separated):</label>
                  <input
                    type="text"
                    value={newDoc.tags}
                    onChange={(e) => setNewDoc({...newDoc, tags: e.target.value})}
                    placeholder="tag1, tag2, tag3"
                  />
                </div>
                <button type="submit">Submit Document</button>
              </form>
              {mongodbOps.createDocument && (
                <MongoDBOperationDetails 
                  operation={mongodbOps.createDocument} 
                  title="Create Document"
                />
              )}
            </div>
          )}
        </section>

        {/* Search Section - Collapsible */}
        <section className="search-section collapsible-section">
          <h2 className="collapsible-header" onClick={() => toggleSection('search')}>
            <span className="expand-icon">{expandedSections.search ? '▼' : '▶'}</span>
            🔍 Search Documents
          </h2>
          
          {expandedSections.search && (
          <div className="collapsible-content">
          <div className="search-options">
            <label className="toggle-switch">
              <input
                type="checkbox"
                checked={useSemanticSearch}
                onChange={(e) => setUseSemanticSearch(e.target.checked)}
              />
              <span className="slider"></span>
              <span className="toggle-label">
                {useSemanticSearch ? '🧠 Semantic Search' : '📝 Text Search'}
              </span>
            </label>
          </div>

          <div className="search-form">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyPress={(e) => e.key === 'Enter' && searchDocuments(searchQuery)}
              placeholder="Enter search terms or use voice..."
              className="search-input"
            />
            
            <button 
              className={`mic-button ${isRecording ? 'recording' : ''}`}
              onClick={isRecording ? stopRecording : startRecording}
              disabled={isTranscribing}
              title={isRecording ? 'Stop recording' : 'Start voice search'}
            >
              {isTranscribing ? '⏳' : isRecording ? '⏹️' : '🎤'}
            </button>
            
            <button 
              className="search-button"
              onClick={() => searchDocuments(searchQuery)}
              disabled={isSearching || isTranscribing}
            >
              {isSearching ? 'Searching...' : 'Search'}
            </button>
          </div>
          
          {isTranscribing && (
            <div className="status-message">
              🎙️ Transcribing your speech...
            </div>
          )}
          {isRecording && (
            <div className="status-message recording-pulse">
              🔴 Recording... Click stop when done
            </div>
          )}
          </div>
          )}
        </section>

        {/* RAG Chat Section - Collapsible */}
        <section className="chat-section collapsible-section">
          <h2 className="collapsible-header" onClick={() => toggleSection('chat')}>
            <span className="expand-icon">{expandedSections.chat ? '▼' : '▶'}</span>
            💬 Ask AI Questions
          </h2>
          {expandedSections.chat && (
          <div className="collapsible-content">
          <p className="section-description">
            Use AI to ask questions and get answers based on your stored documents (RAG - Retrieval-Augmented Generation)
          </p>
          
          <div className="chat-container">
            <div className="chat-messages">
              {chatHistory.length === 0 ? (
                <div className="chat-welcome">
                  <div className="welcome-icon">🤖</div>
                  <h3>Ask me anything about your documents!</h3>
                  <p>I'll search through your documents and provide answers based on the content.</p>
                  <div className="example-questions">
                    <p><strong>Try asking:</strong></p>
                    <ul>
                      <li>"What are the main topics discussed?"</li>
                      <li>"Summarize the key points"</li>
                      <li>"What did we say about [topic]?"</li>
                    </ul>
                  </div>
                </div>
              ) : (
                <>
                  {chatHistory.map((message, index) => (
                    <div key={index} className={`chat-message ${message.type}`}>
                      <div className="message-icon">
                        {message.type === 'user' ? '👤' : message.type === 'ai' ? '🤖' : '⚠️'}
                      </div>
                      <div className="message-content">
                        <div className="message-text">{message.content}</div>
                        {message.sources && message.sources.length > 0 && (
                          <div className="message-sources">
                            <div className="sources-header">📚 Sources ({message.sources.length}):</div>
                            {message.sources.map((source, idx) => (
                              <div key={idx} className="source-item">
                                <strong>{source.title}</strong>
                                <p>{source.body.substring(0, 100)}...</p>
                              </div>
                            ))}
                          </div>
                        )}
                        {message.model && (
                          <div className="message-model">Model: {message.model}</div>
                        )}
                      </div>
                    </div>
                  ))}
                  <div ref={chatEndRef} />
                </>
              )}
            </div>
            
            <form onSubmit={askQuestion} className="chat-input-form">
              <input
                type="text"
                value={chatQuestion}
                onChange={(e) => setChatQuestion(e.target.value)}
                placeholder="Ask a question about your documents..."
                className="chat-input"
                disabled={isAsking}
              />
              <button type="submit" disabled={isAsking || !chatQuestion.trim()} className="chat-send-button">
                {isAsking ? '⏳' : '📤'} {isAsking ? 'Thinking...' : 'Ask'}
              </button>
            </form>
          </div>
          {mongodbOps.chat && (
            <MongoDBOperationDetails 
              operation={mongodbOps.chat} 
              title="RAG Document Retrieval"
            />
          )}
          </div>
          )}
        </section>

        {/* All Documents Section - Collapsible */}
        <section className="results-section collapsible-section">
          <h2 className="collapsible-header" onClick={() => toggleSection('documents')}>
            <span className="expand-icon">{expandedSections.documents ? '▼' : '▶'}</span>
            📚 {searchResults.length > 0 ? `Search Results (${searchResults.length})` : `All Documents (${documents.length})`}
          </h2>
          {expandedSections.documents && (
          <div className="collapsible-content">
          {isLoadingDocuments ? (
            <div style={{ padding: '20px', textAlign: 'center' }}>
              <p>⏳ Loading documents...</p>
            </div>
          ) : searchResults.length > 0 ? (
            <div>
              <h3>Search Results for "{searchQuery}"</h3>
              {searchResults.map((doc, index) => (
                <div key={doc.id} className="document-card">
                  <h3>{doc.title}</h3>
                  <p>{doc.body}</p>
                  <div className="tags">
                    {doc.tags.map((tag, i) => (
                      <span key={i} className="tag">{tag}</span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div>
              <h3>All Documents {documents.length > 0 ? `(${documents.length})` : ''}</h3>
              {documents.length === 0 ? (
                <p style={{ padding: '20px', textAlign: 'center', color: '#666' }}>
                  No documents found. Add a document or upload an audio file to get started.
                </p>
              ) : (
                documents.map((doc) => (
                  <div key={doc.id} className="document-card">
                    <h3>{doc.title}</h3>
                    <p>{doc.body}</p>
                    <div className="tags">
                      {doc.tags.map((tag, i) => (
                        <span key={i} className="tag">{tag}</span>
                      ))}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
          {mongodbOps.fetchDocuments && (
            <MongoDBOperationDetails 
              operation={mongodbOps.fetchDocuments} 
              title="Fetch All Documents"
            />
          )}
          </div>
          )}
        </section>
      </main>

      {/* Query Details Sidebar */}
      <aside className="query-sidebar">
        <h3>🔍 MongoDB Query Details</h3>
        {queryDetails ? (
          <div className="query-details">
            <div className="detail-section">
              <h4>Search Info</h4>
              <div className="detail-item">
                <span className="detail-label">Query:</span>
                <span className="detail-value">"{queryDetails.query}"</span>
              </div>
              <div className="detail-item">
                <span className="detail-label">Type:</span>
                <span className="detail-value badge">{queryDetails.search_type}</span>
              </div>
              <div className="detail-item">
                <span className="detail-label">Execution Time:</span>
                <span className="detail-value">{queryDetails.execution_time_ms}ms</span>
              </div>
              <div className="detail-item">
                <span className="detail-label">Results:</span>
                <span className="detail-value">{queryDetails.total} documents</span>
              </div>
            </div>

            <div className="detail-section">
              <h4>MongoDB Query</h4>
              <pre className="code-block">
                {JSON.stringify(queryDetails.mongodb_query || queryDetails.mongodb_operation?.query, null, 2)}
              </pre>
            </div>

            {queryDetails.mongodb_operation && (
              <div className="detail-section">
                <h4>🗄️ MongoDB Operation Details</h4>
                <div style={{ marginBottom: '10px' }}>
                  <strong>Operation:</strong> {queryDetails.mongodb_operation.operation}
                </div>
                {queryDetails.mongodb_operation.result && (
                  <div style={{ marginBottom: '10px' }}>
                    <strong>Result:</strong>
                    <pre className="code-block">
                      {JSON.stringify(queryDetails.mongodb_operation.result, null, 2)}
                    </pre>
                  </div>
                )}
              </div>
            )}

            {queryDetails.index_used && (
              <div className="detail-section">
                <h4>📊 Index Used</h4>
                <pre className="code-block">
                  {JSON.stringify(queryDetails.index_used, null, 2)}
                </pre>
              </div>
            )}

            <div className="detail-section">
              <h4>Timestamp</h4>
              <div className="detail-value timestamp">
                {new Date(queryDetails.timestamp).toLocaleString()}
              </div>
            </div>
          </div>
        ) : (
          <div className="no-query-message">
            <p>🔎 Execute a search to see MongoDB query details</p>
          </div>
        )}
      </aside>
      </div>
    </div>
  );
}

export default App;
