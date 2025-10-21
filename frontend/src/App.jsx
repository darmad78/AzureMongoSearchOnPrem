import React, { useState, useEffect } from 'react';
import './App.css';

const API_URL = 'http://localhost:8000';

function App() {
  const [documents, setDocuments] = useState([]);
  const [searchResults, setSearchResults] = useState([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [newDoc, setNewDoc] = useState({ title: '', body: '', tags: '' });
  const [isSearching, setIsSearching] = useState(false);

  // Fetch all documents
  const fetchDocuments = async () => {
    try {
      const response = await fetch(`${API_URL}/documents`);
      const data = await response.json();
      setDocuments(data);
    } catch (error) {
      console.error('Error fetching documents:', error);
    }
  };

  // Search documents
  const searchDocuments = async (query) => {
    if (!query.trim()) return;
    
    setIsSearching(true);
    try {
      const response = await fetch(`${API_URL}/search?q=${encodeURIComponent(query)}`);
      const data = await response.json();
      setSearchResults(data.results);
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
        setNewDoc({ title: '', body: '', tags: '' });
        fetchDocuments(); // Refresh the list
      }
    } catch (error) {
      console.error('Error submitting document:', error);
    }
  };

  useEffect(() => {
    fetchDocuments();
  }, []);

  return (
    <div className="App">
      <header className="App-header">
        <h1>Document Search App</h1>
      </header>

      <main className="main-content">
        {/* Document Submission Form */}
        <section className="form-section">
          <h2>Add New Document</h2>
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
        </section>

        {/* Search Section */}
        <section className="search-section">
          <h2>Search Documents</h2>
          <div className="search-form">
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Enter search terms..."
              className="search-input"
            />
            <button 
              onClick={() => searchDocuments(searchQuery)}
              disabled={isSearching}
            >
              {isSearching ? 'Searching...' : 'Search'}
            </button>
          </div>
        </section>

        {/* Results Section */}
        <section className="results-section">
          {searchResults.length > 0 ? (
            <div>
              <h2>Search Results for "{searchQuery}"</h2>
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
              <h2>All Documents</h2>
              {documents.map((doc) => (
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
          )}
        </section>
      </main>
    </div>
  );
}

export default App;
