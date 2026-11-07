import React, { useEffect, useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { getPatientDocuments } from '../services/api';
import { getPatientDocumentById } from '../services/documents';
import Icon from '../components/Icon';
import { Alert, EmptyState, Spinner } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const AllDocuments = () => {
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [analyzing, setAnalyzing] = useState(null);

  const fetchDocuments = useCallback(async () => {
    try {
      setLoading(true);
      const res = await getPatientDocuments();
      const data = res.data || [];
      setDocuments(data);
    } catch (err) {
      console.error('Fetch failed:', err);
      setError('Failed to load documents.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchDocuments(); }, [fetchDocuments]);

  const getFileIcon = (filename) => {
    if (filename?.endsWith('.pdf')) return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger' };
    if (filename?.endsWith('.dcm')) return { icon: 'imagesmode', color: 'bg-primary/10 text-primary' };
    return { icon: 'description', color: 'bg-surface-2 text-muted' };
  };

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      await getPatientDocumentById(docId);
      await fetchDocuments();
    } catch (err) {
      console.error('Analysis failed', err);
      setError(err.response?.data?.detail || 'Analysis failed.');
    } finally {
      setAnalyzing(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6 animate-pulse">
        <div className={ui.pageHeader}>
          <div className="flex flex-col">
            <div className="h-5 w-32 bg-surface-2 rounded mb-2"></div>
            <div className="h-9 w-48 bg-surface-2 rounded"></div>
          </div>
        </div>
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1,2,3].map(i => (
            <div key={i} className={`${ui.card}`}>
              <div className={ui.cardHeader}>
                <div className="flex items-center gap-3">
                  <div className="h-5 w-24 bg-surface-2 rounded"></div>
                  <div className="h-4 w-16 bg-surface-2 rounded-full"></div>
                </div>
              </div>
              <div className="p-5 md:p-7">
                <div className="flex items-center gap-3">
                  <div className="size-8 bg-surface-2 rounded"></div>
                  <div className="h-4 w-32 bg-surface-2 rounded"></div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-6">
        <div className={ui.pageHeader}>
          <h1 className={`${ui.pageTitle} mt-2`}>Documents</h1>
        </div>
        <Alert type="error">{error}</Alert>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <h1 className={`${ui.pageTitle} mt-2`}>Documents</h1>
          <p className={ui.pageSubtitle}>
            Your uploaded medical records, sorted by upload date.
          </p>
        </div>
      </div>

      <section className={`${ui.card} overflow-hidden`}>
        <div className={ui.cardHeader}>
          <h3 className="font-semibold text-ink">All documents</h3>
          <p className="ledger-label text-muted">{documents.length}</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr>
                <th className={ui.th}>Filename</th>
                <th className={`${ui.th} text-right`}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {documents.map(doc => {
                const fileInfo = getFileIcon(doc.filename);
                return (
                  <tr key={doc.id} className={`${ui.tr} group`}>
                    <td className="px-5 md:px-6 py-4">
                      <div className="flex items-center gap-3">
                        <div className={`size-8 rounded ${fileInfo.color} flex items-center justify-center`}>
                          <Icon name={fileInfo.icon} className="text-[19px]" />
                        </div>
                        <div className="min-w-0">
                          <div className="font-medium text-ink truncate">{doc.filename}</div>
                          <p className="text-xs text-muted">
                            {doc.upload_timestamp ? new Date(doc.upload_timestamp).toLocaleDateString('en-US') : 'N/A'}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td className="px-5 md:px-6 py-4 text-right">
                      <div className="flex items-center justify-end gap-2">
                        {doc.ai_analysis ? (
                          <a
                            href={`/document/${doc.id}`}
                            className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                          >
                            <Icon name="visibility" className="text-[15px]" />
                            View
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
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
};

export default AllDocuments;
