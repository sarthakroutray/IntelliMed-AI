import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import { uploadDocument, getPatientDocuments, deleteDocument, shareDocument, unshareDocument, getSharedDoctors, getLinkedDoctors } from '../services/api';
import { useDropzone } from 'react-dropzone';
import Icon from '../components/Icon.jsx';
import GenerateAccessCode from '../components/GenerateAccessCode.jsx';

const PatientDashboard = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeTab, setActiveTab] = useState('all'); // all, shared, private
  const [showGenerateCodeModal, setShowGenerateCodeModal] = useState(false);
  const [linkedDoctors, setLinkedDoctors] = useState([]);
  const [loadingDoctors, setLoadingDoctors] = useState(false);
  const [analyzing, setAnalyzing] = useState(null);
  const [showShareModal, setShowShareModal] = useState(false);
  const [selectedDocumentForShare, setSelectedDocumentForShare] = useState(null);
  const [sharedDoctors, setSharedDoctors] = useState({});

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      // Refresh documents to get the latest analysis from server
      const response = await getPatientDocuments();
      setDocuments(response.data || []);
      
    } catch (err) {
      console.error('AI analysis failed', err);
      alert('AI analysis failed. Please try again.');
    } finally {
      setAnalyzing(null);
    }
  };

  const MAX_FILE_SIZE_MB = 10;
  const MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024;

  const onDrop = useCallback(async (acceptedFiles, rejectedFiles) => {
    // Handle rejected files (e.g. too large)
    if (rejectedFiles && rejectedFiles.length > 0) {
      const rejection = rejectedFiles[0];
      const isTooBig = rejection.errors?.some(e => e.code === 'file-too-large');
      setError(isTooBig
        ? `File is too large. Maximum allowed size is ${MAX_FILE_SIZE_MB} MB.`
        : 'File type not supported. Please upload a PDF, JPEG, PNG, or DICOM file.');
      return;
    }

    if (acceptedFiles.length === 0) return;

    setUploading(true);
    setError('');

    try {
      const uploadResponse = await uploadDocument(acceptedFiles[0]);
      console.log('Upload response:', uploadResponse);
      await fetchDocuments();
    } catch (err) {
      console.error('Upload error:', err);
      if (err.response?.status === 413) {
        setError(`File is too large. Maximum allowed size is ${MAX_FILE_SIZE_MB} MB.`);
      } else if (err.response?.data?.detail) {
        setError(err.response.data.detail);
      } else {
        setError('File upload failed. Please try again.');
      }
    } finally {
      setUploading(false);
    }
  }, []);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({ 
    onDrop,
    accept: {
      'application/pdf': ['.pdf'],
      'image/jpeg': ['.jpeg', '.jpg'],
      'image/png': ['.png'],
      'application/dicom': ['.dcm'],
    },
    multiple: false,
    maxSize: MAX_FILE_SIZE_BYTES,
  });

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
      const response = await getPatientDocuments();
      console.log('Documents response:', response);
      console.log('Documents data:', response.data);
      setDocuments(response.data || []);
      
      // Load shared doctors info for all documents in parallel
      if (response.data && response.data.length > 0) {
        const sharePromises = response.data.map(doc =>
          getSharedDoctors(doc.id)
            .then(res => [doc.id, res.data || []])
            .catch(() => [doc.id, []])
        );
        const shareResults = await Promise.all(sharePromises);
        const shareCounts = Object.fromEntries(shareResults);
        setSharedDoctors(shareCounts);
      }
    } catch (err) {
      console.error('Fetch documents error:', err);
      setError('Failed to fetch documents.');
    } finally {
      setLoading(false);
    }
  }, [user]);

  const fetchLinkedDoctors = useCallback(async () => {
    if (!user) return;
    try {
      setLoadingDoctors(true);
      const response = await getLinkedDoctors();
      setLinkedDoctors(response.data);
    } catch (err) {
      console.error('Failed to fetch linked doctors:', err);
      setLinkedDoctors([]);
    } finally {
      setLoadingDoctors(false);
    }
  }, [user]);

  useEffect(() => {
    fetchDocuments();
    fetchLinkedDoctors();
  }, [fetchDocuments, fetchLinkedDoctors]);

  const filteredDocuments = documents.filter(doc => {
    // Search filter
    const matchesSearch = doc.filename?.toLowerCase().includes(searchQuery.toLowerCase());
    
    // Tab filter (all, shared, private)
    // Note: Currently showing all as private since we don't have shared_with field
    const matchesTab = activeTab === 'all' || activeTab === 'private';
    
    return matchesSearch && matchesTab;
  });

  const getFileIcon = (filename) => {
    if (filename?.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400' };
    if (filename?.endsWith('.dcm')) return { icon: 'imagesmode', color: 'bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400' };
    return { icon: 'description', color: 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400' };
  };

  const getDocumentStatus = (doc) => {
    const isShared = sharedDoctors[doc.id] && sharedDoctors[doc.id].length > 0;
    if (isShared) {
      return (
        <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-blue-100 dark:bg-blue-900/30 border border-blue-200 dark:border-blue-800">
          <Icon name="share" className="text-[14px] text-blue-600 dark:text-blue-400" />
          <span className="text-xs font-medium text-blue-700 dark:text-blue-300">Shared ({sharedDoctors[doc.id].length})</span>
        </div>
      );
    }
    return (
      <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-gray-100 dark:bg-gray-700 border border-gray-200 dark:border-gray-600">
        <Icon name="lock" className="text-[14px] text-gray-500 dark:text-gray-400" />
        <span className="text-xs font-medium text-gray-600 dark:text-gray-300">Private</span>
      </div>
    );
  };

  const handleShareDocument = async (docId) => {
    setSelectedDocumentForShare(docId);
    try {
      const response = await getSharedDoctors(docId);
      setSharedDoctors(prev => ({
        ...prev,
        [docId]: response.data
      }));
    } catch (err) {
      console.error('Error fetching shared doctors:', err);
    }
    setShowShareModal(true);
  };

  const handleToggleShare = async (docId, doctorId, isShared) => {
    try {
      if (isShared) {
        await unshareDocument(docId, doctorId);
      } else {
        await shareDocument(docId, doctorId);
      }
      // Refresh shared doctors list
      const response = await getSharedDoctors(docId);
      setSharedDoctors(prev => ({
        ...prev,
        [docId]: response.data
      }));
    } catch (err) {
      console.error('Error toggling share:', err);
      alert('Failed to update document sharing');
    }
  };

  const handleDeleteDocument = async (docId) => {
    if (!window.confirm('Are you sure you want to delete this document? This action cannot be undone.')) return;
    
    try {
      await deleteDocument(docId);
      setDocuments(documents.filter(doc => doc.id !== docId));
    } catch (err) {
      setError('Failed to delete document.');
    }
  };

  return (
    <div className="flex-1 max-w-[1200px] w-full mx-auto p-4 md:p-8 flex flex-col gap-8">
      {/* Page Header */}
      <div className="flex flex-wrap justify-between items-end gap-4">
        <div className="flex flex-col gap-2">
          <h1 className="text-[#111318] dark:text-white text-3xl md:text-4xl font-black leading-tight tracking-[-0.033em]">
            My Medical Documents
          </h1>
          <p className="text-[#616f89] dark:text-gray-400 text-base font-normal">
            Manage, upload, and analyze your health records safely.
          </p>
        </div>
        <div className="hidden sm:block">
          <p className="text-sm font-medium text-[#616f89] dark:text-gray-400 text-right">
            Last login: Today, {new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
          </p>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-300 px-4 py-3 rounded-lg">
          {error}
        </div>
      )}

      {/* Upload Section (Drag & Drop) */}
      <div {...getRootProps()} className={`bg-white dark:bg-[#1A202C] rounded-xl border-2 border-dashed ${isDragActive ? 'border-primary' : 'border-primary/30 dark:border-primary/20'} hover:border-primary dark:hover:border-primary transition-colors cursor-pointer group`}>
        <input {...getInputProps()} />
        <div className="flex flex-col items-center justify-center py-10 px-6 text-center">
          <div className={`size-12 rounded-full bg-primary/10 flex items-center justify-center mb-4 ${uploading ? 'animate-pulse' : 'group-hover:scale-110'} transition-transform`}>
            {uploading ? (
              <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
            ) : (
              <Icon name="cloud_upload" className="text-primary text-2xl" />
            )}
          </div>
          <h3 className="text-lg font-bold text-[#111318] dark:text-white mb-2">
            {uploading ? 'Uploading...' : 'Upload New Medical Record'}
          </h3>
          <p className="text-sm text-[#616f89] dark:text-gray-400 mb-1 max-w-md">
            {isDragActive ? 'Drop your file here' : 'Drag & drop files here (PDF, JPG, DICOM), or click to browse. Files are encrypted before upload.'}
          </p>
          <p className="text-xs text-[#9aa3b0] dark:text-gray-500 mb-6">
            Maximum file size: {MAX_FILE_SIZE_MB} MB
          </p>
          {!isDragActive && !uploading && (
            <button className="flex items-center justify-center rounded-lg h-9 px-6 bg-primary text-white text-sm font-bold shadow-md shadow-primary/20 hover:bg-primary/90 transition-colors">
              Browse Files
            </button>
          )}
        </div>
      </div>

      {/* Filters & Controls */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div className="flex gap-2 p-1 bg-white dark:bg-[#1A202C] rounded-lg border border-[#dbdfe6] dark:border-gray-700">
          <button 
            onClick={() => setActiveTab('all')}
            className={`px-4 py-1.5 rounded-md text-sm font-bold transition-colors ${
              activeTab === 'all' ? 'bg-primary/10 text-primary' : 'text-[#616f89] dark:text-gray-400 hover:text-[#111318] dark:hover:text-white'
            }`}
          >
            All Documents
          </button>
          <button 
            onClick={() => setActiveTab('shared')}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-colors ${
              activeTab === 'shared' ? 'bg-primary/10 text-primary' : 'text-[#616f89] dark:text-gray-400 hover:text-[#111318] dark:hover:text-white'
            }`}
          >
            Shared
          </button>
          <button 
            onClick={() => setActiveTab('private')}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-colors ${
              activeTab === 'private' ? 'bg-primary/10 text-primary' : 'text-[#616f89] dark:text-gray-400 hover:text-[#111318] dark:hover:text-white'
            }`}
          >
            Private
          </button>
        </div>
        <div className="flex items-center gap-2 w-full sm:w-auto">
          <div className="relative w-full sm:w-64">
            <Icon name="search" className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-[20px]" />
            <input 
              className="w-full h-9 pl-10 pr-4 rounded-lg border border-[#dbdfe6] dark:border-gray-700 bg-white dark:bg-[#1A202C] text-sm focus:border-primary focus:ring-0 placeholder:text-gray-400 dark:text-white"
              placeholder="Search documents..."
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
          <button className="h-9 px-3 rounded-lg border border-[#dbdfe6] dark:border-gray-700 bg-white dark:bg-[#1A202C] text-gray-500 hover:text-primary transition-colors flex items-center justify-center">
            <Icon name="filter_list" />
          </button>
        </div>
      </div>

      {/* Documents Table */}
      <div className="bg-white dark:bg-[#1A202C] rounded-xl border border-[#dbdfe6] dark:border-gray-700 overflow-hidden shadow-sm">
        {loading ? (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-gray-50 dark:bg-gray-800/50 border-b border-[#dbdfe6] dark:border-gray-700">
                  <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Document Name</th>
                  <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Type</th>
                  <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Date</th>
                  <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Status</th>
                  <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#dbdfe6] dark:divide-gray-700">
                {[1, 2, 3, 4, 5].map(i => (
                  <tr key={i} className="animate-pulse">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
                        <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-40"></div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-12"></div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-24"></div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-6 bg-gray-200 dark:bg-gray-700 rounded-full w-20"></div>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
                        <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
                        <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                  <thead>
                    <tr className="bg-gray-50 dark:bg-gray-800/50 border-b border-[#dbdfe6] dark:border-gray-700">
                      <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Document Name</th>
                      <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Type</th>
                      <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Date</th>
                      <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider">Status</th>
                      <th className="px-6 py-4 text-xs font-bold text-[#616f89] dark:text-gray-400 uppercase tracking-wider text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#dbdfe6] dark:divide-gray-700">
                    {filteredDocuments.length > 0 ? filteredDocuments.map((doc) => {
                      const fileInfo = getFileIcon(doc.filename);
                      return (
                        <tr key={doc.id} className="group hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors">
                          <td className="px-6 py-4">
                            <div className="flex items-center gap-3">
                              <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                                <Icon name={fileInfo.icon} className="text-[20px]" />
                              </div>
                              <span className="text-sm font-bold text-[#111318] dark:text-white">{doc.filename}</span>
                            </div>
                          </td>
                          <td className="px-6 py-4 text-sm text-[#616f89] dark:text-gray-400">
                            {doc.filename?.split('.').pop().toUpperCase()}
                          </td>
                          <td className="px-6 py-4 text-sm text-[#616f89] dark:text-gray-400">
                            {doc.upload_timestamp ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                          </td>
                          <td className="px-6 py-4">
                            {getDocumentStatus(doc)}
                          </td>
                          <td className="px-6 py-4 text-right">
                            <div className="flex items-center justify-end gap-2">
                              <button 
                                onClick={() => handleShareDocument(doc.id)}
                                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[#dbdfe6] dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700 text-[#111318] dark:text-white text-xs font-bold transition-colors"
                                title="Share with doctors"
                              >
                                <Icon name="share" className="text-[16px]" />
                                Share
                              </button>
                              {doc.ai_analysis ? (
                                <button 
                                  onClick={() => navigate('/patient-dashboard/ai-analysis')}
                                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-[#dbdfe6] dark:border-gray-600 hover:bg-gray-50 dark:hover:bg-gray-700 text-[#111318] dark:text-white text-xs font-bold transition-colors"
                                >
                                  <Icon name="visibility" className="text-[16px]" />
                                  View
                                </button>
                              ) : (
                                <button 
                                  onClick={() => handleAnalyze(doc.id)}
                                  disabled={analyzing === doc.id}
                                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 hover:bg-primary/20 text-primary text-xs font-bold transition-colors disabled:opacity-50"
                                >
                                  {analyzing === doc.id ? (
                                    <>
                                      <div className="animate-spin rounded-full h-3 w-3 border-b-2 border-primary"></div>
                                      <span>Analyzing...</span>
                                    </>
                                  ) : (
                                    <>
                                      <Icon name="smart_toy" className="text-[16px]" />
                                      <span>Analyze</span>
                                    </>
                                  )}
                                </button>
                              )}
                              <button 
                                onClick={() => handleDeleteDocument(doc.id)}
                                className="size-8 flex items-center justify-center rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-600 dark:hover:text-red-400 transition-colors"
                                title="Delete document"
                              >
                                <Icon name="delete" className="text-[20px]" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    }) : (
                      <tr>
                        <td colSpan="5" className="py-12 text-center">
                          <div className="flex flex-col items-center gap-3">
                            <Icon name="description" className="text-[48px] text-gray-300 dark:text-gray-600" />
                            <p className="text-[#637588] dark:text-gray-400">No documents found</p>
                          </div>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </div>
          
          <div className="text-center pb-8">
            <p className="text-xs text-[#616f89] dark:text-gray-500">
              IntelliMed-AI complies with HIPAA standards. All your documents are end-to-end encrypted.
            </p>
          </div>

        {/* Generate Access Code Modal */}
        {showGenerateCodeModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowGenerateCodeModal(false)}>
            <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()}>
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-bold text-[#111318] dark:text-white">Connect with Doctor</h3>
                <button onClick={() => setShowGenerateCodeModal(false)} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
                  <Icon name="close" className="text-[24px]" />
                </button>
              </div>
              <GenerateAccessCode />
            </div>
          </div>
        )}

        {/* Share Document Modal */}
        {showShareModal && selectedDocumentForShare && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowShareModal(false)}>
            <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()}>
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-bold text-[#111318] dark:text-white">Share Document</h3>
                <button onClick={() => setShowShareModal(false)} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
                  <Icon name="close" className="text-[24px]" />
                </button>
              </div>
              
              {linkedDoctors.length === 0 ? (
                <div className="text-center py-8">
                  <Icon name="person_add" className="text-[48px] text-gray-300 dark:text-gray-600 mx-auto mb-4" />
                  <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">No linked doctors yet</p>
                  <button 
                    onClick={() => {
                      setShowShareModal(false);
                      setShowGenerateCodeModal(true);
                    }}
                    className="px-4 py-2 bg-primary text-white rounded-lg hover:bg-blue-700 text-sm font-bold"
                  >
                    Generate Access Code
                  </button>
                </div>
              ) : (
                <div className="space-y-3 max-h-96 overflow-y-auto">
                  {linkedDoctors.map(doctor => {
                    const isSharedWithDoctor = sharedDoctors[selectedDocumentForShare]?.some(sd => sd.doctor_id === doctor.id) || false;
                    return (
                      <div key={doctor.id} className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-800 rounded-lg">
                        <div>
                          <p className="text-sm font-medium text-[#111318] dark:text-white">{doctor.email}</p>
                          <p className="text-xs text-gray-500 dark:text-gray-400">Doctor</p>
                        </div>
                        <button
                          onClick={() => handleToggleShare(selectedDocumentForShare, doctor.id, isSharedWithDoctor)}
                          className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-colors ${
                            isSharedWithDoctor
                              ? 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 hover:bg-red-200 dark:hover:bg-red-900/50'
                              : 'bg-green-100 dark:bg-green-900/30 text-green-600 dark:text-green-400 hover:bg-green-200 dark:hover:bg-green-900/50'
                          }`}
                        >
                          {isSharedWithDoctor ? 'Unshare' : 'Share'}
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    );
  };
  
  export default PatientDashboard;