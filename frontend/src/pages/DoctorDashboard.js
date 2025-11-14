import React, { useState, useEffect } from 'react';
import { getPatients, getPatientDocuments } from '../services/api';

const DoctorDashboard = () => {
  const [patients, setPatients] = useState([]);
  const [selectedPatient, setSelectedPatient] = useState(null);
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const fetchPatients = async () => {
      try {
        const response = await getPatients();
        setPatients(response.data);
      } catch (error) {
        console.error('Failed to fetch patients', error);
      }
    };
    fetchPatients();
  }, []);

  const handlePatientClick = async (patient) => {
    if (selectedPatient?.id === patient.id) return;
    setSelectedPatient(patient);
    setLoading(true);
    setDocuments([]);
    try {
      const response = await getPatientDocuments(patient.id);
      setDocuments(response.data);
    } catch (error) {
      console.error(`Failed to fetch documents for patient ${patient.id}`, error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <h1 className="text-4xl font-bold mb-8">Doctor's Clinical AI Dashboard</h1>
      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        <div className="lg:col-span-1">
          <div className="card">
            <h2 className="text-2xl font-semibold mb-4">Patient Cohort</h2>
            <ul className="space-y-2">
              {patients.map((patient) => (
                <li 
                  key={patient.id} 
                  onClick={() => handlePatientClick(patient)} 
                  className={`p-3 rounded-lg cursor-pointer transition-all duration-200 font-semibold ${selectedPatient?.id === patient.id ? 'bg-gradient-to-r from-blue-500 to-indigo-500 text-white shadow-lg' : 'hover:bg-gray-200'}`}
                >
                  {patient.email}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="lg:col-span-3">
          {selectedPatient ? (
            <div>
              <h2 className="text-3xl font-semibold mb-6">AI-Powered Analysis for: <span className="text-indigo-600">{selectedPatient.email}</span></h2>
              {loading ? (
                <div className="card text-center"><p className="font-semibold">Loading Patient Data...</p></div>
              ) : documents.length > 0 ? (
                <div className="space-y-8">
                  {documents.map((doc, index) => (
                    <div key={index} className="card">
                      <div className="flex justify-between items-start mb-4">
                        <div>
                          <h3 className="text-2xl font-bold text-gray-800">{doc.filename}</h3>
                          <p className="text-sm text-gray-500 mt-1">
                            Uploaded: {new Date(doc.upload_timestamp).toLocaleString()}
                          </p>
                        </div>
                        <span className="text-base font-semibold bg-blue-100 text-blue-800 py-1 px-4 rounded-full">
                          Analysis Complete
                        </span>
                      </div>
                      {doc.ai_analysis ? (
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 border-t pt-6 mt-4">
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <h4 className="font-bold text-xl mb-3 text-gray-700">NLP Insights</h4>
                            <p className="mb-3"><strong>Summary:</strong> {doc.ai_analysis.nlp_result?.summary}</p>
                            <strong>Key Entities:</strong>
                            <ul className="list-disc list-inside mt-2 space-y-1">
                              {doc.ai_analysis.nlp_result?.entities.map((e, i) => (
                                <li key={i}>{e.text} <span className="font-semibold text-indigo-600">({e.label})</span></li>
                              ))}
                            </ul>
                          </div>
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <h4 className="font-bold text-xl mb-3 text-gray-700">Imaging Analysis</h4>
                            <p className="text-2xl font-bold text-indigo-700">
                              {doc.ai_analysis.cv_result?.classification}
                            </p>
                            <div className="w-full bg-gray-200 rounded-full h-4 mt-2">
                              <div className="bg-green-500 h-4 rounded-full" style={{ width: `${doc.ai_analysis.cv_result?.confidence * 100}%` }}></div>
                            </div>
                            <p className="text-lg text-right font-semibold mt-1">
                              Confidence: <span className="font-bold text-green-600">{(doc.ai_analysis.cv_result?.confidence * 100).toFixed(2)}%</span>
                            </p>
                          </div>
                        </div>
                      ) : (
                        <p>No analysis available for this document.</p>
                      )}
                    </div>
                  ))}
                </div>
              ) : (
                <div className="card text-center py-16">
                  <h3 className="text-2xl font-semibold">No Documents Found</h3>
                  <p className="text-gray-500 mt-3">This patient has not uploaded any documents yet.</p>
                </div>
              )}
            </div>
          ) : (
            <div className="card text-center py-24">
              <h2 className="text-3xl font-semibold">Welcome, Doctor</h2>
              <p className="text-gray-500 mt-4 text-lg">Please select a patient from the cohort list to view their AI-driven medical insights.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default DoctorDashboard;
