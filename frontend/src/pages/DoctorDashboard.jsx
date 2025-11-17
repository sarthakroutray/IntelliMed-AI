import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext.jsx';
import api from '../services/api.js';
import '../styles/DoctorDashboard.css';
import LinkPatient from '../components/LinkPatient.jsx';

const DoctorDashboard = () => {
    const { token, user } = useAuth();
    const [patients, setPatients] = useState([]);
    const [selectedPatient, setSelectedPatient] = useState(null);
    const [documents, setDocuments] = useState([]);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(true);

    const fetchPatients = useCallback(async () => {
        try {
            setLoading(true);
            const response = await api.get('/doctor/patients');
            setPatients(response.data);
        } catch (err) {
            setError('Failed to fetch patients.');
            console.error(err);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        if (token) {
            fetchPatients();
        }
    }, [token, fetchPatients]);

    const handlePatientSelect = async (patient) => {
        setSelectedPatient(patient);
        try {
            const response = await api.get(`/doctor/patients/${patient.id}/documents`);
            setDocuments(response.data);
        } catch (err) {
            setError(`Failed to fetch documents for ${patient.email}.`);
            console.error(err);
        }
    };

    return (
        <div className="doctor-dashboard-container">
            <header className="dashboard-header">
                <div className="header-content">
                    <div>
                        <h1>{user?.role === 'admin' ? 'Admin' : 'Doctor'} Dashboard</h1>
                        <p>Review and manage your patients' medical documents</p>
                    </div>
                    <div className="stats-container">
                        <div className="stat-card">
                            <div className="stat-icon">Patients</div>
                            <div className="stat-info">
                                <div className="stat-value">{patients.length}</div>
                                <div className="stat-label">Total Patients</div>
                            </div>
                        </div>
                        <div className="stat-card">
                            <div className="stat-icon">Docs</div>
                            <div className="stat-info">
                                <div className="stat-value">{documents.length}</div>
                                <div className="stat-label">Documents</div>
                            </div>
                        </div>
                    </div>
                </div>
            </header>
            
            {error && (
                <div className="error-message">
                    <span className="error-icon"></span>
                    {error}
                </div>
            )}

            <div className="dashboard-main-content">
                <div className="patients-list-container">
                    <div className="section-header">
                        <h2>Your Patients</h2>
                        <span className="patient-count">{patients.length} patient{patients.length !== 1 ? 's' : ''}</span>
                    </div>
                    <LinkPatient onPatientLinked={fetchPatients} />
                    {loading ? (
                        <div className="loading-container">
                            <div className="spinner"></div>
                            <p>Loading patients...</p>
                        </div>
                    ) : patients.length > 0 ? (
                        <ul className="patients-list">
                            {patients.map((patient) => (
                                <li 
                                    key={patient.id} 
                                    className={`patient-item ${selectedPatient?.id === patient.id ? 'selected' : ''}`}
                                    onClick={() => handlePatientSelect(patient)}
                                >
                                    <div className="patient-avatar">
                                        {patient.email.charAt(0).toUpperCase()}
                                    </div>
                                    <div className="patient-info">
                                        <div className="patient-email">{patient.name || patient.email}</div>
                                        <div className="patient-meta">Patient ID: {patient.id}</div>
                                    </div>
                                    {selectedPatient?.id === patient.id && <div className="selected-indicator">✓</div>}
                                </li>
                            ))}
                        </ul>
                    ) : (
                        <div className="empty-state">
                            <div className="empty-icon">—</div>
                            <p>No patients found</p>
                        </div>
                    )}
                </div>

                <div className="patient-documents-container">
                    {selectedPatient ? (
                        <>
                            <div className="section-header">
                                <h2>Medical Documents</h2>
                                <div className="patient-badge">{selectedPatient.name || selectedPatient.email}</div>
                            </div>
                            {documents.length > 0 ? (
                                <div className="documents-grid">
                                    {documents.map((doc) => (
                                        <div key={doc.id} className="document-card">
                                            <div className="document-icon">Doc</div>
                                            <div className="document-details">
                                                <a href={doc.file_url} target="_blank" rel="noopener noreferrer" className="document-name">
                                                    {doc.file_name}
                                                </a>
                                                <div className="document-meta">
                                                    <span className="upload-date">
                                                        {new Date(doc.upload_timestamp).toLocaleDateString()}
                                                    </span>
                                                    <span className={`status-badge status-${doc.analysis_status}`}>
                                                        {doc.analysis_status === 'processed' && '✓ '}
                                                        {doc.analysis_status === 'pending' && '• '}
                                                        {doc.analysis_status === 'failed' && '✗ '}
                                                        {doc.analysis_status}
                                                    </span>
                                                </div>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            ) : (
                                <div className="empty-state">
                                    <div className="empty-icon">—</div>
                                    <p>No documents found for this patient</p>
                                    <span className="empty-hint">Documents will appear here once uploaded</span>
                                </div>
                            )}
                        </>
                    ) : (
                        <div className="placeholder-content">
                            <div className="placeholder-icon">←</div>
                            <p>Select a patient to view their documents</p>
                            <span className="placeholder-hint">Click on a patient from the list</span>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
};

export default DoctorDashboard;
