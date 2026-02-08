import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { getDocument, verifyDocument, addClinicalNote, archiveDocument, downloadDocument } from '../services/api';

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
        };
      }
    } catch (err) {
      console.error('Error parsing AI analysis:', err);
    }
    
    return null;
  };

  const analysis = useMemo(() => document ? parseAIAnalysis(document) : null, [document]);

  const handleZoomIn = useCallback(() => setZoomLevel(prev => Math.min(prev + 10, 200)), []);
  const handleZoomOut = useCallback(() => setZoomLevel(prev => Math.max(prev - 10, 50)), []);
  const handleResetZoom = useCallback(() => setZoomLevel(100), []);

  const handleVerifyDocument = async () => {
    try {
      await verifyDocument(documentId);
      alert('Document verified successfully!');
    } catch (err) {
      alert('Failed to verify document: ' + (err.response?.data?.detail || 'Unknown error'));
    }
  };

  const handleAddNote = async () => {
    if (!clinicalNote.trim()) {
      alert('Please enter a note');
      return;
    }
    
    try {
      await addClinicalNote(documentId, clinicalNote);
      alert('Clinical note added successfully!');
      setClinicalNote('');
      setShowNoteModal(false);
    } catch (err) {
      alert('Failed to add note: ' + (err.response?.data?.detail || 'Unknown error'));
    }
  };

  const handleDownload = async () => {
    try {
      const response = await downloadDocument(documentId);
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement('a');
      link.href = url;
      link.setAttribute('download', document.fileName || 'document');
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      alert('Failed to download document: ' + (err.response?.data?.detail || 'Unknown error'));
    }
  };

  const handleArchive = async () => {
    if (!window.confirm('Are you sure you want to archive this document?')) {
      return;
    }
    
    try {
      await archiveDocument(documentId);
      alert('Document archived successfully!');
      navigate('/dashboard');
    } catch (err) {
      alert('Failed to archive document: ' + (err.response?.data?.detail || 'Unknown error'));
    }
  };

  if (loading) {
    return (
      <div className="h-screen flex items-center justify-center bg-background-light dark:bg-background-dark">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary mx-auto mb-4"></div>
          <p className="text-slate-600 dark:text-slate-400">Loading document...</p>
        </div>
      </div>
    );
  }

  if (!document) {
    return (
      <div className="h-screen flex items-center justify-center bg-background-light dark:bg-background-dark">
        <div className="text-center">
          <p className="text-slate-600 dark:text-slate-400 mb-4">{error || 'Document not found'}</p>
          <button 
            onClick={() => navigate('/dashboard')}
            className="px-4 py-2 bg-primary text-white rounded-lg hover:bg-blue-700"
          >
            Back to Dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-background-light dark:bg-background-dark text-slate-900 dark:text-white h-screen flex flex-col overflow-hidden">
      {/* Top Navigation */}
      <header className="flex-none flex items-center justify-between whitespace-nowrap border-b border-solid border-slate-200 dark:border-slate-800 bg-white dark:bg-[#1A202C] px-6 py-3 z-20">
        <div className="flex items-center gap-4 text-slate-900 dark:text-white">
          <div className="size-8 text-primary flex items-center justify-center">
            <span className="material-symbols-outlined !text-[32px]">health_and_safety</span>
          </div>
          <h2 className="text-slate-900 dark:text-white text-xl font-bold leading-tight tracking-tight">IntelliMed-AI</h2>
        </div>
        <div className="flex flex-1 justify-end gap-6 items-center">
          {/* Action Buttons */}
          <div className="hidden md:flex gap-2">
            <button 
              onClick={handleDownload}
              className="flex items-center justify-center rounded-lg h-9 bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-900 dark:text-white gap-2 text-sm font-bold px-4 transition-colors"
            >
              <span className="material-symbols-outlined !text-[20px]">download</span>
              <span>Download</span>
            </button>
            <button 
              onClick={() => setShowShareModal(true)}
              className="flex items-center justify-center rounded-lg h-9 bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-900 dark:text-white gap-2 text-sm font-bold px-4 transition-colors"
            >
              <span className="material-symbols-outlined !text-[20px]">share</span>
              <span>Share</span>
            </button>
            {user && user.role === 'doctor' && (
              <button 
                onClick={handleArchive}
                className="flex items-center justify-center rounded-lg h-9 bg-slate-100 hover:bg-slate-200 dark:bg-slate-800 dark:hover:bg-slate-700 text-slate-900 dark:text-white gap-2 text-sm font-bold px-4 transition-colors"
              >
                <span className="material-symbols-outlined !text-[20px]">inventory_2</span>
                <span>Archive</span>
              </button>
            )}
          </div>
          {/* User Profile */}
          <div className="flex items-center gap-3 pl-6 border-l border-slate-200 dark:border-slate-700">
            <div className="text-right hidden sm:block">
              <p className="text-sm font-bold leading-none">{user?.email || 'User'}</p>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                {user?.role === 'doctor' ? 'Cardiology Dept.' : user?.role === 'patient' ? 'Patient' : 'User'}
              </p>
            </div>
            <div 
              className="bg-center bg-no-repeat bg-cover rounded-full size-10 border-2 border-slate-100 dark:border-slate-700 cursor-pointer"
              style={{backgroundImage: "url('https://lh3.googleusercontent.com/aida-public/AB6AXuDT9gmRag5yEY-DQYZXE0G6h2CkhKyUQS_5zrzjf3YAVG6PhjvxJwOIhCwxi46od3peHROaEx0cc9xqAd-5Yihc_WVUgEX2ptHK8U_HQa7GJx2NvzQFlp6bXZkX36vPmWe2wEB8TDryxjhcQiPxxPlNP_Gro8wlOQ-QB6WZhhIYk27Tl3P7xz59df02P2HkJkEJvhfPG-BvDWTH2GgUE8zjnz8cTuaVwPSRIhiz2QKbO8lsAFXfyPuaUf-vMJO8y12GUHZRwYJ9REFb')"}}
              onClick={() => {
                if (window.confirm('Do you want to logout?')) {
                  logout();
                  navigate('/login');
                }
              }}
            />
          </div>
        </div>
      </header>

      {/* Main Content Layout */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left Panel: Document Viewer */}
        <main className="flex-1 flex flex-col min-w-0 overflow-y-auto bg-slate-50 dark:bg-background-dark p-4 md:p-6 lg:p-8 relative">
          {/* Breadcrumbs */}
          <div className="flex flex-wrap gap-2 mb-4 text-sm">
            <Link to="/dashboard" className="text-slate-500 hover:text-primary transition-colors font-medium">Home</Link>
            <span className="text-slate-400">/</span>
            {user?.role === 'doctor' ? (
              <>
                <Link to="/dashboard" className="text-slate-500 hover:text-primary transition-colors font-medium">Patients</Link>
                <span className="text-slate-400">/</span>
                <Link to={`/patient/${document.patient.id}`} className="text-slate-500 hover:text-primary transition-colors font-medium">{document.patient.name}</Link>
              </>
            ) : (
              <>
                <span className="text-slate-500">My Documents</span>
              </>
            )}
            <span className="text-slate-400">/</span>
            <span className="text-slate-900 dark:text-white font-medium">{document.title}</span>
          </div>

          {/* Header */}
          <div className="flex flex-col md:flex-row md:items-end justify-between gap-4 mb-6">
            <div>
              <h1 className="text-slate-900 dark:text-white text-3xl font-bold tracking-tight">{document.title}</h1>
              <p className="text-slate-500 dark:text-slate-400 mt-1">Scan ID: #{document.id} • {document.timestamp}</p>
            </div>
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300">
                {document.status}
              </span>
              <span className="text-slate-400 text-sm">{document.fileType} • {document.fileSize}</span>
            </div>
          </div>

          {/* Viewer Container */}
          <div className="flex-1 min-h-[500px] bg-slate-200 dark:bg-[#0f1520] rounded-xl border border-slate-300 dark:border-slate-700 relative overflow-hidden group shadow-inner flex flex-col">
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
            <div className="absolute bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-1 bg-white/90 dark:bg-slate-800/90 backdrop-blur-sm p-1.5 rounded-full shadow-lg border border-slate-200 dark:border-slate-700 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
              <button 
                onClick={handleZoomIn}
                className="p-2 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors"
                title="Zoom In"
              >
                <span className="material-symbols-outlined">zoom_in</span>
              </button>
              <button 
                onClick={handleZoomOut}
                className="p-2 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors"
                title="Zoom Out"
              >
                <span className="material-symbols-outlined">zoom_out</span>
              </button>
              <div className="w-px h-6 bg-slate-300 dark:bg-slate-600 mx-1"></div>
              <button className="p-2 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors" title="Pan Mode">
                <span className="material-symbols-outlined">drag_pan</span>
              </button>
              <button 
                onClick={handleResetZoom}
                className="p-2 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 text-slate-700 dark:text-slate-200 transition-colors"
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

          <div className="mt-4 flex justify-between items-center text-sm text-slate-500 dark:text-slate-400">
            <span>File: {document.fileName}</span>
            <button 
              onClick={() => setShowHistoryModal(true)}
              className="text-primary hover:underline font-medium"
            >
              View History
            </button>
          </div>
        </main>

        {/* Right Panel: AI Analysis */}
        <aside className="w-full md:w-[400px] lg:w-[450px] bg-white dark:bg-[#151b28] border-l border-slate-200 dark:border-slate-800 flex flex-col overflow-y-auto shadow-xl z-10">
          <div className="p-6 border-b border-slate-100 dark:border-slate-800 flex justify-between items-center sticky top-0 bg-white dark:bg-[#151b28] z-10">
            <div className="flex items-center gap-2">
              <span className="material-symbols-outlined text-primary">smart_toy</span>
              <h3 className="text-lg font-bold text-slate-900 dark:text-white">AI Analysis</h3>
            </div>
            <button className="text-slate-400 hover:text-primary transition-colors">
              <span className="material-symbols-outlined">more_vert</span>
            </button>
          </div>

          <div className="p-6 flex flex-col gap-6 flex-1">
            {!analysis ? (
              <div className="text-center py-8">
                <span className="material-symbols-outlined text-slate-300 dark:text-slate-600 text-5xl">pending</span>
                <p className="text-sm text-slate-500 dark:text-slate-400 mt-3">No AI analysis available</p>
              </div>
            ) : (
              <>
                {/* X-ray Classification - Only for X-rays */}
                {analysis.documentType === 'xray' && analysis.cv.classification && (
                  <>
                    {/* Summary Card */}
                    <div className={`bg-gradient-to-br ${
                      analysis.cv.classification === 'Normal'
                        ? 'from-green-50 to-emerald-50 dark:from-green-900/20 dark:to-emerald-900/10 border-green-100 dark:border-green-800/30'
                        : 'from-red-50 to-rose-50 dark:from-red-900/20 dark:to-rose-900/10 border-red-100 dark:border-red-800/30'
                    } border rounded-xl p-5 shadow-sm`}>
                      <div className="flex items-start gap-3">
                        <div className={`mt-0.5 ${
                          analysis.cv.classification === 'Normal' 
                            ? 'bg-green-100 dark:bg-green-900/50 text-green-600 dark:text-green-400' 
                            : 'bg-red-100 dark:bg-red-900/50 text-red-600 dark:text-red-400'
                        } rounded-full p-1`}>
                          <span className="material-symbols-outlined !text-[20px]">
                            {analysis.cv.classification === 'Normal' ? 'check_circle' : 'warning'}
                          </span>
                        </div>
                        <div>
                          <h4 className={`${
                            analysis.cv.classification === 'Normal'
                              ? 'text-green-800 dark:text-green-300'
                              : 'text-red-800 dark:text-red-300'
                          } font-bold text-sm mb-1`}>{analysis.cv.classification}</h4>
                          <p className={`text-sm leading-relaxed ${
                            analysis.cv.classification === 'Normal'
                              ? 'text-green-700/80 dark:text-green-400/80'
                              : 'text-red-700/80 dark:text-red-400/80'
                          }`}>
                            {analysis.cv.recommendation || 'Analysis completed'}
                          </p>
                          <p className="text-xs text-slate-500 mt-1">
                            Confidence: {(analysis.cv.confidence * 100).toFixed(1)}%
                          </p>
                        </div>
                      </div>
                    </div>

                    {/* Probabilities */}
                    {analysis.cv.probabilities && (
                      <div className="flex flex-col gap-4">
                        <div className="flex justify-between items-center">
                          <h4 className="text-sm font-bold text-slate-900 dark:text-white uppercase tracking-wider">Class Probabilities</h4>
                          <span className="text-xs font-medium text-slate-400">Confidence</span>
                        </div>

                        {Object.entries(analysis.cv.probabilities).map(([label, prob]) => (
                          <div key={label}>
                            <div className="flex justify-between text-sm mb-1.5">
                              <span className="font-medium text-slate-700 dark:text-slate-200">{label}</span>
                              <span className={`font-bold ${prob > 0.5 ? 'text-primary' : 'text-slate-400'}`}>
                                {(prob * 100).toFixed(1)}%
                              </span>
                            </div>
                            <div className="h-2 w-full bg-slate-100 dark:bg-slate-800 rounded-full overflow-hidden">
                              <div 
                                className={`h-full rounded-full transition-all ${
                                  label === 'Normal' ? 'bg-green-500' : 'bg-red-500'
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
                      <div className="bg-gradient-to-br from-purple-50 to-violet-50 dark:from-purple-900/20 dark:to-violet-900/10 border border-purple-100 dark:border-purple-800/30 rounded-xl p-5 shadow-sm">
                        <div className="flex items-start gap-3">
                          <div className="mt-0.5 bg-purple-100 dark:bg-purple-900/50 rounded-full p-1 text-purple-600 dark:text-purple-400">
                            <span className="material-symbols-outlined !text-[20px]">description</span>
                          </div>
                          <div>
                            <h4 className="text-purple-800 dark:text-purple-300 font-bold text-sm mb-1">Prescription Document</h4>
                            <p className="text-purple-700/80 dark:text-purple-400/80 text-sm leading-relaxed">
                              {analysis.nlp.summary}
                            </p>
                          </div>
                        </div>
                      </div>
                    )}
                  </>
                )}

                {/* Divider */}
                <div className="h-px bg-slate-100 dark:bg-slate-800 my-2"></div>

                {/* Prescription Details (from NLP) - Only for prescriptions */}
                {analysis.documentType === 'prescription' && analysis.nlp.prescriptions?.length > 0 && (
                  <div className="flex flex-col gap-3">
                    <h4 className="text-sm font-bold text-slate-900 dark:text-white uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-purple-600 !text-[18px]">medication</span>
                      Prescription Details
                    </h4>
                    {analysis.nlp.prescriptions.map((rx, index) => (
                      <div key={index} className="p-3 bg-purple-50 dark:bg-purple-900/20 rounded-lg border border-purple-100 dark:border-purple-800">
                        <p className="text-sm font-bold text-purple-900 dark:text-purple-300 capitalize mb-2">{rx.medication}</p>
                        <div className="grid grid-cols-2 gap-2">
                          {rx.dosage && (
                            <div>
                              <p className="text-[10px] font-bold text-slate-500 uppercase">Dosage</p>
                              <p className="text-xs font-medium text-slate-800 dark:text-slate-200">{rx.dosage}</p>
                            </div>
                          )}
                          {rx.frequency && (
                            <div>
                              <p className="text-[10px] font-bold text-slate-500 uppercase">Frequency</p>
                              <p className="text-xs font-medium text-slate-800 dark:text-slate-200 capitalize">{rx.frequency}</p>
                            </div>
                          )}
                          {rx.route && (
                            <div>
                              <p className="text-[10px] font-bold text-slate-500 uppercase">Route</p>
                              <p className="text-xs font-medium text-slate-800 dark:text-slate-200 capitalize">{rx.route}</p>
                            </div>
                          )}
                          {rx.duration && (
                            <div>
                              <p className="text-[10px] font-bold text-slate-500 uppercase">Duration</p>
                              <p className="text-xs font-medium text-slate-800 dark:text-slate-200 capitalize">{rx.duration}</p>
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
                    <h4 className="text-sm font-bold text-slate-900 dark:text-white uppercase tracking-wider flex items-center gap-2">
                      <span className="material-symbols-outlined text-primary !text-[18px]">label</span>
                      Entities Detected
                    </h4>
                    <div className="flex flex-wrap gap-1.5">
                      {analysis.nlp.entities.slice(0, 12).map((entity, index) => (
                        <span key={index} className={`inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs font-medium border ${
                          entity.label === 'MEDICATION' ? 'bg-purple-50 text-purple-800 border-purple-200 dark:bg-purple-900/20 dark:text-purple-300 dark:border-purple-800' :
                          entity.label === 'DOSAGE' ? 'bg-blue-50 text-blue-800 border-blue-200 dark:bg-blue-900/20 dark:text-blue-300 dark:border-blue-800' :
                          entity.label === 'FREQUENCY' ? 'bg-green-50 text-green-800 border-green-200 dark:bg-green-900/20 dark:text-green-300 dark:border-green-800' :
                          entity.label === 'ROUTE' ? 'bg-orange-50 text-orange-800 border-orange-200 dark:bg-orange-900/20 dark:text-orange-300 dark:border-orange-800' :
                          entity.label === 'DURATION' ? 'bg-cyan-50 text-cyan-800 border-cyan-200 dark:bg-cyan-900/20 dark:text-cyan-300 dark:border-cyan-800' :
                          'bg-slate-50 text-slate-700 border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700'
                        }`}>
                          <span>{entity.text}</span>
                          <span className="text-[9px] opacity-60">({entity.label})</span>
                        </span>
                      ))}
                    </div>
                  </div>
                )}

                {/* OCR Extracted Text - Only for prescriptions */}
                {analysis.documentType === 'prescription' && analysis.ocr_text && (
                  <details className="group bg-slate-50 dark:bg-slate-900 rounded-lg border border-slate-200 dark:border-slate-800 overflow-hidden">
                    <summary className="flex justify-between items-center p-3 cursor-pointer select-none">
                      <div className="flex items-center gap-2 text-sm font-semibold text-slate-700 dark:text-slate-300">
                        <span className="material-symbols-outlined !text-[18px]">text_fields</span>
                        OCR Extracted Text
                      </div>
                      <span className="material-symbols-outlined text-slate-400 group-open:rotate-180 transition-transform">expand_more</span>
                    </summary>
                    <div className="p-3 pt-0 border-t border-slate-200 dark:border-slate-800 overflow-x-auto">
                      <pre className="text-[11px] font-mono leading-relaxed text-slate-600 dark:text-slate-400 whitespace-pre-wrap">
                        {analysis.ocr_text}
                      </pre>
                    </div>
                  </details>
                )}

                {/* Raw JSON Toggle */}
                <details className="group bg-slate-50 dark:bg-slate-900 rounded-lg border border-slate-200 dark:border-slate-800 overflow-hidden">
                  <summary className="flex justify-between items-center p-3 cursor-pointer select-none">
                    <div className="flex items-center gap-2 text-sm font-semibold text-slate-700 dark:text-slate-300">
                      <span className="material-symbols-outlined !text-[18px]">data_object</span>
                      Raw API Response
                    </div>
                    <span className="material-symbols-outlined text-slate-400 group-open:rotate-180 transition-transform">expand_more</span>
                  </summary>
                  <div className="p-3 pt-0 border-t border-slate-200 dark:border-slate-800 overflow-x-auto">
                    <pre className="text-[10px] font-mono leading-tight text-slate-600 dark:text-slate-400">
                      {JSON.stringify(document.ai_analysis, null, 2)}
                    </pre>
                  </div>
                </details>
              </>
            )}

            {/* Actions */}
            {user && user.role === 'doctor' && (
              <div className="mt-auto pt-6 flex flex-col gap-3">
                <button 
                  onClick={handleVerifyDocument}
                  className="w-full h-11 bg-primary hover:bg-blue-700 text-white font-bold rounded-lg shadow-md shadow-primary/20 transition-all flex items-center justify-center gap-2"
                >
                  <span className="material-symbols-outlined !text-[20px]">verified</span>
                  Verify &amp; Sign Off
                </button>
                <button 
                  onClick={() => setShowNoteModal(true)}
                  className="w-full h-11 bg-white dark:bg-transparent border border-slate-300 dark:border-slate-600 text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 font-bold rounded-lg transition-all flex items-center justify-center gap-2"
                >
                  <span className="material-symbols-outlined !text-[20px]">edit_note</span>
                  Add Clinical Note
                </button>
              </div>
            )}
          </div>

          {/* Disclaimer Footer */}
          <div className="bg-slate-50 dark:bg-[#121721] p-4 text-center border-t border-slate-200 dark:border-slate-800 mt-auto">
            <p className="text-[10px] text-slate-400 leading-snug">
              <span className="font-bold">Disclaimer:</span> AI results are assistive only and must be verified by a certified medical professional before diagnosis.
            </p>
          </div>
        </aside>
      </div>

      {/* Clinical Note Modal */}
      {showNoteModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-slate-800 rounded-xl max-w-md w-full p-6 shadow-2xl">
            <h3 className="text-xl font-bold text-slate-900 dark:text-white mb-4">Add Clinical Note</h3>
            <textarea
              value={clinicalNote}
              onChange={(e) => setClinicalNote(e.target.value)}
              className="w-full h-32 p-3 border border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-900 text-slate-900 dark:text-white resize-none focus:ring-2 focus:ring-primary focus:border-transparent"
              placeholder="Enter your clinical observations and notes..."
            />
            <div className="flex gap-3 mt-4">
              <button
                onClick={handleAddNote}
                className="flex-1 px-4 py-2 bg-primary text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
              >
                Save Note
              </button>
              <button
                onClick={() => {
                  setShowNoteModal(false);
                  setClinicalNote('');
                }}
                className="flex-1 px-4 py-2 bg-slate-200 dark:bg-slate-700 text-slate-700 dark:text-slate-300 rounded-lg hover:bg-slate-300 dark:hover:bg-slate-600 font-medium transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* History Modal */}
      {showHistoryModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-slate-800 rounded-xl max-w-2xl w-full max-h-[80vh] overflow-hidden shadow-2xl flex flex-col">
            <div className="p-6 border-b border-gray-200 dark:border-gray-700 flex justify-between items-center">
              <h3 className="text-xl font-bold text-slate-900 dark:text-white">Document History</h3>
              <button 
                onClick={() => setShowHistoryModal(false)}
                className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
              >
                <span className="material-symbols-outlined">close</span>
              </button>
            </div>
            
            <div className="p-6 overflow-y-auto flex-1">
              {/* Upload Info */}
              <div className="mb-6">
                <h4 className="text-sm font-bold text-slate-900 dark:text-white mb-3 flex items-center gap-2">
                  <span className="material-symbols-outlined text-primary">upload</span>
                  Upload Information
                </h4>
                <div className="bg-slate-50 dark:bg-slate-900 rounded-lg p-4">
                  <p className="text-sm text-slate-700 dark:text-slate-300">
                    <span className="font-medium">Uploaded:</span> {document.timestamp}
                  </p>
                  <p className="text-sm text-slate-700 dark:text-slate-300 mt-1">
                    <span className="font-medium">Patient:</span> {document.patient.name}
                  </p>
                </div>
              </div>

              {/* Verification Status */}
              <div className="mb-6">
                <h4 className="text-sm font-bold text-slate-900 dark:text-white mb-3 flex items-center gap-2">
                  <span className="material-symbols-outlined text-green-600">verified</span>
                  Verification Status
                </h4>
                <div className="bg-slate-50 dark:bg-slate-900 rounded-lg p-4">
                  <p className="text-sm text-slate-500 dark:text-slate-400">
                    No verification records yet. Awaiting doctor review.
                  </p>
                </div>
              </div>

              {/* Clinical Notes */}
              <div>
                <h4 className="text-sm font-bold text-slate-900 dark:text-white mb-3 flex items-center gap-2">
                  <span className="material-symbols-outlined text-blue-600">edit_note</span>
                  Clinical Notes
                </h4>
                <div className="bg-slate-50 dark:bg-slate-900 rounded-lg p-4">
                  <p className="text-sm text-slate-500 dark:text-slate-400">
                    No clinical notes added yet.
                  </p>
                </div>
              </div>
            </div>
            
            <div className="p-4 border-t border-gray-200 dark:border-gray-700">
              <button
                onClick={() => setShowHistoryModal(false)}
                className="w-full px-4 py-2 bg-slate-200 dark:bg-slate-700 text-slate-700 dark:text-slate-300 rounded-lg hover:bg-slate-300 dark:hover:bg-slate-600 font-medium transition-colors"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Share Modal */}
      {showShareModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white dark:bg-slate-800 rounded-xl max-w-md w-full p-6 shadow-2xl">
            <h3 className="text-xl font-bold text-slate-900 dark:text-white mb-4">Share Document</h3>
            <p className="text-sm text-slate-600 dark:text-slate-400 mb-4">
              {user?.role === 'patient' 
                ? 'This document can be shared with your linked doctors via the dashboard.'
                : 'Document sharing is managed by the patient.'}
            </p>
            <button
              onClick={() => setShowShareModal(false)}
              className="w-full px-4 py-2 bg-primary text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
            >
              Got it
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default MedicalDocumentViewer;
