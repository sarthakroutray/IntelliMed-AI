import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api, { analyzeDocument } from '../services/api';
import Icon from '../components/Icon';

const AIAnalysis = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [selectedDoc, setSelectedDoc] = useState(null);
  const [loading, setLoading] = useState(true);
  const [analyzing, setAnalyzing] = useState(null);

  useEffect(() => {
    const fetchDocumentsWithAI = async () => {
      try {
        setLoading(true);
        
        if (user.role === 'doctor') {
          const patientsResponse = await api.get('/doctor/patients');
          const patients = patientsResponse.data;
          
          // Fetch all patient documents in parallel instead of sequentially
          const docPromises = patients.map(patient =>
            api.get(`/doctor/patients/${patient.id}/documents`)
              .then(res => res.data.map(doc => ({
                ...doc,
                patientName: patient.email?.split('@')[0],
                patientEmail: patient.email
              })))
              .catch(err => {
                console.error(`Failed to fetch documents for patient ${patient.id}`, err);
                return [];
              })
          );
          const results = await Promise.all(docPromises);
          setDocuments(results.flat());
        } else {
          const response = await api.get('/patient/documents');
          setDocuments(response.data);
        }
      } catch (err) {
        console.error('Failed to fetch documents', err);
      } finally {
        setLoading(false);
      }
    };

    fetchDocumentsWithAI();
  }, [user.role]);

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
            ? { ...doc, ai_analysis: JSON.stringify(structuredAnalysis) }
            : doc
        )
      );
    } catch (err) {
      console.error('AI analysis failed', err);
      alert(err.response?.data?.detail || 'AI analysis failed. Please try again.');
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
          <h1 className="text-3xl font-black text-gray-900 dark:text-white mb-2">
            AI Analysis Dashboard
          </h1>
          <p className="text-gray-500 dark:text-gray-400">
            Review AI-powered insights and recommendations from medical documents.
          </p>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left Panel - Document List */}
            <div className="lg:col-span-1 space-y-4">
              {/* Stats Card */}
              <div className="bg-gradient-to-br from-primary to-blue-600 rounded-xl p-6 text-white">
                <div className="flex items-center gap-3 mb-4">
                  <Icon name="auto_awesome" className="text-3xl" />
                  <div>
                    <p className="text-sm opacity-90">AI Analysis</p>
                    <p className="text-2xl font-black">{analyzedDocs.length}/{documents.length}</p>
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
              <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
                <div className="p-4 border-b border-gray-200 dark:border-gray-800">
                  <h3 className="font-bold text-gray-900 dark:text-white flex items-center gap-2">
                    <Icon name="check_circle" className="text-green-600 dark:text-green-400 text-[20px]" />
                    Analyzed ({analyzedDocs.length})
                  </h3>
                </div>
                <div className="max-h-[400px] overflow-y-auto divide-y divide-gray-200 dark:divide-gray-800">
                  {analyzedDocs.map((doc) => (
                    <div key={doc.id} className="relative group">
                      <button
                        onClick={() => setSelectedDoc(doc)}
                        className={`w-full p-4 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors ${
                          selectedDoc?.id === doc.id ? 'bg-primary/10 dark:bg-primary/20' : ''
                        }`}
                      >
                        <p className="text-sm font-bold text-gray-900 dark:text-white truncate pr-8">{doc.filename}</p>
                        {user.role === 'doctor' && (
                          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Patient: {doc.patientName}</p>
                        )}
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                          {new Date(doc.upload_timestamp).toLocaleDateString()}
                        </p>
                      </button>
                      <button
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
                    <div className="p-8 text-center text-gray-500 dark:text-gray-400 text-sm">
                      No analyzed documents yet
                    </div>
                  )}
                </div>
              </div>

              {/* Pending Analysis */}
              {pendingDocs.length > 0 && (
                <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
                  <div className="p-4 border-b border-gray-200 dark:border-gray-800">
                    <h3 className="font-bold text-gray-900 dark:text-white flex items-center gap-2">
                      <Icon name="pending" className="text-orange-600 dark:text-orange-400 text-[20px]" />
                      Pending ({pendingDocs.length})
                    </h3>
                  </div>
                  <div className="max-h-[300px] overflow-y-auto divide-y divide-gray-200 dark:divide-gray-800">
                    {pendingDocs.map((doc) => (
                      <div key={doc.id} className="p-4 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors">
                        <p className="text-sm font-bold text-gray-900 dark:text-white truncate mb-2">{doc.filename}</p>
                        {user.role === 'doctor' && (
                          <p className="text-xs text-gray-500 dark:text-gray-400 mb-2">Patient: {doc.patientName}</p>
                        )}
                        <button
                          onClick={() => handleAnalyze(doc.id)}
                          disabled={analyzing === doc.id}
                          className="w-full flex items-center justify-center gap-2 px-3 py-1.5 rounded-lg bg-primary/10 hover:bg-primary/20 text-primary text-xs font-bold transition-colors disabled:opacity-50"
                        >
                          {analyzing === doc.id ? (
                            <>
                              <div className="animate-spin rounded-full h-3 w-3 border-b-2 border-primary"></div>
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
                <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
                  {/* Document Header */}
                  <div className="p-6 border-b border-gray-200 dark:border-gray-800 bg-gradient-to-r from-gray-50 to-white dark:from-gray-900 dark:to-[#1a202c]">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1">
                        <h2 className="text-xl font-bold text-gray-900 dark:text-white mb-2">{selectedDoc.filename}</h2>
                        {user.role === 'doctor' && (
                          <p className="text-sm text-gray-600 dark:text-gray-400">
                            Patient: <span className="font-medium">{selectedDoc.patientName}</span>
                          </p>
                        )}
                        <p className="text-sm text-gray-500 dark:text-gray-500 mt-1">
                          Analyzed on {new Date(selectedDoc.upload_timestamp).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}
                        </p>
                      </div>
                      <button
                        onClick={() => navigate(`/document/${selectedDoc.id}`)}
                        className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary hover:bg-blue-700 text-white text-sm font-bold transition-colors"
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
                          <div className="text-center py-12">
                            <Icon name="error" className="text-gray-300 dark:text-gray-600 text-5xl mx-auto mb-3" />
                            <p className="text-gray-500 dark:text-gray-400">Unable to parse AI analysis</p>
                          </div>
                        );
                      }

                      const isXray = analysis.document_type === 'xray';
                      const isPrescription = analysis.document_type === 'prescription';
                      
                      return (
                        <>
                          {/* Classification Result - Only show for X-rays */}
                          {isXray && analysis.classification && (
                            <div className={`p-4 rounded-lg border ${
                              analysis.classification === 'Normal'
                                ? 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800'
                                : 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800'
                            }`}>
                              <div className="flex items-center gap-3 mb-2">
                                <Icon name={analysis.classification === 'Normal' ? 'check_circle' : 'warning'} 
                                  className={`text-2xl ${analysis.classification === 'Normal' ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`} />
                                <div>
                                  <p className={`text-lg font-black ${analysis.classification === 'Normal' ? 'text-green-900 dark:text-green-300' : 'text-red-900 dark:text-red-300'}`}>
                                    {analysis.classification}
                                  </p>
                                  <p className="text-sm text-gray-600 dark:text-gray-400">
                                    Confidence: {analysis.confidence ? `${(analysis.confidence * 100).toFixed(1)}%` : 'N/A'}
                                  </p>
                                </div>
                              </div>
                            </div>
                          )}

                          {/* Probabilities - Only show for X-rays */}
                          {isXray && analysis.probabilities && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="bar_chart" className="text-primary" />
                                Class Probabilities
                              </h3>
                              <div className="space-y-3">
                                {Object.entries(analysis.probabilities).map(([label, prob]) => (
                                  <div key={label}>
                                    <div className="flex justify-between text-sm mb-1">
                                      <span className="font-medium text-gray-700 dark:text-gray-300">{label}</span>
                                      <span className="text-gray-500 dark:text-gray-400">{(prob * 100).toFixed(1)}%</span>
                                    </div>
                                    <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2.5">
                                      <div
                                        className={`h-2.5 rounded-full transition-all duration-500 ${
                                          label === 'Normal' ? 'bg-green-500' : 'bg-red-500'
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
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="summarize" className="text-primary" />
                                Summary
                              </h3>
                              <p className="text-gray-700 dark:text-gray-300 leading-relaxed p-4 bg-gray-50 dark:bg-gray-800/50 rounded-lg">
                                {analysis.summary}
                              </p>
                            </div>
                          )}

                          {/* Medical Summary (T5-generated) */}
                          {analysis.medical_summary && analysis.medical_summary.length > 10 && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="clinical_notes" className="text-emerald-600 dark:text-emerald-400" />
                                Medical Summary
                                <span className="text-[10px] font-medium px-2 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 dark:text-emerald-300 ml-auto">AI Generated</span>
                              </h3>
                              <p className="text-gray-700 dark:text-gray-300 leading-relaxed p-4 bg-emerald-50 dark:bg-emerald-900/10 rounded-lg border border-emerald-200 dark:border-emerald-800">
                                {analysis.medical_summary}
                              </p>
                            </div>
                          )}

                          {/* Key Findings */}
                          {analysis.key_findings && analysis.key_findings.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="fact_check" className="text-amber-600 dark:text-amber-400" />
                                Key Findings
                              </h3>
                              <div className="space-y-2">
                                {analysis.key_findings.map((finding, index) => (
                                  <div key={index} className="flex items-start gap-3 p-3 bg-amber-50 dark:bg-amber-900/10 rounded-lg border border-amber-200 dark:border-amber-800">
                                    <Icon name="arrow_right" className="text-amber-600 dark:text-amber-400 text-[18px] mt-0.5 flex-shrink-0" />
                                    <p className="text-sm text-gray-700 dark:text-gray-300">{finding}</p>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Entities - Only for prescriptions */}
                          {isPrescription && analysis.entities && analysis.entities.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="label" className="text-primary" />
                                Key Entities Detected
                              </h3>
                              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                {analysis.entities.map((entity, index) => (
                                  <div key={index} className="p-4 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700">
                                    <p className="text-sm font-bold text-gray-900 dark:text-white">{entity.text}</p>
                                    <div className="flex items-center justify-between mt-2">
                                      <span className="text-xs px-2 py-1 rounded-full bg-primary/10 text-primary font-medium">
                                        {entity.label}
                                      </span>
                                      {entity.confidence && (
                                        <span className="text-xs text-gray-500 dark:text-gray-400">
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
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="lightbulb" className="text-primary" />
                                AI Recommendations
                              </h3>
                              <div className="space-y-2">
                                {analysis.recommendations.map((rec, index) => (
                                  <div key={index} className="flex items-start gap-3 p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
                                    <Icon name="check" className="text-blue-600 dark:text-blue-400 text-[18px] mt-0.5" />
                                    <p className="text-sm text-gray-700 dark:text-gray-300">{rec}</p>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Prescription Details - Only show for prescriptions */}
                          {isPrescription && analysis.prescriptions && analysis.prescriptions.length > 0 && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="medication" className="text-primary" />
                                Prescription Details
                              </h3>
                              <div className="space-y-3">
                                {analysis.prescriptions.map((rx, index) => (
                                  <div key={index} className="p-4 bg-purple-50 dark:bg-purple-900/20 rounded-lg border border-purple-200 dark:border-purple-800">
                                    <div className="flex items-center gap-2 mb-2">
                                      <Icon name="pill" className="text-purple-600 dark:text-purple-400 text-[18px]" />
                                      <p className="text-base font-bold text-purple-900 dark:text-purple-300 capitalize">
                                        {rx.medication}
                                      </p>
                                    </div>
                                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-2">
                                      {rx.dosage && (
                                        <div className="bg-white dark:bg-gray-800 rounded-md px-3 py-1.5 border border-purple-100 dark:border-purple-800">
                                          <p className="text-[10px] font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider">Dosage</p>
                                          <p className="text-sm font-bold text-gray-900 dark:text-white">{rx.dosage}</p>
                                        </div>
                                      )}
                                      {rx.frequency && (
                                        <div className="bg-white dark:bg-gray-800 rounded-md px-3 py-1.5 border border-purple-100 dark:border-purple-800">
                                          <p className="text-[10px] font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider">Frequency</p>
                                          <p className="text-sm font-bold text-gray-900 dark:text-white capitalize">{rx.frequency}</p>
                                        </div>
                                      )}
                                      {rx.route && (
                                        <div className="bg-white dark:bg-gray-800 rounded-md px-3 py-1.5 border border-purple-100 dark:border-purple-800">
                                          <p className="text-[10px] font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider">Route</p>
                                          <p className="text-sm font-bold text-gray-900 dark:text-white capitalize">{rx.route}</p>
                                        </div>
                                      )}
                                      {rx.duration && (
                                        <div className="bg-white dark:bg-gray-800 rounded-md px-3 py-1.5 border border-purple-100 dark:border-purple-800">
                                          <p className="text-[10px] font-bold text-gray-500 dark:text-gray-400 uppercase tracking-wider">Duration</p>
                                          <p className="text-sm font-bold text-gray-900 dark:text-white capitalize">{rx.duration}</p>
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
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="medication" className="text-primary" />
                                Medications Detected
                              </h3>
                              <div className="flex flex-wrap gap-2">
                                {analysis.medications.map((med, index) => (
                                  <span key={index} className="px-3 py-1.5 bg-purple-100 dark:bg-purple-900/30 text-purple-800 dark:text-purple-300 rounded-full text-sm font-bold capitalize">
                                    {med}
                                  </span>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* OCR Extracted Text - Only show for prescriptions */}
                          {isPrescription && analysis.ocr_text && (
                            <div>
                              <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                <Icon name="text_fields" className="text-primary" />
                                OCR Extracted Text
                              </h3>
                              <div className="relative">
                                <pre className="text-sm text-gray-700 dark:text-gray-300 leading-relaxed p-4 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700 whitespace-pre-wrap font-mono max-h-[300px] overflow-y-auto">
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
                <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 p-12 text-center">
                  <Icon name="analytics" className="text-gray-300 dark:text-gray-600 text-6xl mx-auto mb-4" />
                  <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">Select a document</h3>
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    Choose a document from the list to view its AI analysis
                  </p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Info Banner */}
        <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-xl p-4">
          <div className="flex items-start gap-3">
            <Icon name="info" className="text-blue-600 dark:text-blue-400 text-[24px]" />
            <div className="flex-1">
              <p className="text-sm font-bold text-blue-900 dark:text-blue-300 mb-1">AI Analysis Note</p>
              <p className="text-sm text-blue-700 dark:text-blue-400">
                AI analysis is provided for informational purposes only and should not replace professional medical judgment. 
                Always consult with a qualified healthcare provider for medical decisions.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AIAnalysis;
