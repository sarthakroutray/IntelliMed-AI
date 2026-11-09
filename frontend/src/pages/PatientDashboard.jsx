import React, { useState, useCallback, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import Icon from '../components/Icon';
import { uploadDocument, getPatientDocuments, deleteDocument, shareDocument, unshareDocument, getSharedDoctors, getLinkedDoctors, analyzeDocument } from '../services/api';
import { useDropzone } from 'react-dropzone';
import { Alert, Modal, ConfirmDialog, Toast, Spinner, EmptyState } from '../components/ui.jsx';
import ShareDocumentModal from '../components/ShareDocumentModal.jsx';
import { ui } from '../styles/ui.js';

const PatientDashboard = () => {
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeTab, setActiveTab] = useState('all');
  const [analyzing, setAnalyzing] = useState(null);
  const [sharedDoctors, setSharedDoctors] = useState({});
  const [pendingDelete, setPendingDelete] = useState(null);
  const [sharingDocument, setSharingDocument] = useState(null);
  const [toast, setToast] = useState(null);

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
  const onDrop = useCallback(async (acceptedFiles, rejectedFiles) => {
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
          getSharedDoctors(doc.id).then(res => [doc.id, res.data || []]).catch(() => [doc.id, []])
        );
        const shareResults = await Promise.all(sharePromises);
        setSharedDoctors(Object.fromEntries(shareResults));
      }
    } catch (err) {
      console.error('Upload error:', err);
      if (err.response?.status === 413) {
        setError(`File is too large. Maximum allowed size is ${MAX_FILE_SIZE_MB} MB.`);
      } else if (err.code === 'ECONNABORTED') {
        setError('The upload timed out. Please check your connection and try again with a smaller file.');
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
    maxSize: MAX_FILE_SIZE_MB * 1024 * 1024,
  });

  const fetchDocuments = useCallback(async () => {
    try {
      const response = await getPatientDocuments();
      setDocuments(response.data || []);
      if (response.data && response.data.length > 0) {
        const sharePromises = response.data.map(doc =>
          getSharedDoctors(doc.id)
            .then(res => [doc.id, res.data || []])
            .catch(() => [doc.id, []])
        );
        const shareResults = await Promise.all(sharePromises);
        setSharedDoctors(Object.fromEntries(shareResults));
      }
    } catch (err) {
      console.error('Fetch documents error:', err);
      setError('Failed to fetch documents.');
    }
  }, []);

  useEffect(() => {
    fetchDocuments();
  }, [fetchDocuments]);

  const filteredDocuments = documents.filter(doc => {
    const matchesSearch = doc.filename?.toLowerCase().includes(searchQuery.toLowerCase());
    const isShared = Boolean(sharedDoctors[doc.id] && sharedDoctors[doc.id].length > 0);
    const matchesTab =
      activeTab === 'all' ||
      (activeTab === 'shared' && isShared) ||
      (activeTab === 'private' && !isShared);
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
          <Icon name="share" className="text-[13px]" />
          <span>Shared ({sharedDoctors[doc.id].length})</span>
        </div>
      );
    }
    return (
      <div className={`${ui.badge} ${ui.badgeNeutral}`}>
        <Icon name="lock" className="text-[13px]" />
        <span>Private</span>
      </div>
    );
  };

  const handleShareDocument = (doc) => {
    const targetDoc =
      typeof doc === 'object' && doc !== null
        ? doc
        : documents.find((d) => d.id === doc) || { id: doc };
    setSharingDocument(targetDoc);
  };

  const handleDeleteDocument = async (docId) => {
    setDocuments(prev => prev.filter(doc => doc.id !== docId));
    setSharedDoctors(prev => {
      const next = { ...prev };
      delete next[docId];
      return next;
    });
    try {
      await deleteDocument(docId);
      await fetchDocuments();
    } catch (err) {
      console.error('Delete error:', err);
      setError('Failed to delete document.');
      await fetchDocuments();
    }
  };

  return (
    <div className={ui.page}>
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <p className="ledger-label text-muted">Patient records</p>
          <h1 className={`${ui.pageTitle} mt-2`}>
            My medical documents
          </h1>
          <p className={ui.pageSubtitle}>
            Manage, upload, and analyze your health records safely.
          </p>
        </div>
      </div>

      {error && (
        <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>
      )}

      <div {...getRootProps()} className={`bg-surface rounded-xl border border-dashed ${isDragActive ? 'border-primary bg-primary/5' : 'border-line'} hover:border-primary transition-colors cursor-pointer group`}>
        <input aria-label="Upload medical record" {...getInputProps()} />
        <div className="flex flex-col sm:flex-row items-center gap-5 px-6 py-7 text-center sm:text-left">
          <div className={`size-11 rounded border border-line bg-surface-2 flex items-center justify-center shrink-0 ${uploading ? 'animate-pulse' : 'group-hover:border-primary/40'} transition-colors`}>
            {uploading ? (
              <Spinner className="size-5" />
            ) : (
              <Icon name="cloud_upload" className="text-primary text-[22px]" />
            )}
          </div>
          <div className="flex-1 min-w-0">
            <h3 className="font-serif text-lg font-semibold text-ink">
              {uploading
                ? (uploadProgress < 100 ? `Uploading... ${uploadProgress}%` : 'Finishing upload...')
                : 'Upload new medical record'}
            </h3>
            <p className="text-sm text-muted mt-1">
              {isDragActive ? 'Drop your file here' : `Drag & drop a file here (PDF, JPG, DICOM), or click to browse. Max ${MAX_FILE_SIZE_MB} MB. Files are encrypted before upload.`}
            </p>
            {uploading && (
              <div className="w-full max-w-md h-1 rounded-full bg-surface-2 overflow-hidden mt-3">
                <div
                  className="h-full rounded-full bg-primary transition-[width] duration-300"
                  style={{ width: `${Math.max(uploadProgress, 5)}%` }}
                />
              </div>
            )}
          </div>
          {!isDragActive && !uploading && (
            <button type="button" className={`${ui.btn} ${ui.btnPrimary} shrink-0 pointer-events-none`}>
              Browse files
            </button>
          )}
        </div>
      </div>

      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div className="flex gap-1 p-1 bg-surface border border-line rounded">
          {['all', 'shared', 'private'].map((tab) => (
            <button
              key={tab}
              type="button"
              onClick={() => setActiveTab(tab)}
              className={`px-4 py-2 rounded text-[13px] font-semibold transition-colors ${
                activeTab === tab ? 'bg-primary/10 text-primary' : 'text-muted hover:text-ink'
              }`}
            >
              {tab === 'all' ? 'All documents' : tab.charAt(0).toUpperCase() + tab.slice(1)}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2 w-full sm:w-auto">
          <div className="relative w-full sm:w-64">
            <Icon name="search" className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle text-[20px]" />
            <input
              aria-label="Search documents"
              className={ui.inputIcon}
              placeholder="Search documents..."
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>
          <button type="button" aria-label="Filter documents" className={`${ui.btn} ${ui.btnSecondary} size-10 !px-0`}>
            <Icon name="filter_list" />
          </button>
        </div>
      </div>

      <div className={`${ui.card} overflow-hidden`}>
        {filteredDocuments.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr>
                  <th className={ui.th}>Document name</th>
                  <th className={ui.th}>Type</th>
                  <th className={ui.th}>Date</th>
                  <th className={ui.th}>Status</th>
                  <th className={`${ui.th} text-right`}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredDocuments.map((doc) => {
                  const fileInfo = getFileIcon(doc.filename);
                  return (
                    <tr key={doc.id} className={`${ui.tr} group`}>
                      <td className="px-5 md:px-6 py-4">
                        <div className="flex items-center gap-3">
                          <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                            <Icon name={fileInfo.icon} className="text-[19px]" />
                          </div>
                          <span className="text-sm font-semibold text-ink">{doc.filename}</span>
                        </div>
                      </td>
                      <td className={`${ui.td} font-mono text-xs text-muted uppercase`}>
                        {doc.filename?.split('.').pop().toUpperCase()}
                      </td>
                      <td className={`${ui.td} font-mono text-xs text-muted tnum`}>
                        {doc.upload_timestamp
                          ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', {
                              month: 'short',
                              day: 'numeric',
                              year: 'numeric',
                            })
                          : 'N/A'}
                      </td>
                      <td className="px-5 md:px-6 py-4">{getDocumentStatus(doc)}</td>
                      <td className="px-5 md:px-6 py-4 text-right">
                        <div className="flex items-center justify-end gap-2">
                          <button
                            type="button"
                            onClick={() => handleShareDocument(doc)}
                            className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                          >
                            <Icon name="share" className="text-[15px]" />
                            Share
                          </button>
                          {doc.ai_analysis ? (
                            <button
                              type="button"
                              onClick={() => navigate(`/document/${doc.id}`)}
                              className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                            >
                              <Icon name="visibility" className="text-[15px]" />
                              View
                            </button>
                          ) : (
                            <button
                              type="button"
                              onClick={() => handleAnalyze(doc.id)}
                              disabled={analyzing === doc.id}
                              className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                            >
                              {analyzing === doc.id ? (
                                <Spinner className="size-3" />
                              ) : (
                                <><Icon name="smart_toy" className="text-[15px]" />Analyze</>
                              )}
                            </button>
                          )}
                          <button
                            type="button"
                            onClick={() => setPendingDelete(doc.id)}
                            className="size-9 flex items-center justify-center rounded hover:bg-danger/10 text-subtle hover:text-danger"
                          >
                            <Icon name="delete" className="text-[19px]" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState icon="description" title="No documents found" hint="Upload a medical record to get started." />
        )}
      </div>

      <div className="text-center pb-8">
        <p className="text-xs text-subtle">
          IntelliMed-AI complies with HIPAA standards. All your documents are end-to-end encrypted.
        </p>
      </div>

      {/* Share Document Modal */}
      <ShareDocumentModal
        open={Boolean(sharingDocument)}
        onClose={() => setSharingDocument(null)}
        document={sharingDocument}
        initialSharedDoctors={sharingDocument ? sharedDoctors[sharingDocument.id] : []}
        onShareChange={(docId, updated) => {
          setSharedDoctors(prev => ({
            ...prev,
            [docId]: updated,
          }));
        }}
      />

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        open={Boolean(pendingDelete)}
        title="Delete Document"
        message="Are you sure you want to delete this document? This action cannot be undone."
        confirmLabel="Delete"
        danger
        onConfirm={async () => {
          const docId = pendingDelete;
          setPendingDelete(null);
          await handleDeleteDocument(docId);
        }}
        onCancel={() => setPendingDelete(null)}
      />

      {/* Toast Notification */}
      {toast && (
        <Toast
          message={toast.message}
          type={toast.type}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
};

export default PatientDashboard;
