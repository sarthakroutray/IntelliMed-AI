import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { getDocument, verifyDocument, addClinicalNote, archiveDocument, downloadDocument } from '../services/api';
import { Modal, ConfirmDialog, Toast, Spinner } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const entityBadgeClass = (label) => {
  if (label === 'MEDICATION') return 'bg-primary/10 text-primary border-primary/20';
  if (label === 'DOSAGE') return 'bg-info/10 text-info border-info/20';
  if (label === 'FREQUENCY') return 'bg-success/10 text-success border-success/20';
  if (label === 'ROUTE') return 'bg-warning/10 text-warning border-warning/20';
  if (label === 'DURATION') return 'bg-info/10 text-info border-info/20';
  return 'bg-surface-2 text-muted border-line';
};

const MedicalDocumentViewer = () => {
  const { documentId } = useParams();
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  
  const [zoomLevel, setZoomLevel] = useState(100);
  const [document, setDocument] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showNoteModal, setShowNoteModal] = useState(false);
  const [showHistoryModal, setShowHistoryModal] = useState(false);
  const [showShareModal, setShowShareModal] = useState(false);
  const [clinicalNote, setClinicalNote] = useState('');
  const [toast, setToast] = useState(null);
  const [confirmAction, setConfirmAction] = useState(null);

  useEffect(() => {
    const fetchDocument = async () => {
      try {
        setLoading(true);
        const response = await getDocument(documentId);
        setDocument(response.data);
      } catch (err) {
        console.error('Error fetching document:', err);
        setError(err.response?.data?.detail || 'Failed to load document');
      } finally {
        setLoading(false);
      }
    };

    if (documentId) {
      fetchDocument();
    }
  }, [documentId]);

  // Parse AI analysis from backend format to UI format
  const parseAIAnalysis = (doc) => {
    if (!doc || !doc.ai_analysis) return null;
    
    try {
      const analysisData = doc.ai_analysis;
      
      if (typeof analysisData === 'object' && analysisData !== null) {
        const cv = analysisData.cv_result || {};
        const nlp = analysisData.nlp_result || {};
        const ocr = analysisData.ocr_result || '';
        
        // Use validated document type from backend
        const documentType = analysisData.detected_type || cv.document_type || nlp.document_type || 'document';
        
        return {
          documentType,
          cv,
          nlp,
          ocr_text: ocr,
          is_prescription: nlp.is_prescription || false,
          medical_summary: (analysisData.summary_result || {}).medical_summary || '',
          key_findings: (analysisData.summary_result || {}).key_findings || [],
        };
      }
    } catch (err) {
      console.error('Error parsing AI analysis:', err);
    }
    
    return null;
  };

  const analysis = useMemo(() => document ? parseAIAnalysis(document) : null, [document]);
  const verification = document ? {
    verifiedBy: document.verified_by ?? document.verification?.verified_by ?? null,
    verifiedAt: document.verified_at ?? document.verification?.verified_at ?? null,
    notes: document.verification_notes ?? document.verification?.notes ?? null,
  } : null;
  const clinicalNotes = document ? (document.clinical_notes ?? document.verification?.clinical_notes ?? []) : [];
  const isArchived = Boolean(document?.archived ?? document?.verification?.archived);

  const handleZoomIn = useCallback(() => setZoomLevel(prev => Math.min(prev + 10, 200)), []);
  const handleZoomOut = useCallback(() => setZoomLevel(prev => Math.max(prev - 10, 50)), []);
  const handleResetZoom = useCallback(() => setZoomLevel(100), []);

  const handleVerifyDocument = async () => {
    try {
      await verifyDocument(documentId);
      const refreshed = await getDocument(documentId);
      setDocument(refreshed.data);
      setToast({ type: 'success', message: 'Document verified successfully!' });
    } catch (err) {
      setToast({ type: 'error', message: 'Failed to verify document: ' + (err.response?.data?.detail || 'Unknown error') });
    }
  };

  const handleAddNote = async () => {
    if (!clinicalNote.trim()) {
      setToast({ type: 'warning', message: 'Please enter a note' });
      return;
    }
    
    try {
      await addClinicalNote(documentId, clinicalNote);
      const refreshed = await getDocument(documentId);
      setDocument(refreshed.data);
      setToast({ type: 'success', message: 'Clinical note added successfully!' });
      setClinicalNote('');
      setShowNoteModal(false);
    } catch (err) {
      setToast({ type: 'error', message: 'Failed to add note: ' + (err.response?.data?.detail || 'Unknown error') });
    }
  };

  const handleDownload = async () => {
    try {
      const response = await downloadDocument(documentId);
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = window.document.createElement('a');
      link.href = url;
      link.setAttribute('download', document.fileName || 'document');
      window.document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      setToast({ type: 'error', message: 'Failed to download document: ' + (err.response?.data?.detail || 'Unknown error') });
    }
  };

  const handleArchive = async () => {
    try {
      await archiveDocument(documentId);
      setToast({ type: 'success', message: 'Document archived successfully!' });
      navigate('/dashboard');
    } catch (err) {
      setToast({ type: 'error', message: 'Failed to archive document: ' + (err.response?.data?.detail || 'Unknown error') });
    }
  };

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  if (loading) {
    return (
      <div className="h-screen flex items-center justify-center bg-canvas">
        <div className="text-center">
          <Spinner className="size-12 mx-auto mb-4" />
          <p className="text-muted">Loading document...</p>
        </div>
      </div>
    );
  }

  if (!document) {
    return (
      <div className="h-screen flex items-center justify-center bg-canvas">
        <div className="text-center">
          <p className="text-body mb-4">{error || 'Document not found'}</p>
          <button type="button"
            onClick={() => navigate('/dashboard')}
            className={`${ui.btn} ${ui.btnPrimary}`}
          >
            Back to Dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-canvas text-ink h-screen flex flex-col overflow-hidden">
      {/* Top Navigation */}
      <header className="flex-none flex items-center justify-between whitespace-nowrap border-b border-line bg-surface px-6 py-3 z-20">
        <div className="flex items-center gap-4 text-ink">
          <div className="size-8 text-primary flex items-center justify-center">
            <span className="material-symbols-outlined !text-[32px]">health_and_safety</span>
          </div>
          <h2 className="text-ink text-xl font-bold leading-tight tracking-tight">IntelliMed-AI</h2>
        </div>
        <div className="flex flex-1 justify-end gap-6 items-center">
          {/* Action Buttons */}
          <div className="hidden md:flex gap-2">
            <button type="button"
              onClick={handleDownload}
              className={`${ui.btn} ${ui.btnSecondary} h-9`}
            >
              <span className="material-symbols-outlined !text-[20px]">download</span>
              <span>Download</span>
            </button>
            <button type="button"
              onClick={() => setShowShareModal(true)}
              className={`${ui.btn} ${ui.btnSecondary} h-9`}
            >
              <span className="material-symbols-outlined !text-[20px]">share</span>
              <span>Share</span>
            </button>
            {user && user.role === 'doctor' && (
              <button type="button"
                onClick={() => setConfirmAction({ kind: 'archive' })}
                className={`${ui.btn} ${ui.btnSecondary} h-9`}
              >
                <span className="material-symbols-outlined !text-[20px]">inventory_2</span>
                <span>Archive</span>
              </button>
            )}
          </div>
          {/* User Profile */}
          <div className="flex items-center gap-3 pl-6 border-l border-line">
            <div className="text-right hidden sm:block">
              <p className="text-sm font-bold leading-none text-ink">{user?.email || 'User'}</p>
              <p className="text-xs text-muted mt-1">
                {user?.role === 'doctor' ? 'Cardiology Dept.' : user?.role === 'patient' ? 'Patient' : 'User'}
              </p>
            </div>
            <button
              type="button"
              title="Sign out"
              aria-label="Sign out"
              className="bg-primary flex items-center justify-center rounded-full size-10 text-white font-bold text-sm cursor-pointer hover:opacity-90 transition-opacity"
              onClick={() => setConfirmAction({ kind: 'logout' })}
            >
              {user?.email?.charAt(0).toUpperCase() || 'U'}
            </button>
          </div>
        </div>
      </header>

      {/* Main Content Layout */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left Panel: Document Viewer */}
        <main className="flex-1 flex flex-col min-w-0 overflow-y-auto bg-canvas p-4 md:p-6 lg:p-8 relative">
          {/* Breadcrumbs */}
          <div className="flex flex-wrap gap-2 mb-4 text-sm">
            <Link to="/dashboard" className="text-muted hover:text-primary transition-colors font-medium">Home</Link>
            <span className="text-subtle">/</span>
            {user?.role === 'doctor' ? (
              <>
                <Link to="/dashboard" className="text-muted hover:text-primary transition-colors font-medium">Patients</Link>
                <span className="text-subtle">/</span>
                <Link to={`/patient/${document.patient.id}`} className="text-muted hover:text-primary transition-colors font-medium">{document.patient.name}</Link>
              </>
            ) : (
              <>
                <span className="text-muted">My Documents</span>
              </>
            )}
            <span className="text-subtle">/</span>
            <span className="text-ink font-medium">{document.title}</span>
          </div>

          {/* Header */}
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-4 mb-6">
            <div>
              <h1 className="text-ink text-3xl font-extrabold tracking-tight">{document.title}</h1>
              <p className="text-muted mt-1">Scan ID: #{document.id} • {document.timestamp}</p>
            </div>
            <div className="flex items-center gap-2">
              <span className={`${ui.badge} ${ui.badgeSuccess}`}>
                {document.status}
              </span>
              <span className="text-subtle text-sm">{document.fileType} • {document.fileSize}</span>
            </div>
          </div>

          {/* Viewer Container */}
          <div className="flex-1 min-h-[500px] bg-surface-2 rounded-2xl border border-line relative overflow-hidden group shadow-card flex flex-col">
            {/* Main Document Display */}
            <div className="absolute inset-0 flex items-center justify-center bg-black">
              {document.fileName && (document.fileName.toLowerCase().endsWith('.pdf') || document.fileType === 'PDF') ? (
                // PDF Viewer
                <iframe
                  src={document.fileUrl || document.imageUrl}
                  className="w-full h-full"
                  title="PDF Document"
                  style={{
                    transform: `scale(${zoomLevel / 100})`,
                    transformOrigin: 'center center',
                    width: `${100 * (100 / zoomLevel)}%`,
                    height: `${100 * (100 / zoomLevel)}%`,
                  }}
                />
              ) : (
                // Image Viewer
                <div
                  className="w-full h-full bg-contain bg-center bg-no-repeat opacity-90 transition-transform duration-200"
                  style={{
                    backgroundImage: `url('${document.imageUrl || document.fileUrl}')`,
                    transform: `scale(${zoomLevel / 100})`
                  }}
                />
              )}
            </div>

            {/* Floating Toolbar */}
            <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-1 bg-surface/90 backdrop-blur-sm p-1.5 rounded-full shadow-pop border border-line opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              <button type="button"
                onClick={handleZoomIn}
                className="p-2 rounded-full hover:bg-surface-2 text-body transition-colors"
                title="Zoom In"
              >
                <span className="material-symbols-outlined">zoom_in</span>
              </button>
              <button type="button"
                onClick={handleZoomOut}
                className="p-2 rounded-full hover:bg-surface-2 text-body transition-colors"
                title="Zoom Out"
              >
                <span className="material-symbols-outlined">zoom_out</span>
              </button>
              <div className="w-px h-6 bg-line mx-1"></div>
              <button type="button" className="p-2 rounded-full hover:bg-surface-2 text-body transition-colors" title="Pan Mode">
                <span className="material-symbols-outlined">drag_pan</span>
              </button>
              <button type="button"
                onClick={handleResetZoom}
                className="p-2 rounded-full hover:bg-surface-2 text-body transition-colors"
                title="Reset View"
              >
                <span className="material-symbols-outlined">restart_alt</span>
              </button>
            </div>

            {/* Overlay Info */}
            <div className="absolute top-4 left-4 bg-black/50 backdrop-blur-sm text-white text-xs px-3 py-1.5 rounded-md font-mono">
              zoom: {zoomLevel}%
            </div>
          </div>

          <div className="mt-4 flex justify-between items-center text-sm text-muted">
            <span>File: {document.fileName}</span>
            <button type="button"
              onClick={() => setShowHistoryModal(true)}
              className="text-primary hover:underline font-medium"
            >
              View History
            </button>
          </div>
        </main>

        {/* Right Panel: AI Analysis */}
        <aside className="w-full md:w-[400px] lg:w-[450px] bg-surface border-l border-line flex flex-col overflow-y-auto shadow-card z-10">
          <div className="p-6 border-b border-line flex justify-between items-center sticky top-0 bg-surface z-10">
            <div className="flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">smart_toy</span>
              <h3 className="text-lg font-bold text-ink">AI Analysis</h3>
            </div>
            <button type="button" className="text-subtle hover:text-primary transition-colors">
              <span className="material-symbols-outlined">more_vert</span>
            </button>
          </div>

          <div className="p-6 flex flex-col gap-6 flex-1">
            {!analysis ? (
              <div className="text-center py-8">
                <span className="material-symbols-outlined text-subtle text-5xl">pending</span>
                <p className="text-sm text-muted mt-3">No AI analysis available</p>
              </div>
            ) : (
              <>
                {/* X-ray Classification - Only for X-rays */}
                {analysis.documentType === 'xray' && analysis.cv.classification && (
                  <>
                    {/* Summary Card */}
                    <div className={`${
                      analysis.cv.classification === 'Normal'
                        ? 'bg-success/5 border-success/20'
                        : 'bg-danger/5 border-danger/20'
                    } border rounded-2xl p-5 shadow-card`}>
                      <div className="flex items-start gap-3">
                        <div className={`mt-0.5 ${
                          analysis.cv.classification === 'Normal'
                            ? 'bg-success/10 text-success'
                            : 'bg-danger/10 text-danger'
                        } rounded-full p-1`}>
                          <span className="material-symbols-outlined !text-[20px]">
                            {analysis.cv.classification === 'Normal' ? 'check_circle' : 'warning'}
                          </span>
                        </div>
                        <div>
                          <h4 className={`${
                            analysis.cv.classification === 'Normal' ? 'text-success' : 'text-danger'
                          } font-bold text-sm mb-1`}>{analysis.cv.classification}</h4>
                          <p className={`text-sm leading-relaxed ${
                            analysis.cv.classification === 'Normal' ? 'text-success/80' : 'text-danger/80'
                          }`}>
                            {analysis.cv.recommendation || 'Analysis completed'}
                          </p>
                          <p className="text-xs text-muted mt-1">
                            Confidence: {(analysis.cv.confidence * 100).toFixed(1)}%
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Probabilities */}
                    {analysis.cv.probabilities && (
                      <div className="flex flex-col gap-4">
                        <div className="flex justify-between items-center">
                          <h4 className="text-sm font-bold text-ink uppercase tracking-wider">Class Probabilities</h4>
                          <span className="text-xs font-medium text-subtle">Confidence</span>
                        </div>

                        {Object.entries(analysis.cv.probabilities).map(([label, prob]) => (
                          <div key={label}>
                            <div className="flex justify-between text-sm mb-1.5">
                              <span className="font-medium text-body">{label}</span>
                              <span className={`font-bold ${prob > 0.5 ? 'text-primary' : 'text-subtle'}`}>
                                {(prob * 100).toFixed(1)}%
                              </span>
                            </div>
                            <div className="h-2 w-full bg-surface-2 rounded-full overflow-hidden">
                              <div
                                className={`h-full rounded-full transition-all ${
                                  label === 'Normal' ? 'bg-success' : 'bg-danger'
                                }`}
                                style={{width: `${Math.max(prob * 100, 1)}%`}}
                              />
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}

                {/* Prescription Details - Only for prescriptions */}
                {analysis.documentType === 'prescription' && (
                  <>
                    {/* Summary for prescriptions - only if meaningful */}
                    {analysis.nlp.summary && !analysis.nlp.summary.includes('No text available') && (
                      <div className="bg-primary/5 border border-primary/20 rounded-2xl p-5 shadow-card">
                        <div className="flex items-start gap-3">
                          <div className="mt-0.5 bg-primary/10 rounded-full p-1 text-primary">
                            <span className="material-symbols-outlined !text-[20px]">description</span>
                          </div>
                          <div>
                            <h4 className="text-primary font-bold text-sm mb-1">Prescription Document</h4>
                            <p className="text-primary/80 text-sm leading-relaxed">
                              {analysis.nlp.summary}
                            </p>
                          </div>
                        </div>
                      </div>
                    )}
                  </>
                )}

                {/* Divider */}
                <div className="h-px bg-line my-2"></div>

                {/* Medical Summary (T5-generated) */}
                {analysis.medical_summary && analysis.medical_summary.length > 10 && (
                  <div className="flex flex-col gap-2">
                    <h4 className="text-sm font-bold text-ink uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-success !text-[18px]">clinical_notes</span>
                      Medical Summary
                      <span className={`${ui.badge} ${ui.badgeSuccess} ml-auto`}>AI</span>
                    </h4>
                    <p className="text-sm text-body leading-relaxed p-3 bg-success/5 rounded-xl border border-success/20">
                      {analysis.medical_summary}
                    </p>
                  </div>
                )}

                {/* Key Findings */}
                {analysis.key_findings && analysis.key_findings.length > 0 && (
                  <div className="flex flex-col gap-2">
                    <h4 className="text-sm font-bold text-ink uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-warning !text-[18px]">fact_check</span>
                      Key Findings
                    </h4>
                    <div className="flex flex-col gap-1.5">
                      {analysis.key_findings.map((finding, index) => (
                        <div key={index} className="flex items-start gap-2 p-2 bg-warning/5 rounded-xl border border-warning/20">
                          <span className="material-symbols-outlined text-warning !text-[16px] mt-0.5 flex-shrink-0">arrow_right</span>
                          <p className="text-xs text-body">{finding}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Prescription Details (from NLP) - Only for prescriptions */}
                {analysis.documentType === 'prescription' && analysis.nlp.prescriptions?.length > 0 && (
                  <div className="flex flex-col gap-3">
                    <h4 className="text-sm font-bold text-ink uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-primary !text-[18px]">medication</span>
                      Prescription Details
                    </h4>
                    {analysis.nlp.prescriptions.map((rx, index) => (
                      <div key={index} className="p-3 bg-primary/5 rounded-xl border border-primary/20">
                        <p className="text-sm font-bold text-primary capitalize mb-2">{rx.medication}</p>
                        <div className="grid grid-cols-2 gap-2">
                          {rx.dosage && (
                            <div>
                              <p className="text-[10px] font-bold text-muted uppercase">Dosage</p>
                              <p className="text-xs font-medium text-body">{rx.dosage}</p>
                            </div>
                          )}
                          {rx.frequency && (
                            <div>
                              <p className="text-[10px] font-bold text-muted uppercase">Frequency</p>
                              <p className="text-xs font-medium text-body capitalize">{rx.frequency}</p>
                            </div>
                          )}
                          {rx.route && (
                            <div>
                              <p className="text-[10px] font-bold text-muted uppercase">Route</p>
                              <p className="text-xs font-medium text-body capitalize">{rx.route}</p>
                            </div>
                          )}
                          {rx.duration && (
                            <div>
                              <p className="text-[10px] font-bold text-muted uppercase">Duration</p>
                              <p className="text-xs font-medium text-body capitalize">{rx.duration}</p>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}

                {/* NLP Entities - Only for prescriptions */}
                {analysis.documentType === 'prescription' && analysis.nlp.entities?.length > 0 && (
                  <div className="flex flex-col gap-3">
                    <h4 className="text-sm font-bold text-ink uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-primary !text-[18px]">label</span>
                      Entities Detected
                    </h4>
                    <div className="flex flex-wrap gap-1.5">
                      {analysis.nlp.entities.slice(0, 12).map((entity, index) => (
                        <span key={index} className={`inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs font-medium border ${entityBadgeClass(entity.label)}`}>
                          <span>{entity.text}</span>
                          <span className="text-[9px] opacity-60">({entity.label})</span>
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {/* OCR Extracted Text - Only for prescriptions */}
                {analysis.documentType === 'prescription' && analysis.ocr_text && (
                  <details className="group bg-surface-2 rounded-xl border border-line overflow-hidden">
                    <summary className="flex justify-between items-center p-3 cursor-pointer select-none">
                      <div className="flex items-center gap-2 text-sm font-semibold text-body">
                        <span className="material-symbols-outlined !text-[18px]">text_fields</span>
                        OCR Extracted Text
                      </div>
                      <span className="material-symbols-outlined text-subtle group-open:rotate-180 transition-transform">expand_more</span>
                    </summary>
                    <div className="p-3 pt-0 border-t border-line overflow-x-auto">
                      <pre className="text-[11px] font-mono leading-relaxed text-muted whitespace-pre-wrap">
                        {analysis.ocr_text}
                      </pre>
                    </div>
                  </details>
                )}

                {/* Raw JSON Toggle */}
                <details className="group bg-surface-2 rounded-xl border border-line overflow-hidden">
                  <summary className="flex justify-between items-center p-3 cursor-pointer select-none">
                    <div className="flex items-center gap-2 text-sm font-semibold text-body">
                      <span className="material-symbols-outlined !text-[18px]">data_object</span>
                      Raw API Response
                    </div>
                    <span className="material-symbols-outlined text-subtle group-open:rotate-180 transition-transform">expand_more</span>
                  </summary>
                  <div className="p-3 pt-0 border-t border-line overflow-x-auto">
                    <pre className="text-[10px] font-mono leading-tight text-muted">
                      {JSON.stringify(document.ai_analysis, null, 2)}
                    </pre>
                  </div>
                </details>
              </>
            )}

            {/* Actions */}
            {user && user.role === 'doctor' && (
              <div className="mt-auto pt-6 flex flex-col gap-3">
                <button type="button"
                  onClick={handleVerifyDocument}
                  className={`${ui.btn} ${ui.btnPrimary} w-full h-11`}
                >
                  <span className="material-symbols-outlined !text-[20px]">verified</span>
                  Verify &amp; Sign Off
                </button>
                <button type="button"
                  onClick={() => setShowNoteModal(true)}
                  className={`${ui.btn} ${ui.btnSecondary} w-full h-11`}
                >
                  <span className="material-symbols-outlined !text-[20px]">edit_note</span>
                  Add Clinical Note
                </button>
              </div>
            )}
          </div>

          {/* Disclaimer Footer */}
          <div className="bg-surface-2 p-4 text-center border-t border-line mt-auto">
            <p className="text-[10px] text-subtle leading-snug">
              <span className="font-bold">Disclaimer:</span> AI results are assistive only and must be verified by a certified medical professional before diagnosis.
            </p>
          </div>
        </aside>
      </div>

      {/* Clinical Note Modal */}
      <Modal
        open={showNoteModal}
        onClose={() => {
          setShowNoteModal(false);
          setClinicalNote('');
        }}
        title="Add Clinical Note"
      >
        <textarea aria-label="Clinical note"
          value={clinicalNote}
          onChange={(e) => setClinicalNote(e.target.value)}
          className={`${ui.input} h-32 resize-none`}
          placeholder="Enter your clinical observations and notes..."
        />
        <div className="flex gap-3 mt-4">
          <button type="button"
            onClick={handleAddNote}
            className={`${ui.btn} ${ui.btnPrimary} flex-1`}
          >
            Save Note
          </button>
          <button type="button"
            onClick={() => {
              setShowNoteModal(false);
              setClinicalNote('');
            }}
            className={`${ui.btn} ${ui.btnSecondary} flex-1`}
          >
            Cancel
          </button>
        </div>
      </Modal>

      {/* History Modal */}
      <Modal
        open={showHistoryModal}
        onClose={() => setShowHistoryModal(false)}
        title="Document History"
        maxWidth="max-w-2xl"
      >
        <div className="overflow-y-auto max-h-[60vh]">
          {/* Upload Info */}
          <div className="mb-6">
            <h4 className="text-sm font-bold text-ink mb-3 flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">upload</span>
              Upload Information
            </h4>
            <div className="bg-surface-2 rounded-xl p-4">
              <p className="text-sm text-body">
                <span className="font-medium">Uploaded:</span> {document.timestamp}
              </p>
              <p className="text-sm text-body mt-1">
                <span className="font-medium">Patient:</span> {document.patient.name}
              </p>
            </div>
          </div>

          {/* Verification Status */}
          <div className="mb-6">
            <h4 className="text-sm font-bold text-ink mb-3 flex items-center gap-2">
              <span className="material-symbols-outlined text-success">verified</span>
              Verification Status
            </h4>
            <div className="bg-surface-2 rounded-xl p-4">
              {verification?.verifiedAt || verification?.verifiedBy ? (
                <div className="text-sm text-body">
                  <p>
                    <span className="font-medium">Verified by:</span> {verification.verifiedBy ?? 'Doctor'}
                  </p>
                  {verification.verifiedAt && (
                    <p className="mt-1">
                      <span className="font-medium">At:</span> {new Date(verification.verifiedAt).toLocaleString()}
                    </p>
                  )}
                  {verification.notes && (
                    <p className="mt-1">
                      <span className="font-medium">Notes:</span> {verification.notes}
                    </p>
                  )}
                </div>
              ) : (
                <p className="text-sm text-muted">
                  No verification records yet. Awaiting doctor review.
                </p>
              )}
              {isArchived && (
                <p className="text-sm text-warning mt-2 font-medium">
                  This document has been archived.
                </p>
              )}
            </div>
          </div>

          {/* Clinical Notes */}
          <div>
            <h4 className="text-sm font-bold text-ink mb-3 flex items-center gap-2">
              <span className="material-symbols-outlined text-info">edit_note</span>
              Clinical Notes ({clinicalNotes.length})
            </h4>
            <div className="bg-surface-2 rounded-xl p-4">
              {clinicalNotes.length > 0 ? (
                <div className="space-y-3">
                  {clinicalNotes.map((n, idx) => (
                    <div key={idx} className="text-sm text-body border-b border-line last:border-0 pb-2 last:pb-0">
                      <p>{n.note || n.text}</p>
                      <p className="text-xs text-muted mt-1">
                        {n.added_by || n.author || 'Doctor'}
                        {n.added_at ? ` • ${new Date(n.added_at).toLocaleString()}` : ''}
                      </p>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-sm text-muted">
                  No clinical notes added yet.
                </p>
              )}
            </div>
          </div>
        </div>
      </Modal>

      {/* Share Modal */}
      <Modal
        open={showShareModal}
        onClose={() => setShowShareModal(false)}
        title="Share Document"
      >
        <p className="text-sm text-body mb-4">
          {user?.role === 'patient'
            ? 'This document can be shared with your linked doctors via the dashboard.'
            : 'Document sharing is managed by the patient.'}
        </p>
        <button type="button"
          onClick={() => setShowShareModal(false)}
          className={`${ui.btn} ${ui.btnPrimary} w-full`}
        >
          Got it
        </button>
      </Modal>

      {/* Destructive / sign-out Confirmation */}
      <ConfirmDialog
        open={confirmAction !== null}
        title={confirmAction?.kind === 'logout' ? 'Sign out?' : 'Archive document?'}
        message={
          confirmAction?.kind === 'logout'
            ? 'Do you want to logout?'
            : 'Are you sure you want to archive this document?'
        }
        confirmLabel={confirmAction?.kind === 'logout' ? 'Logout' : 'Archive'}
        danger={confirmAction?.kind === 'logout'}
        onConfirm={() => {
          const kind = confirmAction?.kind;
          setConfirmAction(null);
          if (kind === 'logout') handleLogout();
          else handleArchive();
        }}
        onCancel={() => setConfirmAction(null)}
      />

      <Toast
        message={toast?.message}
        type={toast?.type}
        onClose={() => setToast(null)}
      />
    </div>
  );
};

export default MedicalDocumentViewer;
