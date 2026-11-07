import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { getLinkedDoctors, deleteDocument, getPatientDocuments, getSharedDoctors, analyzeDocument } from '../../services/api';
import Icon from '../../components/Icon.jsx';
import { Alert, ConfirmDialog, EmptyState } from '../../components/ui.jsx';
import { ui } from '../../styles/ui.js';

const DoctorPatients = () => {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [linkedDoctors, setLinkedDoctors] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [pendingDelete, setPendingDelete] = useState(null);
  const [analyzing, setAnalyzing] = useState(null);
  const [loading, setLoading] = useState(true);
  const [sharedDoctors, setSharedDoctors] = useState({});

  const fetchDoctors = useCallback(async () => {
    try {
      const res = await getLinkedDoctors();
      setLinkedDoctors(res.data || []);
    } catch (err) {
      setError('Failed to load your patients.');
    } finally {
      setLoading(false);
    }
  }, []);

  const fetchDocuments = useCallback(async () => {
    try {
      const res = await getPatientDocuments();
      const docs = res.data || [];
      const sharePromises = docs.map(doc =>
        getSharedDoctors(doc.id).then(r => [doc.id, r.data || []]).catch(() => [doc.id, []])
      );
      const results = await Promise.all(sharePromises);
      const counts = Object.fromEntries(results);
      setSharedDoctors(counts);
      setDocuments(docs);
    } catch (err) {
      console.error('Fetch docs error:', err);
    }
  }, []);

  useEffect(() => {
    fetchDoctors();
    fetchDocuments();
  }, [fetchDoctors, fetchDocuments]);

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      await analyzeDocument(docId);
      await fetchDocuments();
    } catch (err) {
      console.error('Analysis failed', err);
      setError(err.response?.data?.detail || 'Analysis failed.');
    } finally {
      setAnalyzing(null);
    }
  };

  const handleDelete = async (docId) => {
    setDocuments(prev => prev.filter(d => d.id !== docId));
    try {
      await deleteDocument(docId);
      await fetchDocuments();
    } catch (err) {
      console.error('Delete failed', err);
      setDocuments(prev => prev.filter(d => d.id !== docId));
    }
  };

  const getFileIcon = (filename) => {
    if (filename?.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger' };
    if (filename?.endsWith('.dcm')) return { icon: 'imagesmode', color: 'bg-primary/10 text-primary' };
    return { icon: 'description', color: 'bg-surface-2 text-muted' };
  };

  const getDocumentStatus = (doc) => {
    const isShared = sharedDoctors[doc.id] && sharedDoctors[doc.id].length > 0;
    return isShared
      ? <span className={`badge badge-info flex items-center gap-1.5 text-xs`}>Shared</span>
      : <span className={`badge badge-neutral flex items-center gap-1.5 text-xs`}>Private</span>;
  };

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <h1 className={`${ui.pageTitle} mt-2`}>Patients</h1>
        <p className={ui.pageSubtitle}>View and manage the patients linked to your account.</p>
      </div>

      {error && (
        <Alert type="error" onDismiss={() => setError('')}>
          {error}
        </Alert>
      )}

      {loading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className={ui.card}>
              <div className={ui.cardHeader}>
                <div className="h-4 w-24 bg-surface-2 rounded"></div>
                <div className="h-8 w-8 bg-surface-2 rounded-full"></div>
              </div>
              <div className="p-5 md:p-7">
                <div className="h-3 w-full bg-surface-2 rounded mb-2"></div>
                <div className="h-3 w-2/3 bg-surface-2 rounded"></div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <>
          <section className={`${ui.card} overflow-hidden`}>
            <div className={ui.cardHeader}>
              <h3 className="text-base font-semibold text-ink">Your patients</h3>
              <p className="ledger-label text-muted">{linkedDoctors.length}</p>
            </div>
            {linkedDoctors.length === 0 ? (
              <div className="py-12 text-center">
                <EmptyState
                  icon="people"
                  title="No patients linked"
                  hint="You must first link a patient from their dashboard."
                />
              </div>
            ) : (
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr>
                    <th className={ui.th}>Patient email</th>
                    <th className={`${ui.th} text-right`}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {linkedDoctors.map((doc) => (
                    <tr key={doc.id} className={`${ui.tr} group`}>
                      <td className={`px-5 md:px-6 py-4 max-w-xs`}>
                        <div className="flex items-center gap-3">
                          <div className="bg-primary/10 text-primary rounded-full size-8 flex items-center justify-center">
                            <Icon name="person" className="text-[18px]" />
                          </div>
                          <span className="text-sm font-medium text-ink truncate">{doc.email}</span>
                        </div>
                      </td>
                      <td className="px-5 md:px-6 py-4 text-right">
                        <button
                          onClick={() => navigate(`/patient-dashboard?doctor=${doc.id}`)}
                          className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm} mx-1`}
                          disabled={analyzing === doc.id}
                        >
                          <span className="sr-only">View</span>
                          <Icon name="visibility" className="text-[15px]" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </section>

          <section className={`${ui.card} overflow-hidden`}>
            <div className={ui.cardHeader}>
              <h3 className="text-base font-semibold text-ink">Recent uploads</h3>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr>
                    <th className={ui.th}>Document</th>
                    <th className={ui.th}>Uploaded</th>
                    <th className={ui.th}>Status</th>
                    <th className={`${ui.th} text-right`}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {documents.slice(0, 8).map((doc) => {
                    const fileInfo = getFileIcon(doc.filename);
                    return (
                      <tr key={doc.id} className={`${ui.tr} group`}>
                        <td className="px-5 md:px-6 py-4">
                          <div className="flex items-center gap-3">
                            <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                              <Icon name={fileInfo.icon} className="text-[19px]" />
                            </div>
                            <span className="text-sm font-medium text-ink">{doc.filename}</span>
                          </div>
                        </td>
                        <td className={`${ui.td}`}>
                          {new Date(doc.upload_timestamp).toLocaleDateString('en-US', {
                            month: 'short',
                            day: 'numeric',
                            year: 'numeric',
                          })}
                        </td>
                        <td className="px-5 md:px-6 py-4">{getDocumentStatus(doc)}</td>
                        <td className="px-5 md:px-6 py-4 text-right">
                          {doc.ai_analysis ? (
                            <button
                              onClick={() => navigate(`/document/${doc.id}`)}
                              className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                            >
                              View
                            </button>
                          ) : (
                            <button
                              onClick={() => handleAnalyze(doc.id)}
                              disabled={analyzing === doc.id}
                              className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                            >
                              {analyzing === doc.id ? (
                                <Spinner className="size-3" />
                              ) : (
                                <>
                                  <Icon name="smart_toy" className="text-[15px]" />
                                  <span>Analyze</span>
                                </>
                              )}
                            </button>
                          )}
                          <button
                            onClick={() => setPendingDelete(doc.id)}
                            className="size-9 flex items-center justify-center rounded hover:bg-danger/10 text-subtle hover:text-danger ml-1"
                            title="Delete document"
                          >
                            <Icon name="delete" className="text-[19px]" />
                          </button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
            {documents.length === 0 && (
              <div className="py-8">
                <EmptyState icon="inbox" title="No uploads yet." hint="Wait for patients to share documents." />
              </div>
            )}
          </section>
        </>
      )}

      <ConfirmDialog
        open={pendingDelete !== null}
        title="Delete document?"
        message="This document will be permanently removed from all patients' views."
        confirmLabel="Delete"
        danger
        onConfirm={() => {
          handleDelete(pendingDelete);
          setPendingDelete(null);
        }}
        onCancel={() => setPendingDelete(null)}
      />
    </div>
  );
};

export default DoctorPatients;