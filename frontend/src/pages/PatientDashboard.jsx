import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import { uploadDocument, getPatientDocuments, deleteDocument, shareDocument, unshareDocument, getSharedDoctors, getLinkedDoctors, analyzeDocument } from '../services/api';
import { useDropzone } from 'react-dropzone';
import Icon from '../components/Icon.jsx';
import GenerateAccessCode from '../components/GenerateAccessCode.jsx';
import { Alert, Modal, ConfirmDialog, Toast, Spinner, EmptyState } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const PatientDashboard = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
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
  const [toast, setToast] = useState(null);
  const [pendingDelete, setPendingDelete] = useState(null);

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      await analyzeDocument(docId);
      await fetchDocuments();
    } catch (err) {
      console.error('AI analysis failed', err);
      setToast({ type: 'error', message: err.response?.data?.detail || 'AI analysis failed. Please try again.' });
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
    setUploadProgress(0);

    try {
      const uploadResponse = await uploadDocument(acceptedFiles[0], (progressEvent) => {
        if (!progressEvent.total) return;
        const percent = Math.round((progressEvent.loaded * 100) / progressEvent.total);
        setUploadProgress(Math.min(percent, 99));
      });
      setUploadProgress(100);
      const refreshed = await getPatientDocuments();
      setDocuments(refreshed.data || []);

      if (refreshed.data && refreshed.data.length > 0) {
        const sharePromises = refreshed.data.map(doc =>
          getSharedDoctors(doc.id)
            .then(res => [doc.id, res.data || []])
            .catch(() => [doc.id, []])
        );
        const shareResults = await Promise.all(sharePromises);
        setSharedDoctors(Object.fromEntries(shareResults));
      }
    } catch (err) {
      console.error('Upload error:', err);
      if (err.response?.status === 413) {
        setError(`File is too large. Maximum allowed size is ${MAX_FILE_SIZE_MB} MB.`);
      } else if (err.code === 'ECONNABORTED') {
        setError('The upload timed out before the server finished processing. Please try again — large scanned documents can take a few minutes to analyze.');
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

  const fetchDocuments = useCallback(async () => {
    if (!user) return;
    try {
      setLoading(true);
      const response = await getPatientDocuments();
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
    if (filename?.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger' };
    if (filename?.endsWith('.dcm')) return { icon: 'imagesmode', color: 'bg-primary/10 text-primary' };
    return { icon: 'description', color: 'bg-surface-2 text-muted' };
  };

  const getDocumentStatus = (doc) => {
    const isShared = sharedDoctors[doc.id] && sharedDoctors[doc.id].length > 0;
    if (isShared) {
      return (
        <div className={`${ui.badge} ${ui.badgeInfo}`}>
          <Icon name="share" className="text-[14px]" />
          <span>Shared ({sharedDoctors[doc.id].length})</span>
        </div>
      );
    }
    return (
      <div className={`${ui.badge} ${ui.badgeNeutral}`}>
        <Icon name="lock" className="text-[14px]" />
        <span>Private</span>
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
      setToast({ type: 'error', message: 'Failed to update document sharing' });
    }
  };

  const handleDeleteDocument = async (docId) => {
    // Optimistically remove from UI first for immediate feedback.
    setDocuments(prev => prev.filter(doc => doc.id !== docId));
    setSharedDoctors(prev => {
      const next = { ...prev };
      delete next[docId];
      return next;
    });

    try {
      await deleteDocument(docId);

      // Re-sync from backend to avoid drift when cache or network timing is involved.
      await fetchDocuments();
    } catch (err) {
      console.error('Delete error:', err);
      setError('Failed to delete document.');

      // Attempt to recover UI state from source of truth if delete fails.
      await fetchDocuments();
    }
  };

  return (
    <div className={ui.page}>
      {/* Page Header */}
      <div className={ui.pageHeader}>
        <div className="flex flex-col gap-2">
          <h1 className={ui.pageTitle}>
            My Medical Documents
          </h1>
          <p className={ui.pageSubtitle}>
            Manage, upload, and analyze your health records safely.
          </p>
        </div>
        <div className="hidden sm:block">
          <p className="text-sm font-medium text-muted text-right">
            Last login: Today, {new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
          </p>
        </div>
      </div>

      {error && (
        <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>
      )}

      {/* Upload Section (Drag & Drop) */}
      <div {...getRootProps()} className={`bg-surface rounded-2xl border-2 border-dashed ${isDragActive ? 'border-primary' : 'border-line'} hover:border-primary transition-colors cursor-pointer group shadow-card`}>
        <input aria-label="Upload medical record" {...getInputProps()} />
        <div className="flex flex-col items-center justify-center py-10 px-6 text-center">
          <div className={`size-12 rounded-full bg-primary/10 flex items-center justify-center mb-4 ${uploading ? 'animate-pulse' : 'group-hover:scale-110'} transition-transform`}>
            {uploading ? (
              <Spinner className="size-6" />
            ) : (
              <Icon name="cloud_upload" className="text-primary text-2xl" />
            )}
          </div>
          <h3 className="text-lg font-bold text-ink mb-2">
            {uploading
              ? (uploadProgress < 100 ? `Uploading... ${uploadProgress}%` : 'Analyzing document...')
              : 'Upload New Medical Record'}
          </h3>
          {uploading && (
            <div className="w-full max-w-md h-2 rounded-full bg-surface-2 overflow-hidden mb-4">
              <div
                className="h-full rounded-full bg-primary transition-[width] duration-300"
                style={{ width: `${Math.max(uploadProgress, 5)}%` }}
              />
            </div>
          )}
          <p className="text-sm text-muted mb-1 max-w-md">
            {isDragActive ? 'Drop your file here' : 'Drag & drop files here (PDF, JPG, DICOM), or click to browse. Files are encrypted before upload.'}
          </p>
          <p className="text-xs text-subtle mb-6">
            Maximum file size: {MAX_FILE_SIZE_MB} MB
          </p>
          {!isDragActive && !uploading && (
            <button type="button" className={`${ui.btn} ${ui.btnPrimary}`}>
              Browse Files
            </button>
          )}
        </div>
      </div>

      {/* Filters & Controls */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div className="flex gap-2 p-1 bg-surface border border-line rounded-xl">
          {['all', 'shared', 'private'].map((tab) => (
            <button type="button"
              key={tab}
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-1.5 rounded-lg text-sm font-bold transition-colors ${
                activeTab === tab ? 'bg-primary/10 text-primary' : 'text-muted hover:text-ink'
              }`}
            >
              {tab === 'all' ? 'All Documents' : tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2 w-full sm:w-auto">
          <div className="relative w-full sm:w-64">
            <Icon name="search" className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle text-[20px]" />
            <input aria-label="Search documents"
              className={ui.inputIcon}
              placeholder="Search documents..."
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
          <button type="button" className={`${ui.btn} ${ui.btnSecondary} size-9 !px-0`}>
            <Icon name="filter_list" />
          </button>
        </div>
      </div>

      {/* Documents Table */}
      <div className={`${ui.card} overflow-hidden`}>
        {loading ? (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="bg-surface-2/60 border-b border-line">
                  <th className={ui.th}>Document Name</th>
                  <th className={ui.th}>Type</th>
                  <th className={ui.th}>Date</th>
                  <th className={ui.th}>Status</th>
                  <th className={`${ui.th} text-right`}>Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {[1, 2, 3, 4, 5].map(i => (
                  <tr key={i} className="animate-pulse">
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className="size-8 bg-surface-2 rounded"></div>
                        <div className="h-4 bg-surface-2 rounded w-40"></div>
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-4 bg-surface-2 rounded w-12"></div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-4 bg-surface-2 rounded w-24"></div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="h-6 bg-surface-2 rounded-full w-20"></div>
                    </td>
                    <td className="px-6 py-4 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <div className="size-8 bg-surface-2 rounded"></div>
                        <div className="size-8 bg-surface-2 rounded"></div>
                        <div className="size-8 bg-surface-2 rounded"></div>
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
                    <tr className="bg-surface-2/60 border-b border-line">
                      <th className={ui.th}>Document Name</th>
                      <th className={ui.th}>Type</th>
                      <th className={ui.th}>Date</th>
                      <th className={ui.th}>Status</th>
                      <th className={`${ui.th} text-right`}>Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-line">
                    {filteredDocuments.length > 0 ? filteredDocuments.map((doc) => {
                      const fileInfo = getFileIcon(doc.filename);
                      return (
                        <tr key={doc.id} className="group hover:bg-surface-2/60 transition-colors">
                          <td className="px-6 py-4">
                            <div className="flex items-center gap-3">
                              <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                                <Icon name={fileInfo.icon} className="text-[20px]" />
                              </div>
                              <span className="text-sm font-bold text-ink">{doc.filename}</span>
                            </div>
                          </td>
                          <td className={`${ui.td} text-muted`}>
                            {doc.filename?.split('.').pop().toUpperCase()}
                          </td>
                          <td className={`${ui.td} text-muted`}>
                            {doc.upload_timestamp ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                          </td>
                          <td className="px-5 md:px-6 py-4">
                            {getDocumentStatus(doc)}
                          </td>
                          <td className="px-5 md:px-6 py-4 text-right">
                            <div className="flex items-center justify-end gap-2">
                              <button type="button"
                                onClick={() => handleShareDocument(doc.id)}
                                className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                                title="Share with doctors"
                              >
                                <Icon name="share" className="text-[16px]" />
                                Share
                              </button>
                              {doc.ai_analysis ? (
                                <button type="button"
                                  onClick={() => navigate('/patient-dashboard/ai-analysis')}
                                  className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                                >
                                  <Icon name="visibility" className="text-[16px]" />
                                  View
                                </button>
                              ) : (
                                <button type="button"
                                  onClick={() => handleAnalyze(doc.id)}
                                  disabled={analyzing === doc.id}
                                  className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                                >
                                  {analyzing === doc.id ? (
                                    <>
                                      <Spinner className="size-3" />
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
                              <button type="button"
                                onClick={() => setPendingDelete(doc.id)}
                                className="size-8 flex items-center justify-center rounded-lg hover:bg-danger/10 text-subtle hover:text-danger transition-colors"
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
                        <td colSpan="5">
                          <EmptyState icon="description" title="No documents found" hint="Upload a medical record to get started." />
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </div>
          
          <div className="text-center pb-8">
            <p className="text-xs text-muted">
              IntelliMed-AI complies with HIPAA standards. All your documents are end-to-end encrypted.
            </p>
          </div>

        {/* Generate Access Code Modal */}
        <Modal
          open={showGenerateCodeModal}
          onClose={() => setShowGenerateCodeModal(false)}
          title="Connect with Doctor"
        >
          <GenerateAccessCode />
        </Modal>

        {/* Share Document Modal */}
        <Modal
          open={showShareModal && !!selectedDocumentForShare}
          onClose={() => setShowShareModal(false)}
          title="Share Document"
        >
          {linkedDoctors.length === 0 ? (
            <div className="text-center py-6">
              <EmptyState
                icon="person_add"
                title="No linked doctors yet"
                action={
                  <button type="button"
                    onClick={() => {
                      setShowShareModal(false);
                      setShowGenerateCodeModal(true);
                    }}
                    className={`${ui.btn} ${ui.btnPrimary} mt-2`}
                  >
                    Generate Access Code
                  </button>
                }
              />
            </div>
          ) : (
            <div className="space-y-3 max-h-96 overflow-y-auto">
              {linkedDoctors.map(doctor => {
                const isSharedWithDoctor = sharedDoctors[selectedDocumentForShare]?.some(sd => sd.doctor_id === doctor.id) || false;
                return (
                  <div key={doctor.id} className="flex items-center justify-between p-3 bg-surface-2 rounded-lg">
                    <div>
                      <p className="text-sm font-medium text-ink">{doctor.email}</p>
                      <p className="text-xs text-muted">Doctor</p>
                    </div>
                    <button type="button"
                      onClick={() => handleToggleShare(selectedDocumentForShare, doctor.id, isSharedWithDoctor)}
                      className={`${ui.btn} ${ui.btnSm} ${isSharedWithDoctor ? ui.btnSoftDanger : 'bg-success/10 hover:bg-success/20 text-success px-3 py-1.5'}`}
                    >
                      {isSharedWithDoctor ? 'Unshare' : 'Share'}
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </Modal>

        {/* Delete Confirmation */}
        <ConfirmDialog
          open={pendingDelete !== null}
          title="Delete document?"
          message="Are you sure you want to delete this document? This action cannot be undone."
          confirmLabel="Delete"
          danger
          onConfirm={() => {
            handleDeleteDocument(pendingDelete);
            setPendingDelete(null);
          }}
          onCancel={() => setPendingDelete(null)}
        />

        <Toast
          message={toast?.message}
          type={toast?.type}
          onClose={() => setToast(null)}
        />
      </div>
    );
  };

  export default PatientDashboard;