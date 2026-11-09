import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api, { analyzeDocument, getDoctorDocuments } from '../services/api';
import Icon from '../components/Icon';
import { Alert, Toast, Spinner, EmptyState } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const AIAnalysis = ({ refreshKey = 0 }) => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [selectedDoc, setSelectedDoc] = useState(null);
  const [loading, setLoading] = useState(true);
  const [analyzing, setAnalyzing] = useState(null);
  const [toast, setToast] = useState(null);

  const fetchDocumentsWithAI = useCallback(async () => {
    try {
      setLoading(true);
      
      if (user?.role === 'doctor') {
        const response = await getDoctorDocuments();
        const docs = (response.data || []).map(doc => ({
          ...doc,
          patientName: doc.patient_name || doc.patient_email?.split('@')[0],
          patientEmail: doc.patient_email
        }));
        setDocuments(docs);
      } else {
        const response = await api.get('/patient/documents');
        setDocuments(response.data || []);
      }
    } catch (err) {
      console.error('Failed to fetch documents', err);
    } finally {
      setLoading(false);
    }
  }, [user?.role]);

  useEffect(() => {
    fetchDocumentsWithAI();
  }, [fetchDocumentsWithAI, refreshKey]);

  const handleAnalyze = async (docId) => {
    setAnalyzing(docId);
    try {
      // Call real AI analysis endpoint
      const response = await analyzeDocument(docId);
      const analysisResult = response.data.analysis;

      // Build the structured analysis from backend response
      const cv = analysisResult.cv_result || {};
      const nlp = analysisResult.nlp_result || {};
      const ocr = analysisResult.ocr_result || '';

      const structuredAnalysis = {
        summary: cv.classification
          ? `${cv.classification} (${(cv.confidence * 100).toFixed(1)}% confidence). ${cv.recommendation || ''}`
          : nlp.summary || 'Analysis completed.',
        entities: nlp.entities || [],
        recommendations: [
          cv.recommendation,
          nlp.summary ? `NLP Summary: ${nlp.summary}` : null,
        ].filter(Boolean),
        classification: cv.classification,
        confidence: cv.confidence,
        probabilities: cv.probabilities,
        ocr_text: ocr,
        // New prescription-specific fields
        is_prescription: nlp.is_prescription || false,
        medications: nlp.medications || [],
        prescriptions: nlp.prescriptions || [],
        // T5 Medical Summary fields
        medical_summary: analysisResult.summary_result?.medical_summary || '',
        key_findings: analysisResult.summary_result?.key_findings || [],
      };

      // Update local state with real analysis result
      setDocuments(docs =>
        docs.map(doc =>
          doc.id === docId
            ? { ...doc, ai_analysis: analysisResult }
            : doc
        )
      );
      setSelectedDoc(current =>
        current && current.id === docId
          ? { ...current, ai_analysis: analysisResult }
          : current
      );
    } catch (err) {
      console.error('AI analysis failed', err);
      setToast({ type: 'error', message: err.response?.data?.detail || 'AI analysis failed. Please try again.' });
    } finally {
      setAnalyzing(null);
    }
  };

  const parseAIAnalysis = (analysisData) => {
    try {
      // If it's already an object (from backend), use it directly
      if (typeof analysisData === 'object' && analysisData !== null) {
        // Transform backend structure to frontend structure
        const cv = analysisData.cv_result || {};
        const nlp = analysisData.nlp_result || {};
        const ocr = analysisData.ocr_result || '';
        
        // Use validated document type from backend (or fall back to individual types)
        const documentType = analysisData.detected_type || cv.document_type || nlp.document_type || 'document';
        const isXray = documentType === 'xray';
        const isPrescription = documentType === 'prescription';

        // Extract T5 summary data
        const summaryResult = analysisData.summary_result || {};
        const medicalSummary = summaryResult.medical_summary || analysisData.medical_summary || '';
        const keyFindings = summaryResult.key_findings || analysisData.key_findings || [];
        
        // Build context-aware summary and recommendations
        let summary = '';
        let recommendations = [];
        
        if (isXray && cv.classification) {
          // For X-rays: use CV data only
          summary = `${cv.classification} (${(cv.confidence * 100).toFixed(1)}% confidence). ${cv.recommendation || ''}`;
          if (cv.recommendation) {
            recommendations.push(cv.recommendation);
          }
        } else if (isPrescription && nlp.summary && !nlp.summary.includes('No text available')) {
          // For prescriptions: use NLP data only (if meaningful)
          summary = nlp.summary;
          recommendations.push(nlp.summary);
        } else if (cv.classification) {
          // Fallback: has CV classification
          summary = `${cv.classification} (${(cv.confidence * 100).toFixed(1)}% confidence)`;
        } else if (nlp.summary && !nlp.summary.includes('No text available')) {
          // Fallback: has meaningful NLP summary
          summary = nlp.summary;
        } else {
          summary = 'Analysis completed.';
        }
        
        return {
          summary,
          entities: isPrescription ? (nlp.entities || []) : [],  // Only show entities for prescriptions
          recommendations,
          classification: cv.classification,
          confidence: cv.confidence,
          probabilities: cv.probabilities,
          ocr_text: ocr,
          is_prescription: nlp.is_prescription || false,
          medications: nlp.medications || [],
          prescriptions: nlp.prescriptions || [],
          document_type: documentType,
          medical_summary: medicalSummary,
          key_findings: keyFindings,
        };
      }
      
      // If it's a string, parse it
      if (typeof analysisData === 'string') {
        return JSON.parse(analysisData);
      }
      
      return null;
    } catch {
      return null;
    }
  };

  const analyzedDocs = documents.filter(doc => doc.ai_analysis);
  const pendingDocs = documents.filter(doc => !doc.ai_analysis);

  return (
    <div className="flex-1 overflow-y-auto p-4 md:p-8">
      <div className="max-w-[1400px] mx-auto flex flex-col gap-8">
        {/* Header */}
        <div>
          <h1 className={ui.pageTitle}>
            AI Analysis Dashboard
          </h1>
          <p className={`${ui.pageSubtitle} mt-2`}>
            Review AI-powered insights and recommendations from medical documents.
          </p>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <Spinner className="size-12" />
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left Panel - Document List */}
            <div className="lg:col-span-1 space-y-4">
              {/* Stats Card */}
              <div className="bg-gradient-to-br from-primary to-primary-strong rounded-2xl p-6 text-white shadow-card">
                <div className="flex items-center gap-3 mb-4">
                  <Icon name="auto_awesome" className="text-3xl" />
                  <div>
                    <p className="text-sm opacity-90">AI Analysis</p>
                    <p className="text-2xl font-extrabold">{analyzedDocs.length}/{documents.length}</p>
                  </div>
                </div>
                <div className="w-full bg-white/20 rounded-full h-2">
                  <div
                    className="bg-white rounded-full h-2 transition-all duration-500"
                    style={{ width: `${documents.length > 0 ? (analyzedDocs.length / documents.length) * 100 : 0}%` }}
                  ></div>
                </div>
              </div>

              {/* Analyzed Documents */}
              <div className={`${ui.card} overflow-hidden`}>
                <div className="p-4 border-b border-line">
                  <h3 className="font-bold text-ink flex items-center gap-2">
                    <Icon name="check_circle" className="text-success text-[20px]" />
                    Analyzed ({analyzedDocs.length})
                  </h3>
                </div>
                <div className="max-h-[400px] overflow-y-auto divide-y divide-line">
                  {analyzedDocs.map((doc) => (
                    <div key={doc.id} className="relative group">
                      <button type="button"
                        onClick={() => setSelectedDoc(doc)}
                        className={`w-full p-4 text-left hover:bg-surface-2 transition-colors ${
                          selectedDoc?.id === doc.id ? 'bg-primary/10' : ''
                        }`}
                      >
                        <p className="text-sm font-bold text-ink truncate pr-8">{doc.filename}</p>
                        {user.role === 'doctor' && (
                          <p className="text-xs text-muted mt-1">Patient: {doc.patientName}</p>
                        )}
                        <p className="text-xs text-muted mt-1">
                          {new Date(doc.upload_timestamp).toLocaleDateString()}
                        </p>
                      </button>
                      <button type="button"
                        onClick={() => handleAnalyze(doc.id)}
                        disabled={analyzing === doc.id}
                        className="absolute top-2 right-2 p-1.5 rounded-md bg-primary/10 hover:bg-primary/20 text-primary transition-colors disabled:opacity-50"
                        title="Re-analyze"
                      >
                        <Icon name="refresh" className="text-[16px]" />
                      </button>
                    </div>
                  ))}
                  {analyzedDocs.length === 0 && (
                    <div className="p-8 text-center text-muted text-sm">
                      No analyzed documents yet
                    </div>
                  )}
                </div>
              </div>

              {/* Pending Analysis */}
              {pendingDocs.length > 0 && (
                <div className={`${ui.card} overflow-hidden`}>
                  <div className="p-4 border-b border-line">
                    <h3 className="font-bold text-ink flex items-center gap-2">
                      <Icon name="pending" className="text-warning text-[20px]" />
                      Pending ({pendingDocs.length})
                    </h3>
                  </div>
                  <div className="max-h-[300px] overflow-y-auto divide-y divide-line">
                    {pendingDocs.map((doc) => (
                      <div key={doc.id} className="p-4 hover:bg-surface-2 transition-colors">
                        <p className="text-sm font-bold text-ink truncate mb-2">{doc.filename}</p>
                        {user.role === 'doctor' && (
                          <p className="text-xs text-muted mb-2">Patient: {doc.patientName}</p>
                        )}
                        <button type="button"
                          onClick={() => handleAnalyze(doc.id)}
                          disabled={analyzing === doc.id}
                          className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm} w-full`}
                        >
                          {analyzing === doc.id ? (
                            <>
                              <Spinner className="size-3" />
                              <span>Analyzing...</span>
                            </>
                          ) : (
                            <>
                              <Icon name="auto_awesome" className="text-[14px]" />
                              <span>Analyze Now</span>
                            </>
                          )}
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Right Panel - Analysis Details */}
            <div className="lg:col-span-2">
              {selectedDoc ? (
                <div className={`${ui.card} overflow-hidden`}>
                  {/* Document Header */}
                  <div className="p-6 border-b border-line bg-surface-2/60">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1">
                        <h2 className="text-xl font-bold text-ink mb-2">{selectedDoc.filename}</h2>
                        {user.role === 'doctor' && (
                          <p className="text-sm text-body">
                            Patient: <span className="font-medium">{selectedDoc.patientName}</span>
                          </p>
                        )}
                        <p className="text-sm text-muted mt-1">
                          Analyzed on {new Date(selectedDoc.upload_timestamp).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                        </p>
                      </div>
                      <button type="button"
                        onClick={() => navigate(`/document/${selectedDoc.id}`)}
                        className={`${ui.btn} ${ui.btnPrimary}`}
                      >
                        <Icon name="visibility" className="text-[18px]" />
                        <span>View Document</span>
                      </button>
                    </div>
                  </div>

                  {/* Analysis Content */}
                  <div className="p-6 space-y-6">
                    {(() => {
                      const analysis = parseAIAnalysis(selectedDoc.ai_analysis);
                      if (!analysis) {
                        return (
                          <EmptyState icon="error" title="Unable to parse AI analysis" />
                        );
                      }

                      const isXray = analysis.document_type === 'xray';
                      const isPrescription = analysis.document_type === 'prescription';
                      
                      return (
                        <>
                          {/* Classification Result - Only show for X-rays */}
                          {isXray && analysis.classification && (
                            <div className={`p-4 rounded-xl border ${
                              analysis.classification === 'Normal'
                                ? 'bg-success/5 border-success/20'
                                : 'bg-danger/5 border-danger/20'
                            }`}>
                              <div className="flex items-center gap-3 mb-2">
                                <Icon name={analysis.classification === 'Normal' ? 'check_circle' : 'warning'}
                                  className={`text-2xl ${analysis.classification === 'Normal' ? 'text-success' : 'text-danger'}`} />
                                <div>
                                  <p className={`text-lg font-extrabold ${analysis.classification === 'Normal' ? 'text-success' : 'text-danger'}`}>
                                    {analysis.classification}
                                  </p>
                                  <p className="text-sm text-body">
                                    Confidence: {analysis.confidence ? `${(analysis.confidence * 100).toFixed(1)}%` : 'N/A'}
                                  </p>
                                </div>
                              </div>
                            </div>
                          )}

                          {/* Probabilities - Only show for X-rays */}
                          {isXray && analysis.probabilities && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="bar_chart" className="text-primary" />
                                Class Probabilities
                              </h3>
                              <div className="space-y-3">
                                {Object.entries(analysis.probabilities).map(([label, prob]) => (
                                  <div key={label}>
                                    <div className="flex justify-between text-sm mb-1">
                                      <span className="font-medium text-body">{label}</span>
                                      <span className="text-muted">{(prob * 100).toFixed(1)}%</span>
                                    </div>
                                    <div className="w-full bg-surface-2 rounded-full h-2.5">
                                      <div
                                        className={`h-2.5 rounded-full transition-all duration-500 ${
                                          label === 'Normal' ? 'bg-success' : 'bg-danger'
                                        }`}
                                        style={{ width: `${Math.max(prob * 100, 1)}%` }}
                                      ></div>
                                    </div>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Summary - Only show if meaningful */}
                          {analysis.summary && !analysis.summary.includes('Analysis completed') && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="summarize" className="text-primary" />
                                Summary
                              </h3>
                              <p className="text-body leading-relaxed p-4 bg-surface-2 rounded-xl">
                                {analysis.summary}
                              </p>
                            </div>
                          )}

                          {/* Medical Summary (T5-generated) */}
                          {analysis.medical_summary && analysis.medical_summary.length > 10 && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="clinical_notes" className="text-success" />
                                Medical Summary
                                <span className={`${ui.badge} ${ui.badgeSuccess} ml-auto`}>AI Generated</span>
                              </h3>
                              <p className="text-body leading-relaxed p-4 bg-success/5 rounded-xl border border-success/20">
                                {analysis.medical_summary}
                              </p>
                            </div>
                          )}

                          {/* Key Findings */}
                          {analysis.key_findings && analysis.key_findings.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="fact_check" className="text-warning" />
                                Key Findings
                              </h3>
                              <div className="space-y-2">
                                {analysis.key_findings.map((finding, index) => (
                                  <div key={index} className="flex items-start gap-3 p-3 bg-warning/5 rounded-xl border border-warning/20">
                                    <Icon name="arrow_right" className="text-warning text-[18px] mt-0.5 flex-shrink-0" />
                                    <p className="text-sm text-body">{finding}</p>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Entities - Only for prescriptions */}
                          {isPrescription && analysis.entities && analysis.entities.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="label" className="text-primary" />
                                Key Entities Detected
                              </h3>
                              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                {analysis.entities.map((entity, index) => (
                                  <div key={index} className="p-4 bg-surface-2 rounded-xl border border-line">
                                    <p className="text-sm font-bold text-ink">{entity.text}</p>
                                    <div className="flex items-center justify-between mt-2">
                                      <span className={`${ui.badge} ${ui.badgeInfo}`}>
                                        {entity.label}
                                      </span>
                                      {entity.confidence && (
                                        <span className="text-xs text-muted">
                                          {Math.round(entity.confidence * 100)}% confidence
                                        </span>
                                      )}
                                    </div>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Recommendations */}
                          {analysis.recommendations && analysis.recommendations.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="lightbulb" className="text-primary" />
                                AI Recommendations
                              </h3>
                              <div className="space-y-2">
                                {analysis.recommendations.map((rec, index) => (
                                  <div key={index} className="flex items-start gap-3 p-3 bg-info/5 rounded-xl border border-info/20">
                                    <Icon name="check" className="text-info text-[18px] mt-0.5" />
                                    <p className="text-sm text-body">{rec}</p>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Prescription Details - Only show for prescriptions */}
                          {isPrescription && analysis.prescriptions && analysis.prescriptions.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="medication" className="text-primary" />
                                Prescription Details
                              </h3>
                              <div className="space-y-3">
                                {analysis.prescriptions.map((rx, index) => (
                                  <div key={index} className="p-4 bg-primary/5 rounded-xl border border-primary/20">
                                    <div className="flex items-center gap-2 mb-2">
                                      <Icon name="pill" className="text-primary text-[18px]" />
                                      <p className="text-base font-bold text-primary capitalize">
                                        {rx.medication}
                                      </p>
                                    </div>
                                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-2">
                                      {rx.dosage && (
                                        <div className="bg-surface rounded-lg px-3 py-1.5 border border-line">
                                          <p className="text-[10px] font-bold text-muted uppercase tracking-wider">Dosage</p>
                                          <p className="text-sm font-bold text-ink">{rx.dosage}</p>
                                        </div>
                                      )}
                                      {rx.frequency && (
                                        <div className="bg-surface rounded-lg px-3 py-1.5 border border-line">
                                          <p className="text-[10px] font-bold text-muted uppercase tracking-wider">Frequency</p>
                                          <p className="text-sm font-bold text-ink capitalize">{rx.frequency}</p>
                                        </div>
                                      )}
                                      {rx.route && (
                                        <div className="bg-surface rounded-lg px-3 py-1.5 border border-line">
                                          <p className="text-[10px] font-bold text-muted uppercase tracking-wider">Route</p>
                                          <p className="text-sm font-bold text-ink capitalize">{rx.route}</p>
                                        </div>
                                      )}
                                      {rx.duration && (
                                        <div className="bg-surface rounded-lg px-3 py-1.5 border border-line">
                                          <p className="text-[10px] font-bold text-muted uppercase tracking-wider">Duration</p>
                                          <p className="text-sm font-bold text-ink capitalize">{rx.duration}</p>
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Medications List (if prescription but no structured prescriptions) - Only show for prescriptions */}
                          {isPrescription && analysis.medications && analysis.medications.length > 0 && (!analysis.prescriptions || analysis.prescriptions.length === 0) && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="medication" className="text-primary" />
                                Medications Detected
                              </h3>
                              <div className="flex flex-wrap gap-2">
                                {analysis.medications.map((med, index) => (
                                  <span key={index} className="px-3 py-1.5 bg-primary/10 text-primary rounded-full text-sm font-bold capitalize">
                                    {med}
                                  </span>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* OCR Extracted Text - Only show for prescriptions */}
                          {isPrescription && analysis.ocr_text && (
                            <div>
                              <h3 className="text-lg font-bold text-ink mb-3 flex items-center gap-2">
                                <Icon name="text_fields" className="text-primary" />
                                OCR Extracted Text
                              </h3>
                              <div className="relative">
                                <pre className="text-sm text-body leading-relaxed p-4 bg-surface-2 rounded-xl border border-line whitespace-pre-wrap font-mono max-h-[300px] overflow-y-auto">
                                  {analysis.ocr_text}
                                </pre>
                              </div>
                            </div>
                          )}
                        </>
                      );
                    })()}
                  </div>
                </div>
              ) : (
                <div className={`${ui.card} p-12 text-center`}>
                  <EmptyState
                    icon="analytics"
                    title="Select a document"
                    hint="Choose a document from the list to view its AI analysis"
                  />
                </div>
              )}
            </div>
          </div>
        )}

        {/* Info Banner */}
        <Alert type="info">
          <p className="font-bold mb-1">AI Analysis Note</p>
          <p>
            AI analysis is provided for informational purposes only and should not replace professional medical judgment. 
            Always consult with a qualified healthcare provider for medical decisions.
          </p>
        </Alert>
      </div>

      <Toast
        message={toast?.message}
        type={toast?.type}
        onClose={() => setToast(null)}
      />
    </div>
  );
};

export default AIAnalysis;
