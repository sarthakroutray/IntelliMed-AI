import React, { useEffect, useState, useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { getDoctorStats } from '../../services/api';
import { getPatientDocumentById } from '../../services/documents';
import Icon from '../../components/Icon';
import { Alert, EmptyState, Spinner, ConfirmDialog } from '../../components/ui.jsx';
import { ui } from '../../styles/ui.js';

const DoctorAiAnalysis = () => {
  const params = useParams();
  const { id: docId } = params;
  const navigate = useNavigate();
  const [doc, setDoc] = useState(null);
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [analyzing, setAnalyzing] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  const fetchDoc = useCallback(async () => {
    try {
      setLoading(true);
      const data = await getPatientDocumentById(docId);
      setDoc(data);
      setAnalysis(data.ai_analysis);
    } catch (err) {
      console.error('Fetch document failed:', err);
      setError('Document not found or access denied.');
    } finally {
      setLoading(false);
    }
  }, [docId]);

  useEffect(() => { fetchDoc(); }, [fetchDoc]);

  const handleAnalyze = async () => {
    setAnalyzing(true);
    try {
      await fetchDoc();
    } catch (err) {
      console.error('Analysis failed', err);
      setError(err.response?.data?.detail || 'Analysis failed.');
    } finally {
      setAnalyzing(false);
    }
  };

  const handleDelete = async () => {
    await fetchDoc();
    setConfirmingDelete(false);
    navigate('/dashboard/documents');
  };

  const stats = analysis
    ? {
        token_count: analysis.token_count,
        words: analysis.word_count,
        pages: analysis.page_count,
        tables: analysis.tables_detected || 0,
      }
    : null;

  if (loading) {
    return (
      <div className="space-y-6 animate-pulse">
        <div className="flex items-center justify-between">
          <div className={`size-8 rounded ${ui.emptyIcon}`}></div>
          <h1 className={`${ui.pageTitle}`}>Document Analysis</h1>
        </div>
        <div className={`${ui.card}`}>
          <div className={ui.cardHeader}>
            <div className="h-4 w-24 bg-surface-2 rounded"></div>
            <div className="h-5 w-16 bg-surface-2 rounded-full"></div>
          </div>
          <div className="p-5 md:p-7">
            <div className="h-4 w-1/3 bg-surface-2 rounded mb-3"></div>
            <div className="h-4 w-1/2 bg-surface-2 rounded"></div>
          </div>
        </div>
      </div>
    );
  }

  if (error || !doc) {
    return (
      <div className="space-y-6">
        <div className={ui.pageHeader}>
          <h1 className={`${ui.pageTitle}`}>Document Analysis</h1>
        </div>
        <EmptyState
          icon="error"
          title="Document not found"
          hint="The document could not be loaded. It may have been deleted or you no longer have access."
          action={
            <button
              type="button"
              onClick={() => navigate('/dashboard/documents')}
              className={`${ui.btn} ${ui.btnSecondary}`}
            >
              Back to documents
            </button>
          }
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <p className="ledger-label text-muted">Document</p>
          <h1 className={`${ui.pageTitle} mt-2`}>{doc.filename}</h1>
          <p className={ui.pageSubtitle}>
            Shared with {doc.shared_with?.length || 0} doctors · Uploaded {new Date(doc.upload_timestamp).toLocaleDateString('en-US')}
          </p>
        </div>
      </div>

      <div className="grid md:grid-cols-3 gap-4">
        <div className={`${ui.card}`}>
          <div className={ui.cardHeader}>
            <div className="flex items-center gap-3">
              <div className={`size-10 rounded ${ui.emptyIcon}`}>
                <Icon name={getFileIcon(doc.filename).icon} />
              </div>
              <p className="ledger-label text-muted">{doc.filename}</p>
            </div>
          </div>
          <div className="p-5 md:p-7">
            <p className="text-xs text-muted">
              Uploaded by <span className="text-ink">{doc.patient_name || 'Unknown patient'}</span>
            </p>
            <p className="mt-4 text-sm text-muted">
              Size: {(doc.file_size / 1024).toFixed(1)} KB
            </p>
            <div className="mt-3 flex gap-2">
              <span className={`badge badge-neutral flex items-center gap-1.5 text-xs`}>
                <Icon name="lock" className="text-[13px]" />
                Private
              </span>
            </div>
          </div>
        </div>

        <div className={`${ui.card}`}>
          <div className={ui.cardHeader}>
            <p className="ledger-label text-muted">AI Analysis</p>
          </div>
          <div className="p-5 md:p-7">
            {analysis ? (
              <div className="space-y-3">
                <p className="text-sm font-medium text-ink">Summary</p>
                <p className="text-sm text-body leading-relaxed">
                  {analysis.summary.slice(0, 160)}
                  {analysis.summary.length > 160 && '…'}
                </p>
                <p className="text-sm font-medium text-ink">Details</p>
                <ul className="text-sm text-muted space-y-1.5">
                  <li className="flex justify-between">
                    <span>Words</span>
                    <span className="tnum">{analysis.word_count.toLocaleString()}</span>
                  </li>
                  <li className="flex justify-between">
                    <span>Pages</span>
                    <span className="tnum">{analysis.page_count}</span>
                  </li>
                  <li className="flex justify-between">
                    <span>Tables</span>
                    <span className="tnum">{analysis.tables_detected || 0}</span>
                  </li>
                  <li className="flex justify-between">
                    <span>Entities</span>
                    <span className="tnum">{analysis.entities?.length || 0}</span>
                  </li>
                  <li className="flex justify-between">
                    <span>Confidence</span>
                    <span className="tnum">{(analysis.confidence * 100).toFixed(0)}%</span>
                  </li>
                </ul>
                <p className="text-xs text-muted mt-4">
                  Generated on {new Date(analysis.generated_at).toLocaleDateString('en-US')}
                </p>
              </div>
            ) : (
              <div className="py-6 text-center">
                <p className="text-muted text-sm">
                  No analysis available. Please run AI analysis first.
                </p>
              </div>
            )}
          </div>
        </div>

        {doc.docStats && (
          <div className={`${ui.card}`}>
            <div className={ui.cardHeader}>
              <p className="ledger-label text-muted">Statistics</p>
            </div>
            <div className="p-5 md:p-7">
              <div className="space-y-3">
                <p className="text-sm font-medium text-ink">Views</p>
                <div className="flex items-center justify-between text-sm text-muted">
                  <span>By patients</span>
                  <span className="tnum">{doc.docStats.patient_views.toLocaleString()}</span>
                </div>
                <div className="flex items-center justify-between text-sm text-muted">
                  <span>By doctors</span>
                  <span className="tnum">{doc.docStats.doctor_views.toLocaleString()}</span>
                </div>
                <div className="w-full h-2 rounded-full bg-surface-2 mt-3">
                  <div
                    className="h-full rounded-full bg-primary transition-all duration-500"
                    style={{ width: `${(doc.docStats.doctor_views / (doc.docStats.patient_views + doc.docStats.doctor_views)) * 100}%` }}
                  />
                </div>
                <p className="text-xs text-muted mt-2">
                  {doc.docStats.doctor_views} doctor views / {doc.docStats.patient_views + doc.docStats.doctor_views} total
                </p>
              </div>
            </div>
          </div>
        )}
      </div>

      {analysis && (
        <section className={`${ui.card} overflow-hidden`}>
          <div className={ui.cardHeader}>
            <h3 className="font-semibold text-ink">Full analysis report</h3>
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => navigate(`/document/${doc.id}`)}
                className={`${ui.btn} ${ui.btnSecondary}`}
              >
                View full report
              </button>
              <button
                type="button"
                onClick={() => setConfirmingDelete(true)}
                className={`${ui.btn} ${ui.btnDanger}`}
              >
                Delete
              </button>
            </div>
          </div>
          <div className="overflow-x-auto">
            <div className="min-w-[600px] p-5 md:p-7">
              <div className="prose prose-sm max-w-none text-body">
                <h2 className="font-serif text-xl text-ink mb-4">Analysis Report</h2>
                <p className="text-sm text-muted mb-4">
                  AI-generated insights and extracted data from this document.
                </p>
                <div className="space-y-4">
                  <div className="p-4 rounded border border-line bg-surface-2">
                    <p className="text-sm text-body">{analysis.summary}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {analysis.entities?.slice(0, 8).map((e, i) => (
                      <span key={i} className={`${ui.badge} ${ui.badgeInfo} text-xs`}>
                        {e}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      )}

      <ConfirmDialog
        open={confirmingDelete}
        title="Delete this document?"
        message="This will remove the document from all patient and doctor views. The analysis data will also be deleted."
        confirmLabel="Delete"
        danger
        onConfirm={handleDelete}
        onCancel={() => setConfirmingDelete(false)}
      />
    </div>
  );
};

const getFileIcon = (filename) => {
  if (filename?.endsWith('.pdf')) return 'picture_as_pdf';
  if (filename?.endsWith('.dcm')) return 'imagesmode';
  return 'description';
};

export default DoctorAiAnalysis;