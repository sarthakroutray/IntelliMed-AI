import React, { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { getSharedDoctors, getDoctorStats, getPatientDocuments, analyzeDocument } from '../../services/api';
import Icon from '../../components/Icon.jsx';
import { Alert, EmptyState, Spinner } from '../../components/ui.jsx';
import { ui } from '../../styles/ui.js';

const DoctorDocuments = () => {
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [analyzing, setAnalyzing] = useState(null);
  const [loading, setLoading] = useState(true);
  const [sharedDoctors, setSharedDoctors] = useState({});
  const [stats, setStats] = useState({});

  const fetchSharedDocs = useCallback(async () => {
    try {
      const sharePromises = Array.from({ length: 500 }, (_, i) => i)
        .map(id => getSharedDoctors(id))
        .catch(() => []);
      const results = await Promise.all(sharePromises);
      const counts = results.reduce((acc, arr) => ({ ...acc, [arr[0]]: arr[1] }), {});
      setSharedDoctors(counts);

      const docs = [];
      const docIds = Object.keys(counts);
      const statsPromises = docIds.map(id => getDoctorStats(id).then(s => s.data));
      const docsRes = await Promise.all([getPatientDocuments().then(r => r.data), ...statsPromises]);
      const allDocs = [...docsRes[0], ...docsRes.slice(1).map((s, i) => ({ ...s, docStats: docsRes[i + 1] }))];
      setDocuments(allDocs);
    } catch (err) {
      console.error('Fetch shared docs failed:', err);
      setError('Failed to load shared documents.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchSharedDocs(); }, [fetchSharedDocs]);

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      await analyzeDocument(docId);
      await fetchSharedDocs();
    } catch (err) {
      console.error('Analysis failed', err);
      setError(err.response?.data?.detail || 'Analysis failed.');
    } finally {
      setAnalyzing(null);
    }
  };

  const getFileIcon = (filename) => {
    if (filename?.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger' };
    if (filename?.endsWith('.dcm')) return { icon: 'imagesmode', color: 'bg-primary/10 text-primary' };
    return { icon: 'description', color: 'bg-surface-2 text-muted' };
  };

  const getDocumentStatus = (doc) => {
    const isShared = sharedDoctors[doc.id];
    if (isShared) {
      return (
        <div className={`badge badge-info flex items-center gap-1.5 text-xs`}>
          <Icon name="share" className="text-[13px]" />
          <span>{isShared} doctors</span>
        </div>
      );
    }
    return <span className="text-muted text-xs">Private</span>;
  };

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <h1 className={`${ui.pageTitle} mt-2`}>Documents</h1>
        <p className={ui.pageSubtitle}>
          Documents shared with you and other doctors on the platform.
        </p>
      </div>

      {error && (
        <Alert type="error" onDismiss={() => setError('')}>
          {error}
        </Alert>
      )}

      {loading || analyzing ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className={`${ui.card} animate-pulse`}>
              <div className={ui.cardHeader}>
                <div className="flex items-center gap-3">
                  <div className="h-5 w-24 bg-surface-2 rounded"></div>
                  <div className="h-5 w-16 bg-surface-2 rounded-full"></div>
                </div>
              </div>
              <div className="p-5 md:p-7">
                <div className="flex items-center gap-3">
                  <div className="size-8 bg-surface-2 rounded"></div>
                  <div className="h-4 w-48 bg-surface-2 rounded"></div>
                </div>
                <div className="mt-3 h-4 w-24 bg-surface-2 rounded"></div>
              </div>
            </div>
          ))}
        </div>
      ) : documents.length === 0 ? (
        <EmptyState
          icon="folder"
          title="No shared documents yet"
          hint="Patients can share documents with you when they upload them."
        />
      ) : (
        <section className={`${ui.card} overflow-hidden`}>
          <div className={ui.cardHeader}>
            <h3 className="text-base font-semibold text-ink">Shared documents</h3>
            <p className="ledger-label text-muted">{documents.length}</p>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr>
                  <th className={ui.th}>Document</th>
                  <th className={`${ui.th} text-right`}>AI analysis</th>
                </tr>
              </thead>
              <tbody>
                {documents.map((doc) => {
                  const fileInfo = getFileIcon(doc.filename);
                  return (
                    <tr key={doc.id} className={`${ui.tr} group`}>
                      <td className="px-5 md:px-6 py-4">
                        <div className="flex flex-col gap-1.5">
                          <div className="flex items-center gap-3">
                            <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                              <Icon name={fileInfo.icon} className="text-[19px]" />
                            </div>
                            <span className="font-medium text-ink">{doc.filename}</span>
                          </div>
                          <p className="text-xs text-subtle truncate">{doc.patient_name || 'Unknown patient'}</p>
                          <div className="flex items-center gap-2 mt-0.5">
                            <p className="text-muted text-xs">Shared with {sharedDoctors[doc.id] || 0} doctors</p>
                            <span className="material-symbols-outlined text-muted">verified</span>
                          </div>
                        </div>
                      </td>
                      <td className="px-5 md:px-6 py-4 text-right">
                        {doc.ai_analysis ? (
                          <a
                            href={`/document/${doc.id}`}
                            className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                          >
                            View report
                          </a>
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
                              <>
                                <Icon name="smart_toy" className="text-[15px]" />
                                Analyze
                              </>
                            )}
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      )}
    </div>
  );
};

export default DoctorDocuments;