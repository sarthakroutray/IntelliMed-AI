import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { uploadDocument, getPatientDocuments, deleteDocument } from '../services/api';
import { useDropzone } from 'react-dropzone';
import '../styles/PatientDashboard.css';
import GenerateAccessCode from '../components/GenerateAccessCode.jsx';

const PatientDashboard = () => {
  const { user } = useAuth();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [selectedFile, setSelectedFile] = useState(null);
  const [loading, setLoading] = useState(true);

  const onDrop = useCallback((acceptedFiles) => {
    setSelectedFile(acceptedFiles[0]);
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({ 
    onDrop,
    accept: {
      'application/pdf': ['.pdf'],
      'image/jpeg': ['.jpeg', '.jpg'],
      'image/png': ['.png'],
    },
    multiple: false,
  });

  const handleUpload = async () => {
    if (!selectedFile) return;

    setUploading(true);
    setError('');

    try {
      await uploadDocument(selectedFile);
      await fetchDocuments(); // Refresh document list
      setSelectedFile(null); // Clear selected file
      setError(''); // Clear any previous errors
    } catch (err) {
      setError('File upload failed. Please try again.');
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (documentId) => {
    if (!window.confirm('Are you sure you want to delete this document?')) return;
    
    try {
      await deleteDocument(documentId);
      setDocuments(documents.filter(doc => doc.id !== documentId));
    } catch (err) {
      setError('Failed to delete document.');
    }
  };

  const fetchDocuments = useCallback(async () => {
    if (!user) return;
    try {
      setLoading(true);
      // The backend should infer the user from the token
      const response = await getPatientDocuments(); 
      setDocuments(response.data);
    } catch (err) {
      setError('Failed to fetch documents.');
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    fetchDocuments();
  }, [fetchDocuments]);

  return (
    <div className="dashboard-container">
      <header className="dashboard-header">
        <div className="header-content">
          <div>
            <h1>Welcome, {user?.email?.split('@')[0]}!</h1>
            <p>This is your personal health dashboard. Upload and manage your medical documents securely.</p>
          </div>
          <div className="stats-container">
            <div className="stat-card">
              <div className="stat-icon">Docs</div>
              <div className="stat-info">
                <div className="stat-value">{documents.length}</div>
                <div className="stat-label">Documents</div>
              </div>
            </div>
          </div>
        </div>
      </header>

      {error && (
        <div className="error-message">
          <span className="error-icon">⚠</span>
          {error}
        </div>
      )}

      <div className="dashboard-grid">
        <div className="dashboard-card upload-card">
          <div className="card-header">
            <h2>Upload New Document</h2>
            <p className="card-subtitle">Share your medical records securely</p>
          </div>
          <div {...getRootProps()} className={`upload-area ${isDragActive ? 'active' : ''} ${selectedFile ? 'has-file' : ''}`}>
            <input {...getInputProps()} />
            <div className="upload-icon">
              {selectedFile ? '✓' : '+'}
            </div>
            {selectedFile ? (
              <div className="selected-file">
                <p className="file-name">{selectedFile.name}</p>
                <p className="file-size">{(selectedFile.size / 1024).toFixed(2)} KB</p>
              </div>
            ) : isDragActive ? (
              <p className="upload-text">Drop the file here...</p>
            ) : (
              <div className="upload-prompt">
                <p className="upload-text">Drag & drop your document here</p>
                <p className="upload-hint">or click to browse</p>
                <p className="upload-formats">Supported: PDF, JPG, PNG</p>
              </div>
            )}
          </div>
          <button 
            onClick={handleUpload} 
            disabled={uploading || !selectedFile} 
            className="upload-button"
          >
            {uploading ? (
              <>
                <span className="spinner-small"></span>
                <span>Uploading...</span>
              </>
            ) : (
              <>
                <span>Upload Document</span>
              </>
            )}
          </button>
        </div>

        <div className="dashboard-card documents-card full-width">
          <div className="card-header">
            <h2>Your Documents</h2>
            <p className="card-subtitle">{documents.length} document{documents.length !== 1 ? 's' : ''} uploaded</p>
          </div>
          {loading ? (
            <div className="loading-container">
              <div className="spinner"></div>
              <p>Loading documents...</p>
            </div>
          ) : documents.length > 0 ? (
            <div className="document-list">
              {documents.map((doc) => (
                <div key={doc.id} className="document-item">
                  <div className="document-header">
                    <div className="document-icon">Doc</div>
                    <div className="document-info">
                      <h3>{doc.filename}</h3>
                      <p className="upload-date">
                        {new Date(doc.upload_timestamp).toLocaleDateString('en-US', {
                          year: 'numeric',
                          month: 'long',
                          day: 'numeric'
                        })}
                      </p>
                    </div>
                    <button 
                      className="delete-button"
                      onClick={() => handleDelete(doc.id)}
                      title="Delete Document"
                    >
                      🗑️
                    </button>
                  </div>
                  {doc.ai_analysis && (
                    <div className="analysis-section">
                      <div className="analysis-header">
                        <h4>AI Analysis</h4>
                        <span className="analysis-badge">Completed</span>
                      </div>
                      <div className="analysis-content">
                        {JSON.stringify(doc.ai_analysis, null, 2)}
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">
              <div className="empty-icon">—</div>
              <p>No documents uploaded yet</p>
              <span className="empty-hint">Upload your first document to get started</span>
            </div>
          )}
        </div>

        <div className="dashboard-card">
          <GenerateAccessCode />
        </div>
      </div>
    </div>
  );
};

export default PatientDashboard;

