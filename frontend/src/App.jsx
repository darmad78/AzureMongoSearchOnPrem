import React, { useState, useEffect, useRef } from 'react';
import './App.css';

// Determine API URL: Dynamically construct from current hostname
const getApiUrl = () => {
  // Get the current hostname (works regardless of IP changes)
  const hostname = window.location.hostname;
  const protocol = window.location.protocol;
  const backendPort = "30888";
  
  // Get build time for deployment verification
  const buildTime = import.meta.env.VITE_BUILD_TIME || 'Unknown Build Time';
  
  // Construct API URL using current hostname and backend port
  return {
    url: `${protocol}//${hostname}:${backendPort}`,
    buildTime: buildTime
  };
};

const { url: API_URL } = getApiUrl();
console.log('Frontend API_URL:', API_URL);
console.log('VITE_API_URL env:', import.meta.env.VITE_API_URL);
console.log('Window location:', window.location.href);

function App() {
  // Get build time for display
  const BUILD_TIME = import.meta.env.VITE_BUILD_TIME || 'Unknown Build Time';
  
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
  const [uploadSteps, setUploadSteps] = useState([]);
  const [chatQuestion, setChatQuestion] = useState('');
  const [chatHistory, setChatHistory] = useState([]);
  const [isAsking, setIsAsking] = useState(false);
  const [customPrompt, setCustomPrompt] = useState('You are a helpful assistant. Answer the question based on the context provided.');
  // MongoDB operation details for each operation type
  const [mongodbOps, setMongodbOps] = useState({
    createDocument: null,
    uploadAudio: null,
    chat: null,
    fetchDocuments: null,
    search: null,
    search: null
  });
  const mediaRecorderRef = useRef(null);
  const audioChunksRef = useRef([]);
  const chatEndRef = useRef(null);
  
  // Collapsible sections state
  const [expandedSections, setExpandedSections] = useState({
    addDocument: false,
    search: true,
    chat: true,  // Expanded by default for better UX
    documents: true,  // Expanded by default to show documents
    health: false
  });
  const [isLoadingDocuments, setIsLoadingDocuments] = useState(true);
  
  // Health check state
  const [healthData, setHealthData] = useState({
    backend: null,
    ollama: null,
    mongodb: null,
    isLoading: false,
    lastChecked: null
  });
  
  const toggleSection = (section) => {
    setExpandedSections(prev => ({
      ...prev,
      [section]: !prev[section]
    }));
  };

  // Professional MongoDB Query/Result Display Component
  const MongoDBQueryResult = ({ operation, collapsible = true }) => {
    const [isExpanded, setIsExpanded] = useState(!collapsible);
    
    if (!operation) return null;
    
    return (
      <div className="mongodb-query-result">
        {collapsible && (
          <div 
            className="mongodb-header"
            onClick={() => setIsExpanded(!isExpanded)}
          >
            <div className="mongodb-header-title">
              <span className="mongodb-header-icon">🗄️</span>
              MongoDB Query Details
            </div>
            <span>{isExpanded ? '▼' : '▶'}</span>
          </div>
        )}
        {(!collapsible || isExpanded) && (
          <div className="mongodb-content">
            {/* Query and Response side by side (when no workflow steps) */}
            {operation.query && operation.result && !operation.result.workflow_steps && (
              <div style={{ 
                display: 'grid', 
                gridTemplateColumns: '1fr 1fr', 
                gap: '15px',
                marginBottom: '15px',
                width: '100%'
              }}>
                {/* Query Block */}
                {operation.query && (
                  <div className="mongodb-block mongodb-block-query">
                    <div className="mongodb-block-header">
                      <span className="mongodb-block-icon">📤</span>
                      <h4 className="mongodb-block-title">Query Request</h4>
                    </div>
                    <div className="mongodb-block-content">
                      <pre className="mongodb-code" style={{
                        backgroundColor: '#f8f9fa',
                        padding: '12px',
                        borderRadius: '6px',
                        overflow: 'auto',
                        fontSize: '0.85em',
                        fontFamily: 'Monaco, "Courier New", monospace',
                        lineHeight: '1.5',
                        maxHeight: '400px',
                        border: '1px solid #dee2e6'
                      }}>
                        {JSON.stringify(operation.query, null, 2)}
                      </pre>
                    </div>
                  </div>
                )}
                
                {/* Result Block */}
                {operation.result && (
                  <div className="mongodb-block mongodb-block-response">
                    <div className="mongodb-block-header">
                      <span className="mongodb-block-icon">📥</span>
                      <h4 className="mongodb-block-title">Query Response</h4>
                    </div>
                    <div className="mongodb-block-content">
                      <pre className="mongodb-code" style={{
                        backgroundColor: '#f8f9fa',
                        padding: '12px',
                        borderRadius: '6px',
                        overflow: 'auto',
                        fontSize: '0.85em',
                        fontFamily: 'Monaco, "Courier New", monospace',
                        lineHeight: '1.5',
                        maxHeight: '400px',
                        border: '1px solid #dee2e6'
                      }}>
                        {JSON.stringify(operation.result, null, 2)}
                      </pre>
                      {operation.result.retrieved_documents !== undefined && (
                        <div className="mongodb-summary" style={{
                          marginTop: '10px',
                          padding: '8px',
                          backgroundColor: '#e7f3ff',
                          borderRadius: '4px',
                          fontSize: '0.9em'
                        }}>
                          <strong>📊 Summary:</strong> Retrieved <strong>{operation.result.retrieved_documents}</strong> of <strong>{operation.result.total_documents || 'N/A'}</strong> documents
                          {operation.result.similarity_scores && operation.result.similarity_scores.length > 0 && (
                            <div style={{ marginTop: '6px' }}>
                              Similarity: {operation.result.similarity_scores.map(s => s.toFixed(4)).join(', ')}
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            )}
            
            {/* Query Block (when workflow steps exist, show query separately) */}
            {operation.query && operation.result && operation.result.workflow_steps && (
              <div className="mongodb-block mongodb-block-query" style={{ marginBottom: '15px' }}>
                <div className="mongodb-block-header">
                  <span className="mongodb-block-icon">📤</span>
                  <h4 className="mongodb-block-title">Query Request</h4>
                </div>
                <div className="mongodb-block-content">
                  <pre className="mongodb-code" style={{
                    backgroundColor: '#f8f9fa',
                    padding: '12px',
                    borderRadius: '6px',
                    overflow: 'auto',
                    fontSize: '0.85em',
                    fontFamily: 'Monaco, "Courier New", monospace',
                    lineHeight: '1.5',
                    maxHeight: '400px',
                    border: '1px solid #dee2e6'
                  }}>
                    {JSON.stringify(operation.query, null, 2)}
                  </pre>
                </div>
              </div>
            )}
            
            {/* Workflow Steps Block (for audio upload) */}
            {operation.result && operation.result.workflow_steps && (
              <div className="mongodb-block mongodb-block-workflow">
                <div className="mongodb-block-header">
                  <span className="mongodb-block-icon">📋</span>
                  <h4 className="mongodb-block-title">Processing Workflow</h4>
                </div>
                <div className="mongodb-block-content">
                  {operation.result.workflow_steps.map((step, idx) => (
                    <div key={`step-${step.step}-${idx}`} style={{
                      marginBottom: '15px',
                      padding: '12px',
                      backgroundColor: '#fff',
                      border: '1px solid #dee2e6',
                      borderRadius: '6px',
                      borderLeft: '4px solid #28a745'
                    }}>
                      <div style={{ display: 'flex', alignItems: 'center', marginBottom: '8px' }}>
                        <span style={{
                          backgroundColor: '#28a745',
                          color: 'white',
                          borderRadius: '50%',
                          width: '24px',
                          height: '24px',
                          display: 'inline-flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          fontSize: '0.85em',
                          fontWeight: 'bold',
                          marginRight: '10px'
                        }}>
                          {step.step}
                        </span>
                        <strong style={{ fontSize: '0.95em' }}>{step.name}</strong>
                        {step.details.duration_ms && (
                          <span style={{
                            marginLeft: 'auto',
                            fontSize: '0.8em',
                            color: '#6c757d'
                          }}>
                            {step.details.duration_ms}ms
                          </span>
                        )}
                      </div>
                      <div style={{ marginLeft: '34px', fontSize: '0.85em', color: '#495057' }}>
                        {Object.entries(step.details).filter(([key]) => key !== 'duration_ms').map(([key, value]) => (
                          <div key={key} style={{ marginBottom: '4px' }}>
                            <strong>{key.replace(/_/g, ' ')}:</strong> {
                              typeof value === 'object' ? (
                                <pre style={{
                                  display: 'inline-block',
                                  margin: '4px 0 0 0',
                                  padding: '6px',
                                  backgroundColor: '#f8f9fa',
                                  borderRadius: '4px',
                                  fontSize: '0.8em',
                                  maxWidth: '100%',
                                  overflow: 'auto'
                                }}>
                                  {JSON.stringify(value, null, 2)}
                                </pre>
                              ) : (
                                <span> {String(value)}</span>
                              )
                            }
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                  {operation.result.total_duration_ms && (
                    <div style={{
                      marginTop: '15px',
                      padding: '10px',
                      backgroundColor: '#e7f3ff',
                      borderRadius: '4px',
                      textAlign: 'center',
                      fontWeight: 'bold'
                    }}>
                      ⏱️ Total Duration: {operation.result.total_duration_ms}ms
                    </div>
                  )}
                </div>
              </div>
            )}
            
            
            {/* Index Used Block */}
            {operation.index_used && (
              <div className="mongodb-block mongodb-block-index">
                <div className="mongodb-block-header">
                  <span className="mongodb-block-icon">📊</span>
                  <h4 className="mongodb-block-title">Index Used</h4>
                </div>
                <div className="mongodb-block-content">
                  <pre className="mongodb-code">
                    {JSON.stringify(operation.index_used, null, 2)}
                  </pre>
                </div>
              </div>
            )}
            
            {/* Metadata */}
            <div className="mongodb-metadata">
              {operation.operation && (
                <div className="mongodb-metadata-item">
                  <strong>Operation:</strong>
                  <span className="mongodb-badge">{operation.operation}</span>
                </div>
              )}
              {operation.execution_time_ms && (
                <div className="mongodb-metadata-item">
                  <strong>⏱️ Time:</strong> {operation.execution_time_ms}ms
                </div>
              )}
              {operation.documents_affected !== null && operation.documents_affected !== undefined && (
                <div className="mongodb-metadata-item">
                  <strong>📄 Documents:</strong> {operation.documents_affected}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    );
  };

  // MongoDB Operation Details Component (for workflow steps)
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
          <div style={{ marginBottom: '15px' }}>
            <strong style={{ fontSize: '1em', color: '#007bff', display: 'block', marginBottom: '8px' }}>
              📤 MongoDB Query Sent:
            </strong>
            <pre style={{ 
              backgroundColor: '#e7f3ff', 
              padding: '12px', 
              borderRadius: '6px',
              overflow: 'auto',
              fontSize: '0.85em',
              marginTop: '5px',
              border: '1px solid #b3d9ff',
              maxHeight: '300px',
              fontFamily: 'monospace'
            }}>
              {JSON.stringify(operation.query, null, 2)}
            </pre>
          </div>
        )}
        {operation.result && operation.result.workflow_steps && (
          <div style={{ marginBottom: '15px' }}>
            <strong>📋 Workflow Steps:</strong>
            <div style={{ marginTop: '10px' }}>
              {operation.result.workflow_steps.map((step, idx) => (
                <div key={idx} style={{
                  marginBottom: '12px',
                  padding: '12px',
                  backgroundColor: '#fff',
                  border: '1px solid #dee2e6',
                  borderRadius: '6px',
                  borderLeft: '4px solid #28a745'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', marginBottom: '8px' }}>
                    <span style={{
                      backgroundColor: '#28a745',
                      color: 'white',
                      borderRadius: '50%',
                      width: '24px',
                      height: '24px',
                      display: 'inline-flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      fontSize: '0.85em',
                      fontWeight: 'bold',
                      marginRight: '10px'
                    }}>
                      {step.step}
                    </span>
                    <strong style={{ fontSize: '0.95em' }}>{step.name}</strong>
                    {step.details.duration_ms && (
                      <span style={{
                        marginLeft: 'auto',
                        fontSize: '0.8em',
                        color: '#6c757d'
                      }}>
                        {step.details.duration_ms}ms
                      </span>
                    )}
                  </div>
                  <div style={{ marginLeft: '34px', fontSize: '0.85em', color: '#495057' }}>
                    {Object.entries(step.details).filter(([key]) => key !== 'duration_ms').map(([key, value]) => (
                      <div key={key} style={{ marginBottom: '4px' }}>
                        <strong>{key.replace(/_/g, ' ')}:</strong> {
                          typeof value === 'object' ? (
                            <pre style={{
                              display: 'inline-block',
                              margin: '4px 0 0 0',
                              padding: '6px',
                              backgroundColor: '#f8f9fa',
                              borderRadius: '4px',
                              fontSize: '0.8em',
                              maxWidth: '100%',
                              overflow: 'auto'
                            }}>
                              {JSON.stringify(value, null, 2)}
                            </pre>
                          ) : (
                            <span> {String(value)}</span>
                          )
                        }
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            {operation.result.total_duration_ms && (
              <div style={{
                marginTop: '10px',
                padding: '8px',
                backgroundColor: '#e7f3ff',
                borderRadius: '4px',
                textAlign: 'center',
                fontWeight: 'bold'
              }}>
                ⏱️ Total Duration: {operation.result.total_duration_ms}ms
              </div>
            )}
          </div>
        )}
        {operation.result && !operation.result.workflow_steps && (
          <div style={{ marginBottom: '15px' }}>
            <strong style={{ fontSize: '1em', color: '#28a745', display: 'block', marginBottom: '8px' }}>
              📥 MongoDB Response:
            </strong>
            <pre style={{ 
              backgroundColor: '#d4edda', 
              padding: '12px', 
              borderRadius: '6px',
              overflow: 'auto',
              fontSize: '0.85em',
              marginTop: '5px',
              border: '1px solid #c3e6cb',
              maxHeight: '300px',
              fontFamily: 'monospace'
            }}>
              {JSON.stringify(operation.result, null, 2)}
            </pre>
            {operation.result.retrieved_documents !== undefined && (
              <div style={{ 
                marginTop: '10px', 
                padding: '10px',
                backgroundColor: '#fff3cd',
                borderRadius: '6px',
                fontSize: '0.9em',
                border: '1px solid #ffc107'
              }}>
                <strong>📊 Query Summary:</strong>
                <div style={{ marginTop: '5px' }}>
                  • Retrieved <strong>{operation.result.retrieved_documents}</strong> document(s) from <strong>{operation.result.total_documents || 'N/A'}</strong> total
                  {operation.result.similarity_scores && operation.result.similarity_scores.length > 0 && (
                    <div style={{ marginTop: '5px' }}>
                      • Similarity scores: <strong>{operation.result.similarity_scores.map(s => s.toFixed(4)).join(', ')}</strong>
                    </div>
                  )}
                </div>
              </div>
            )}
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
      
      // Capture MongoDB operation details for sidebar
      if (data.mongodb_operation) {
        setMongodbOps(prev => ({ ...prev, search: data.mongodb_operation }));
      }
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
        setUploadSteps([]);
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
    setUploadStatus('Starting upload...');
    setUploadSteps([]);

    try {
      const formData = new FormData();
      formData.append('audio', audioFile);
      if (audioTitle) formData.append('title', audioTitle);
      if (audioTags) formData.append('tags', audioTags);
      if (audioLanguage) formData.append('language', audioLanguage);

      // Show initial step
      setUploadSteps([{
        step: 1,
        name: "Upload Audio File",
        status: "in_progress",
        details: { filename: audioFile.name }
      }]);
      setUploadStatus('📤 Uploading audio file...');

      const response = await fetch(`${API_URL}/documents/from-audio`, {
        method: 'POST',
        body: formData,
      });

      if (response.ok) {
        const result = await response.json();
        
        // Extract workflow steps from MongoDB operation
        let steps = [];
        if (result.mongodb_operation && result.mongodb_operation.result && result.mongodb_operation.result.workflow_steps) {
          steps = result.mongodb_operation.result.workflow_steps;
          console.log('Workflow steps received:', steps.length, steps);
        }
        
        setUploadSteps(steps);
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
        
        // Clear status after 5 seconds (longer to see the steps)
        setTimeout(() => {
          setUploadStatus('');
          setUploadSteps([]);
        }, 5000);
      } else {
        const error = await response.json();
        setUploadStatus(`❌ Error: ${error.detail}`);
        setUploadSteps([]);
      }
    } catch (error) {
      console.error('Error uploading audio:', error);
      setUploadStatus('❌ Upload failed. Please try again.');
      setUploadSteps([]);
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
      const requestBody = {
        question: userQuestion,
        max_context_docs: 10,  // Increased from 3 to 10 for better RAG context
        system_prompt: customPrompt.trim() || undefined
      };
      console.log('📤 Sending chat request with system_prompt:', requestBody.system_prompt || '(using default)');
      
      const response = await fetch(`${API_URL}/chat`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(requestBody),
      });

      if (response.ok) {
        const data = await response.json();
        
        // Capture MongoDB operation details
        if (data.mongodb_operation) {
          setMongodbOps(prev => ({ ...prev, chat: data.mongodb_operation }));
        }
        
        // Add AI response to chat history with MongoDB operation
        const aiMessage = {
          type: 'ai',
          content: data.answer,
          sources: data.sources,
          model: data.model_used,
          mongodb_operation: data.mongodb_operation
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

  // Health check function
  const checkHealth = async () => {
    setHealthData(prev => ({ ...prev, isLoading: true }));
    const health = {
      backend: null,
      ollama: null,
      mongodb: null,
      lastChecked: new Date().toISOString()
    };

    // Check backend API
    try {
      const backendResponse = await fetch(`${API_URL}/`);
      health.backend = {
        status: backendResponse.ok ? 'healthy' : 'unhealthy',
        message: backendResponse.ok ? 'Backend API is running' : `HTTP ${backendResponse.status}`,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      health.backend = {
        status: 'error',
        message: `Cannot connect to backend: ${error.message}`,
        timestamp: new Date().toISOString()
      };
    }

    // Check Ollama
    try {
      const ollamaResponse = await fetch(`${API_URL}/health/ollama`);
      const ollamaData = await ollamaResponse.json();
      health.ollama = {
        status: ollamaData.status || 'unknown',
        message: ollamaData.message || 'Unknown status',
        model_available: ollamaData.model_available || false,
        ollama_url: ollamaData.ollama_url || 'N/A',
        ollama_model: ollamaData.ollama_model || 'N/A',
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      health.ollama = {
        status: 'error',
        message: `Cannot check Ollama health: ${error.message}`,
        timestamp: new Date().toISOString()
      };
    }

    // Check MongoDB (by trying to fetch documents count)
    try {
      const mongoResponse = await fetch(`${API_URL}/documents`);
      if (mongoResponse.ok) {
        const docs = await mongoResponse.json();
        health.mongodb = {
          status: 'healthy',
          message: `Connected to MongoDB. ${docs.length} documents found.`,
          document_count: docs.length,
          timestamp: new Date().toISOString()
        };
      } else {
        health.mongodb = {
          status: 'unhealthy',
          message: `MongoDB connection issue: HTTP ${mongoResponse.status}`,
          timestamp: new Date().toISOString()
        };
      }
    } catch (error) {
      health.mongodb = {
        status: 'error',
        message: `Cannot connect to MongoDB: ${error.message}`,
        timestamp: new Date().toISOString()
      };
    }

    setHealthData({
      ...health,
      isLoading: false
    });
  };

  useEffect(() => {
    fetchDocuments();
  }, []);

  return (
    <div className="App">
      <header className="App-header">
        <h1>Document Search App</h1>
        <p style={{ position: 'absolute', top: '50px', left: '20px', fontSize: '12px', color: '#888', zIndex: 10 }}>
          Version: {BUILD_TIME}
        </p>
        <button 
          onClick={() => {
            toggleSection('health');
            if (!expandedSections.health) {
              checkHealth();
            }
          }}
          style={{
            position: 'absolute',
            top: '20px',
            right: '20px',
            padding: '10px 20px',
            backgroundColor: expandedSections.health ? '#28a745' : '#007bff',
            color: 'white',
            border: 'none',
            borderRadius: '5px',
            cursor: 'pointer',
            fontSize: '14px',
            fontWeight: 'bold'
          }}
        >
          {expandedSections.health ? '🟢 Health' : '⚕️ Health Check'}
        </button>
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
          
          {/* Workflow Steps Progress */}
          {uploadSteps.length > 0 && (
            <div style={{
              marginTop: '20px',
              padding: '15px',
              backgroundColor: '#f8f9fa',
              border: '1px solid #dee2e6',
              borderRadius: '8px'
            }}>
              <h3 style={{ marginTop: 0, marginBottom: '15px', color: '#495057' }}>
                📋 Processing Steps
              </h3>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                {uploadSteps.map((step, index) => {
                  console.log('Rendering step:', step.step, step.name);
                  return (
                    <div 
                      key={`upload-step-${step.step}-${index}`}
                      style={{
                        padding: '12px',
                        backgroundColor: step.status === 'completed' ? '#d4edda' : 
                                         step.status === 'in_progress' ? '#fff3cd' : '#f8f9fa',
                        border: `1px solid ${step.status === 'completed' ? '#c3e6cb' : 
                                                step.status === 'in_progress' ? '#ffeaa7' : '#dee2e6'}`,
                        borderRadius: '6px',
                        display: 'flex',
                        alignItems: 'flex-start',
                        gap: '12px'
                      }}
                    >
                      <div style={{
                        fontSize: '20px',
                        minWidth: '30px'
                      }}>
                        {step.status === 'completed' ? '✅' : 
                         step.status === 'in_progress' ? '⏳' : '⏸️'}
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{
                          fontWeight: 'bold',
                          marginBottom: '5px',
                          color: '#212529'
                        }}>
                          Step {step.step}: {step.name}
                        </div>
                        {step.details && (
                          <div style={{ fontSize: '0.9em', color: '#6c757d' }}>
                            {step.details.filename && (
                              <div>📄 File: {step.details.filename}</div>
                            )}
                            {step.details.file_size_bytes && (
                              <div>📦 Size: {(step.details.file_size_bytes / 1024).toFixed(2)} KB</div>
                            )}
                            {step.details.detected_language && (
                              <div>🌐 Language: {step.details.detected_language}</div>
                            )}
                            {step.details.transcription_length && (
                              <div>📝 Transcription: {step.details.transcription_length} characters</div>
                            )}
                            {step.details.transcription_preview && (
                              <div style={{ 
                                marginTop: '5px', 
                                fontStyle: 'italic',
                                color: '#495057'
                              }}>
                                Preview: "{step.details.transcription_preview}"
                              </div>
                            )}
                            {step.details.embedding_dimensions && (
                              <div>🧠 Embedding: {step.details.embedding_dimensions} dimensions ({step.details.model})</div>
                            )}
                            {step.details.inserted_id && (
                              <div>💾 Document ID: {step.details.inserted_id}</div>
                            )}
                            {step.details.duration_ms && (
                              <div style={{ 
                                marginTop: '5px',
                                fontWeight: 'bold',
                                color: '#007bff'
                              }}>
                                ⏱️ Duration: {step.details.duration_ms}ms
                              </div>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  );
                })}
                {mongodbOps.uploadAudio && mongodbOps.uploadAudio.result && mongodbOps.uploadAudio.result.total_duration_ms && (
                  <div style={{
                    marginTop: '10px',
                    padding: '10px',
                    backgroundColor: '#e7f3ff',
                    border: '1px solid #b3d9ff',
                    borderRadius: '6px',
                    textAlign: 'center',
                    fontWeight: 'bold',
                    color: '#004085'
                  }}>
                    ⏱️ Total Processing Time: {mongodbOps.uploadAudio.result.total_duration_ms}ms
                  </div>
                )}
              </div>
            </div>
          )}
          
          {mongodbOps.uploadAudio && (
            <MongoDBQueryResult 
              operation={mongodbOps.uploadAudio}
              collapsible={true}
            />
          )}
        </section>

        {/* RAG Chat Section - Collapsible - Moved right after audio upload */}
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
          
          <div style={{ 
            display: 'grid', 
            gridTemplateColumns: '2fr 1fr', 
            gap: '20px',
            marginBottom: '20px',
            alignItems: 'start'
          }}>
            <div className="chat-container" style={{ width: '100%' }}>
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
                        {message.mongodb_operation ? (
                          <MongoDBQueryResult 
                            operation={message.mongodb_operation} 
                            collapsible={false}
                          />
                        ) : null}
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
          
          {/* Custom Prompt Box */}
          <div style={{
            padding: '20px',
            backgroundColor: '#f8f9fa',
            border: '1px solid #dee2e6',
            borderRadius: '8px',
            height: 'fit-content'
          }}>
            <h3 style={{ marginTop: 0, marginBottom: '12px', fontSize: '1.1em', color: '#495057' }}>
              ⚙️ Custom System Prompt
            </h3>
            <p style={{ fontSize: '0.85em', color: '#6c757d', marginBottom: '12px' }}>
              Customize how the AI responds. Leave empty for default.
            </p>
            <textarea
              value={customPrompt}
              onChange={(e) => setCustomPrompt(e.target.value)}
              placeholder="You are a helpful assistant. Answer the question based on the context provided."
              style={{
                width: '100%',
                minHeight: '200px',
                padding: '12px',
                border: '1px solid #ced4da',
                borderRadius: '6px',
                fontSize: '0.9em',
                fontFamily: 'inherit',
                resize: 'vertical',
                lineHeight: '1.5'
              }}
            />
            <button
              onClick={() => setCustomPrompt('You are a helpful assistant. Answer the question based on the context provided.')}
              style={{
                marginTop: '10px',
                padding: '6px 12px',
                backgroundColor: '#6c757d',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '0.85em'
              }}
            >
              Reset to Default
            </button>
          </div>
          </div>
          </div>
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
          
          {/* MongoDB Query/Result Blocks */}
          {queryDetails && (
            <MongoDBQueryResult 
              operation={{
                query: queryDetails.mongodb_query || queryDetails.mongodb_operation?.query,
                result: queryDetails.mongodb_operation?.result || {
                  retrieved_documents: queryDetails.total,
                  total_documents: queryDetails.total
                },
                operation: queryDetails.mongodb_operation?.operation || queryDetails.search_type,
                execution_time_ms: queryDetails.execution_time_ms,
                documents_affected: queryDetails.total,
                index_used: queryDetails.index_used
              }}
              collapsible={true}
            />
          )}
          </div>
          )}
        </section>

        {/* Health Check Section - Collapsible */}
        <section className="form-section collapsible-section">
          <h2 className="collapsible-header" onClick={() => {
            toggleSection('health');
            if (!expandedSections.health && !healthData.isLoading) {
              checkHealth();
            }
          }}>
            <span className="expand-icon">{expandedSections.health ? '▼' : '▶'}</span>
            ⚕️ System Health
          </h2>
          {expandedSections.health && (
            <div className="collapsible-content">
              <div style={{ marginBottom: '20px' }}>
                <button 
                  onClick={checkHealth}
                  disabled={healthData.isLoading}
                  style={{
                    padding: '10px 20px',
                    backgroundColor: '#007bff',
                    color: 'white',
                    border: 'none',
                    borderRadius: '5px',
                    cursor: healthData.isLoading ? 'not-allowed' : 'pointer',
                    fontSize: '14px',
                    fontWeight: 'bold',
                    opacity: healthData.isLoading ? 0.6 : 1
                  }}
                >
                  {healthData.isLoading ? '⏳ Checking...' : '🔄 Refresh Health Status'}
                </button>
                {healthData.lastChecked && (
                  <span style={{ marginLeft: '15px', color: '#666', fontSize: '0.9em' }}>
                    Last checked: {new Date(healthData.lastChecked).toLocaleString()}
                  </span>
                )}
              </div>

              {healthData.isLoading && !healthData.backend && (
                <div style={{ padding: '20px', textAlign: 'center' }}>
                  <p>⏳ Checking system health...</p>
                </div>
              )}

              {/* Backend Health */}
              <div style={{
                marginBottom: '20px',
                padding: '15px',
                backgroundColor: '#f8f9fa',
                border: '1px solid #dee2e6',
                borderRadius: '8px'
              }}>
                <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{
                    fontSize: '20px',
                    color: healthData.backend?.status === 'healthy' ? '#28a745' : 
                           healthData.backend?.status === 'error' ? '#dc3545' : '#ffc107'
                  }}>
                    {healthData.backend?.status === 'healthy' ? '🟢' : 
                     healthData.backend?.status === 'error' ? '🔴' : '🟡'}
                  </span>
                  Backend API
                </h3>
                {healthData.backend ? (
                  <div>
                    <p><strong>Status:</strong> <span style={{
                      color: healthData.backend.status === 'healthy' ? '#28a745' : 
                             healthData.backend.status === 'error' ? '#dc3545' : '#ffc107',
                      fontWeight: 'bold'
                    }}>{healthData.backend.status.toUpperCase()}</span></p>
                    <p><strong>Message:</strong> {healthData.backend.message}</p>
                    <p style={{ fontSize: '0.85em', color: '#666' }}>
                      API URL: {API_URL}
                    </p>
                  </div>
                ) : (
                  <p>Not checked yet</p>
                )}
              </div>

              {/* Ollama Health */}
              <div style={{
                marginBottom: '20px',
                padding: '15px',
                backgroundColor: '#f8f9fa',
                border: '1px solid #dee2e6',
                borderRadius: '8px'
              }}>
                <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{
                    fontSize: '20px',
                    color: healthData.ollama?.status === 'healthy' ? '#28a745' : 
                           healthData.ollama?.status === 'error' || healthData.ollama?.status === 'unhealthy' ? '#dc3545' : '#ffc107'
                  }}>
                    {healthData.ollama?.status === 'healthy' ? '🟢' : 
                     healthData.ollama?.status === 'error' || healthData.ollama?.status === 'unhealthy' ? '🔴' : '🟡'}
                  </span>
                  Ollama LLM Service
                </h3>
                {healthData.ollama ? (
                  <div>
                    <p><strong>Status:</strong> <span style={{
                      color: healthData.ollama.status === 'healthy' ? '#28a745' : 
                             healthData.ollama.status === 'error' || healthData.ollama.status === 'unhealthy' ? '#dc3545' : '#ffc107',
                      fontWeight: 'bold'
                    }}>{healthData.ollama.status.toUpperCase()}</span></p>
                    <p><strong>Message:</strong> {healthData.ollama.message}</p>
                    {healthData.ollama.ollama_url && (
                      <p><strong>Ollama URL:</strong> {healthData.ollama.ollama_url}</p>
                    )}
                    {healthData.ollama.ollama_model && (
                      <p><strong>Model:</strong> {healthData.ollama.ollama_model}</p>
                    )}
                    <p><strong>Model Available:</strong> 
                      <span style={{
                        color: healthData.ollama.model_available ? '#28a745' : '#dc3545',
                        fontWeight: 'bold',
                        marginLeft: '5px'
                      }}>
                        {healthData.ollama.model_available ? '✅ Yes' : '❌ No'}
                      </span>
                    </p>
                    {!healthData.ollama.model_available && healthData.ollama.ollama_model && (
                      <div style={{
                        marginTop: '10px',
                        padding: '10px',
                        backgroundColor: '#fff3cd',
                        border: '1px solid #ffc107',
                        borderRadius: '5px',
                        fontSize: '0.9em'
                      }}>
                        <strong>⚠️ Model not available!</strong>
                        <p style={{ margin: '5px 0 0 0' }}>
                          Pull the model with:
                        </p>
                        <code style={{
                          display: 'block',
                          marginTop: '5px',
                          padding: '5px',
                          backgroundColor: '#f8f9fa',
                          borderRadius: '3px'
                        }}>
                          kubectl exec &lt;ollama-pod&gt; -n mongodb -- ollama pull {healthData.ollama.ollama_model}
                        </code>
                      </div>
                    )}
                  </div>
                ) : (
                  <p>Not checked yet</p>
                )}
              </div>

              {/* MongoDB Health */}
              <div style={{
                marginBottom: '20px',
                padding: '15px',
                backgroundColor: '#f8f9fa',
                border: '1px solid #dee2e6',
                borderRadius: '8px'
              }}>
                <h3 style={{ marginTop: 0, display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{
                    fontSize: '20px',
                    color: healthData.mongodb?.status === 'healthy' ? '#28a745' : 
                           healthData.mongodb?.status === 'error' ? '#dc3545' : '#ffc107'
                  }}>
                    {healthData.mongodb?.status === 'healthy' ? '🟢' : 
                     healthData.mongodb?.status === 'error' ? '🔴' : '🟡'}
                  </span>
                  MongoDB Database
                </h3>
                {healthData.mongodb ? (
                  <div>
                    <p><strong>Status:</strong> <span style={{
                      color: healthData.mongodb.status === 'healthy' ? '#28a745' : 
                             healthData.mongodb.status === 'error' ? '#dc3545' : '#ffc107',
                      fontWeight: 'bold'
                    }}>{healthData.mongodb.status.toUpperCase()}</span></p>
                    <p><strong>Message:</strong> {healthData.mongodb.message}</p>
                    {healthData.mongodb.document_count !== undefined && (
                      <p><strong>Documents:</strong> {healthData.mongodb.document_count}</p>
                    )}
                  </div>
                ) : (
                  <p>Not checked yet</p>
                )}
              </div>
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
      </div>
    </div>
  );
}

export default App;
