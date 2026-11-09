import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { getDoctorDocuments, analyzeDocument } from '../services/api';
import Icon from '../components/Icon';
import { Alert, EmptyState, Spinner, Toast } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const DoctorDocuments = ({ refreshKey = 0 }) => {
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [analyzing, setAnalyzing] = useState(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [toast, setToast] = useState(null);

  const fetchDocuments = useCallback(async () => {
    try {
      setLoading(true);
      setError('');
      const res = await getDoctorDocuments();
      setDocuments(res.data || []);
    } catch (err) {
      console.error('Fetch doctor documents failed:', err);
      setError(err.response?.data?.detail || 'Failed to load shared documents.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDocuments();
  }, [fetchDocuments, refreshKey]);

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      await analyzeDocument(docId);
      await fetchDocuments();
      setToast({ type: 'success', message: 'AI analysis completed successfully!' });
    } catch (err) {
      console.error('Analysis failed', err);
      const detail = err.response?.data?.detail;
      const message = typeof detail === 'string'
        ? detail
        : 'AI analysis failed. Please try again.';
      setToast({ type: 'error', message });
    } finally {
      setAnalyzing(null);
    }
  };

  const getFileIcon = (filename) => {
    const lower = (filename || '').toLowerCase();
    if (lower.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger', type: 'pdf' };
    if (lower.endsWith('.dcm') || lower.endsWith('.dicom')) return { icon: 'medical_services', color: 'bg-primary/10 text-primary', type: 'dicom' };
    if (lower.match(/\.(jpg|jpeg|png|webp)$/)) return { icon: 'image', color: 'bg-info/10 text-info', type: 'image' };
    return { icon: 'description', color: 'bg-surface-2 text-muted', type: 'other' };
  };

  const filteredDocuments = useMemo(() => {
    return documents.filter((doc) => {
      const { type } = getFileIcon(doc.filename);
      const matchesType = typeFilter === 'all' || type === typeFilter;
      const q = searchQuery.toLowerCase();
      const matchesSearch =
        !q ||
        doc.filename?.toLowerCase().includes(q) ||
        doc.patient_email?.toLowerCase().includes(q) ||
        doc.patient_name?.toLowerCase().includes(q);
      return matchesType && matchesSearch;
    });
  }, [documents, typeFilter, searchQuery]);

  return (
    <div className={`${ui.page} overflow-y-auto`}>
      {/* Header */}
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <p className="ledger-label text-muted">Physician records</p>
          <h1 className={`${ui.pageTitle} mt-2`}>Shared Patient Documents</h1>
          <p className={ui.pageSubtitle}>
            Review, analyze, and sign off on medical records shared by your linked patients.
          </p>
        </div>
      </div>

      {error && <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>}

      {/* Toolbar / Filters */}
      <div className="flex flex-col sm:flex-row gap-4 items-stretch sm:items-center justify-between">
        <div className="relative flex-1 max-w-md">
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Icon name="search" className="text-muted text-[20px]" />
          </div>
          <input
            aria-label="Search documents"
            className={ui.inputIcon}
            placeholder="Search by filename, patient email or name..."
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        <div className="flex items-center gap-2 overflow-x-auto pb-1 sm:pb-0">
          {[
            { id: 'all', label: 'All files' },
            { id: 'pdf', label: 'PDFs' },
            { id: 'dicom', label: 'DICOM' },
            { id: 'image', label: 'Images' },
          ].map((tab) => (
            <button
              type="button"
              key={tab.id}
              onClick={() => setTypeFilter(tab.id)}
              className={`${ui.btn} ${
                typeFilter === tab.id
                  ? 'bg-primary text-white border-primary'
                  : `${ui.btnSecondary}`
              } ${ui.btnSm}`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {/* Documents Table Card */}
      <section className={`${ui.card} overflow-hidden`}>
        <div className={ui.cardHeader}>
          <h3 className="font-semibold text-ink">All Documents</h3>
          <p className="ledger-label text-muted">
            {filteredDocuments.length} {filteredDocuments.length === 1 ? 'file' : 'files'}
          </p>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center py-20 gap-3">
            <Spinner className="size-10 text-primary" />
            <p className="text-sm text-muted">Loading shared patient documents...</p>
          </div>
        ) : filteredDocuments.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr>
                  <th className={ui.th}>Document</th>
                  <th className={ui.th}>Patient</th>
                  <th className={ui.th}>Uploaded</th>
                  <th className={ui.th}>Status</th>
                  <th className={`${ui.th} text-right`}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredDocuments.map((doc) => {
                  const fileInfo = getFileIcon(doc.filename);
                  const isAnalyzed = Boolean(doc.ai_analysis);
                  const isVerified = Boolean(doc.verified_at);

                  return (
                    <tr key={doc.id} className={`${ui.tr} group`}>
                      <td className="px-5 md:px-6 py-4">
                        <div className="flex items-center gap-3">
                          <div className={`size-9 rounded ${fileInfo.color} flex items-center justify-center shrink-0`}>
                            <Icon name={fileInfo.icon} className="text-[20px]" />
                          </div>
                          <div className="min-w-0">
                            <span className="font-medium text-ink truncate block" title={doc.filename}>
                              {doc.filename}
                            </span>
                            <span className="text-xs text-muted font-mono">
                              #{doc.id}
                            </span>
                          </div>
                        </div>
                      </td>

                      <td className="px-5 md:px-6 py-4">
                        <div className="min-w-0">
                          <p className="text-sm font-medium text-ink truncate">
                            {doc.patient_name || doc.patient_email?.split('@')[0]}
                          </p>
                          <p className="text-xs text-muted truncate">{doc.patient_email}</p>
                        </div>
                      </td>

                      <td className="px-5 md:px-6 py-4 text-xs font-mono text-muted tnum whitespace-nowrap">
                        {doc.upload_timestamp
                          ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', {
                              month: 'short',
                              day: 'numeric',
                              year: 'numeric',
                            })
                          : 'N/A'}
                      </td>

                      <td className="px-5 md:px-6 py-4 whitespace-nowrap">
                        <div className="flex items-center gap-2">
                          {isAnalyzed ? (
                            <span className={`${ui.badge} ${ui.badgeSuccess}`}>
                              <Icon name="auto_awesome" className="text-[12px]" />
                              AI Ready
                            </span>
                          ) : (
                            <span className={`${ui.badge} ${ui.badgeNeutral}`}>
                              Pending AI
                            </span>
                          )}

                          {isVerified && (
                            <span className={`${ui.badge} ${ui.badgeInfo}`}>
                              <Icon name="verified" className="text-[12px]" />
                              Verified
                            </span>
                          )}
                        </div>
                      </td>

                      <td className="px-5 md:px-6 py-4 text-right whitespace-nowrap">
                        <div className="flex items-center justify-end gap-2">
                          {isAnalyzed ? (
                            <button
                              type="button"
                              onClick={() => navigate(`/document/${doc.id}`)}
                              className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                            >
                              <Icon name="visibility" className="text-[15px]" />
                              View Report
                            </button>
                          ) : (
                            <>
                              <button
                                type="button"
                                onClick={() => handleAnalyze(doc.id)}
                                disabled={analyzing === doc.id}
                                className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                              >
                                {analyzing === doc.id ? (
                                  <Spinner className="size-3" />
                                ) : (
                                  <>
                                    <Icon name="smart_toy" className="text-[15px]" />
                                    Analyze
                                  </>
                                )}
                              </button>
                              <button
                                type="button"
                                onClick={() => navigate(`/document/${doc.id}`)}
                                className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                              >
                                <Icon name="visibility" className="text-[15px]" />
                                View
                              </button>
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <EmptyState
            icon="folder_off"
            title="No documents found"
            hint={
              searchQuery || typeFilter !== 'all'
                ? 'Try adjusting your search query or filter.'
                : 'When linked patients share medical records with you, they will appear here.'
            }
          />
        )}
      </section>

      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
};

export default DoctorDocuments;
