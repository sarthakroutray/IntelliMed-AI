import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api from '../services/api';
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
          
          const allDocs = [];
          for (const patient of patients) {
            try {
              const docsResponse = await api.get(`/doctor/patients/${patient.id}/documents`);
              const docs = docsResponse.data.map(doc => ({
                ...doc,
                patientName: patient.email?.split('@')[0],
                patientEmail: patient.email
              }));
              allDocs.push(...docs);
            } catch (err) {
              console.error(`Failed to fetch documents for patient ${patient.id}`, err);
            }
          }
          setDocuments(allDocs);
        } else {
          // Patient view
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
      // Trigger AI analysis (simulated - replace with actual API call when ML is ready)
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Mock AI analysis result
      const mockAnalysis = {
        summary: "Medical document analysis completed. Key findings extracted.",
        entities: [
          { text: "Diagnosis", label: "MEDICAL_CONDITION", confidence: 0.95 },
          { text: "Treatment Plan", label: "PROCEDURE", confidence: 0.89 }
        ],
        recommendations: [
          "Follow up appointment recommended in 2 weeks",
          "Monitor vital signs daily"
        ]
      };
      
      // Update local state
      setDocuments(docs => 
        docs.map(doc => 
          doc.id === docId 
            ? { ...doc, ai_analysis: JSON.stringify(mockAnalysis) } 
            : doc
        )
      );
      
    } catch (err) {
      console.error('AI analysis failed', err);
      alert('AI analysis failed. Please try again.');
    } finally {
      setAnalyzing(null);
    }
  };

  const parseAIAnalysis = (analysisString) => {
    try {
      return JSON.parse(analysisString);
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
                    <button
                      key={doc.id}
                      onClick={() => setSelectedDoc(doc)}
                      className={`w-full p-4 text-left hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors ${
                        selectedDoc?.id === doc.id ? 'bg-primary/10 dark:bg-primary/20' : ''
                      }`}
                    >
                      <p className="text-sm font-bold text-gray-900 dark:text-white truncate">{doc.filename}</p>
                      {user.role === 'doctor' && (
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Patient: {doc.patientName}</p>
                      )}
                      <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                        {new Date(doc.upload_timestamp).toLocaleDateString()}
                      </p>
                    </button>
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

                      return (
                        <>
                          {/* Summary */}
                          <div>
                            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                              <Icon name="summarize" className="text-primary" />
                              Summary
                            </h3>
                            <p className="text-gray-700 dark:text-gray-300 leading-relaxed p-4 bg-gray-50 dark:bg-gray-800/50 rounded-lg">
                              {analysis.summary}
                            </p>
                          </div>

                          {/* Entities */}
                          {analysis.entities && analysis.entities.length > 0 && (
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
