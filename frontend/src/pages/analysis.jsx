import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { getDoctorStats, getPatientDocuments, analyzeDocument } from '../services/api';
import { getPatientDocumentById } from '../services/documents';
import Icon from '../components/Icon.jsx';
import { Alert, EmptyState, Spinner } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const Analysis = () => {
  const params = useParams();
  const { id: docId } = params;
  const navigate = useNavigate();
  const [doc, setDoc] = useState(null);
  const [analysis, setAnalysis] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [analyzing, setAnalyzing] = useState(false);

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

  useEffect(() => {
    fetchDoc();
  }, [fetchDoc]);

  const handleAnalyze = async () => {
    setAnalyzing(true);
    try {
      await analyzeDocument(docId);
      await fetchDoc();
    } catch (err) {
      console.error('Analysis failed', err);
      setError(err.response?.data?.detail || 'Analysis failed.');
    } finally {
      setAnalyzing(false);
    }
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

  if (error) {
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
            Uploaded by <span className="text-ink">{doc.patient_name || 'Unknown patient'}</span>
            · {new Date(doc.upload_timestamp).toLocaleDateString('en-US')}
          </p>
        </div>
      </div>

      <section className={`${ui.card} overflow-hidden`}>
        <div className={ui.cardHeader}>
          <h3 className="font-semibold text-ink">Analysis report</h3>
          <p className="ledger-label text-muted">{analysis ? 'Complete' : 'No analysis yet'}</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr>
                <th className={ui.th}>Metric</th>
                <th className={`${ui.th} text-right`}>Value</th>
              </tr>
            </thead>
            <tbody>
              {analysis ? (
                <tr>
                  <td className="px-5 md:px-6 py-4 text-muted">Summary</td>
                  <td className="px-5 md:px-6 py-4">
                    <div className="text-ink font-medium">{analysis.summary.slice(0, 120)}
                      {analysis.summary.length > 120 && '…'}
                    </div>
                  </td>
                </tr>
              ) : null}
              {stats ? (
                <>
                  <tr>
                    <td className="px-5 md:px-6 py-4">Words</td>
                    <td className={`px-5 md:px-6 py-4 ${ui.tdFontMono} tnum`}>{stats.words.toLocaleString()}</td>
                  </tr>
                  <tr>
                    <td className="px-5 md:px-6 py-4">Pages</td>
                    <td className={`px-5 md:px-6 py-4 ${ui.tdFontMono} tnum`}>{stats.pages}</td>
                  </tr>
                  <tr>
                    <td className="px-5 md:px-6 py-4">Tables</td>
                    <td className={`px-5 md:px-6 py-4 ${ui.tdFontMono} tnum`}>{stats.tables}</td>
                  </tr>
                </>
              ) : null}
              {!analysis && (
                <tr>
                  <td colSpan="2" className="p-5 text-center text-muted">
                    This document has not been analyzed yet. Upload a new document or analyze one from your dashboard.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      {!analysis && (
        <div className={`${ui.card} text-center py-8`}>
          <p className="text-muted">To analyze this document, run the AI extraction first.</p>
          <button
            type="button"
            onClick={handleAnalyze}
            disabled={analyzing}
            className={`${ui.btn} ${ui.btnPrimary} mt-4`}
          >
            {analyzing ? (
              <Spinner className="size-4" />
            ) : (
              <>
                <Icon name="smart_toy" className="text-[18px]" />
                Analyze document
              </>
            )}
          </button>
        </div>
      )}
    </div>
  );
};

export default Analysis;
