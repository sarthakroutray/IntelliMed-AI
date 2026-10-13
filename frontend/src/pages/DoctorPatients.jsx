import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext.jsx';
import { useNavigate } from 'react-router-dom';
import api from '../services/api.js';
import Icon from '../components/Icon.jsx';
import { ui } from '../styles/ui.js';
import { Alert, Modal, Spinner, EmptyState } from '../components/ui.jsx';

const DoctorPatients = () => {
    const { user } = useAuth();
    const navigate = useNavigate();
    const [patients, setPatients] = useState([]);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');
    const [currentPage, setCurrentPage] = useState(1);
    const [selectedPatient, setSelectedPatient] = useState(null);
    const [patientDocuments, setPatientDocuments] = useState([]);
    const [loadingDocs, setLoadingDocs] = useState(false);
    const itemsPerPage = 4;

    const handleViewPatientDocuments = async (patient) => {
        setSelectedPatient(patient);
        setLoadingDocs(true);
        try {
            const response = await api.get(`/doctor/patients/${patient.id}/documents`);
            setPatientDocuments(response.data);
        } catch (err) {
            setError(`Failed to fetch documents for ${patient.email}`);
            console.error(err);
        } finally {
            setLoadingDocs(false);
        }
    };

    const fetchPatients = useCallback(async () => {
        try {
            setLoading(true);
            const response = await api.get('/doctor/patients');
            const patientsData = response.data;
            
            // Fetch document count for each patient
            const patientsWithCounts = await Promise.all(
                patientsData.map(async (patient) => {
                    try {
                        const docsResponse = await api.get(`/doctor/patients/${patient.id}/documents`);
                        return { ...patient, document_count: docsResponse.data.length };
                    } catch {
                        return { ...patient, document_count: 0 };
                    }
                })
            );
            
            setPatients(patientsWithCounts);
        } catch (err) {
            setError('Failed to fetch patients.');
            console.error(err);
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchPatients();
    }, [fetchPatients]);

    const filteredPatients = patients.filter(patient => 
        patient.email?.toLowerCase().includes(searchQuery.toLowerCase()) ||
        patient.id?.toString().includes(searchQuery)
    );

    const totalPages = Math.ceil(filteredPatients.length / itemsPerPage);
    const paginatedPatients = filteredPatients.slice(
        (currentPage - 1) * itemsPerPage,
        currentPage * itemsPerPage
    );

    const getInitials = (email) => {
        return email?.charAt(0).toUpperCase() || '?';
    };

    const getAvatarColor = (index) => {
        const colors = [
            'bg-primary/10 text-primary',
            'bg-info/10 text-info',
            'bg-success/10 text-success',
            'bg-warning/10 text-warning',
        ];
        return colors[index % colors.length];
    };

    return (
        <div className={`${ui.page} overflow-y-auto`}>
            {/* Page Header & Actions */}
            <div className={ui.pageHeader}>
                <div className="flex flex-col gap-1">
                    <h1 className={ui.pageTitle}>Patient List</h1>
                    <p className={ui.pageSubtitle}>Manage your patient records and documents.</p>
                </div>
            </div>

            {error && <Alert type="error">{error}</Alert>}

            {/* Filters / Toolbar */}
            <div className="flex flex-col sm:flex-row gap-4">
                <div className="relative flex-1 max-w-md">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                        <Icon name="search" className="text-muted text-[20px]" />
                    </div>
                    <input aria-label="Search patients"
                        className={ui.inputIcon}
                        placeholder="Search by name, ID or email..."
                        type="text"
                        value={searchQuery}
                        onChange={(e) => setSearchQuery(e.target.value)}
                    />
                </div>
                <div className="flex items-center gap-2">
                    <button type="button" className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}>
                        <Icon name="filter_list" className="text-[20px]" />
                        Filter
                    </button>
                    <button type="button" className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}>
                        <Icon name="sort" className="text-[20px]" />
                        Sort
                    </button>
                </div>
            </div>

            {/* Table Card */}
            <div className={`${ui.card} overflow-hidden flex flex-col`}>
                {loading ? (
                    <div className="flex items-center justify-center py-20">
                        <Spinner className="size-12" />
                    </div>
                ) : (
                    <>
                        <div className="overflow-x-auto">
                            <table className={ui.table}>
                                <thead>
                                    <tr className="border-b border-line bg-surface-2/50">
                                        <th className={`${ui.th} w-[280px]`}>Patient Name</th>
                                        <th className={ui.th}>Patient ID / Contact</th>
                                        <th className={ui.th}>Last Visit</th>
                                        <th className={ui.th}>Documents</th>
                                        <th className={`${ui.th} text-right`}>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {paginatedPatients.length > 0 ? paginatedPatients.map((patient, index) => (
                                        <tr key={patient.id} onClick={() => handleViewPatientDocuments(patient)} className={`${ui.tr} cursor-pointer`}>
                                            <td className={ui.td}>
                                                <div className="flex items-center gap-3">
                                                    <div className={`flex items-center justify-center size-10 rounded-full ${getAvatarColor(index)} font-bold text-sm`}>
                                                        {getInitials(patient.email)}
                                                    </div>
                                                    <div className="flex flex-col">
                                                        <span className="text-sm font-bold text-ink">{patient.email?.split('@')[0]}</span>
                                                        <span className="text-xs text-muted">Patient</span>
                                                    </div>
                                                </div>
                                            </td>
                                            <td className={ui.td}>
                                                <div className="flex flex-col">
                                                    <span className="text-sm font-medium text-ink">ID: #{patient.id}</span>
                                                    <span className="text-xs text-muted">{patient.email}</span>
                                                </div>
                                            </td>
                                            <td className={ui.td}>
                                                <span className="text-sm text-body">
                                                    {patient.created_at ? new Date(patient.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                                                </span>
                                            </td>
                                            <td className={ui.td}>
                                                <div className={`${ui.badge} ${ui.badgeNeutral}`}>
                                                    <Icon name="description" className="text-[14px]" />
                                                    {patient.document_count || 0}
                                                </div>
                                            </td>
                                            <td className={`${ui.td} text-right`}>
                                                <button type="button" className="size-8 rounded hover:bg-surface-2 text-muted transition-colors">
                                                    <Icon name="more_vert" className="text-[20px]" />
                                                </button>
                                            </td>
                                        </tr>
                                    )) : (
                                        <tr>
                                            <td colSpan="5">
                                                <EmptyState icon="person_off" title="No patients found" />
                                            </td>
                                        </tr>
                                    )}
                                </tbody>
                            </table>
                        </div>
                        
                        {/* Pagination */}
                        {filteredPatients.length > 0 && (
                            <div className="p-4 border-t border-line flex items-center justify-between">
                                <span className="text-sm text-muted">
                                    Showing {(currentPage - 1) * itemsPerPage + 1} to {Math.min(currentPage * itemsPerPage, filteredPatients.length)} of {filteredPatients.length} entries
                                </span>
                                <div className="flex items-center gap-2">
                                    <button type="button" 
                                        onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                                        disabled={currentPage === 1}
                                        className="size-8 flex items-center justify-center rounded-lg border border-line text-muted hover:bg-surface-2 transition-colors disabled:opacity-50"
                                    >
                                        <Icon name="chevron_left" className="text-[18px]" />
                                    </button>
                                    {[...Array(Math.min(totalPages, 3))].map((_, i) => (
                                        <button type="button" 
                                            key={i + 1}
                                            onClick={() => setCurrentPage(i + 1)}
                                            className={`size-8 flex items-center justify-center rounded-lg font-bold text-sm transition-colors ${
                                                currentPage === i + 1
                                                    ? 'bg-primary text-white'
                                                    : 'border border-line text-muted hover:bg-surface-2'
                                            }`}
                                        >
                                            {i + 1}
                                        </button>
                                    ))}
                                    {totalPages > 3 && <span className="text-muted">...</span>}
                                    <button type="button" 
                                        onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                                        disabled={currentPage === totalPages}
                                        className="size-8 flex items-center justify-center rounded-lg border border-line text-muted hover:bg-surface-2 transition-colors disabled:opacity-50"
                                    >
                                        <Icon name="chevron_right" className="text-[18px]" />
                                    </button>
                                </div>
                            </div>
                        )}
                    </>
                )}
            </div>

            {/* Patient Documents Modal */}
            <Modal
                open={!!selectedPatient}
                onClose={() => setSelectedPatient(null)}
                title={`${selectedPatient?.email?.split('@')[0]}'s Documents`}
                maxWidth="max-w-3xl"
            >
                <p className="text-muted text-sm mb-4">{selectedPatient?.email}</p>
                <div className="max-h-[60vh] overflow-y-auto">
                    {loadingDocs ? (
                        <div className="flex items-center justify-center py-12">
                            <Spinner className="size-12" />
                        </div>
                    ) : patientDocuments.length > 0 ? (
                        <div className="space-y-4">
                            {patientDocuments.map((doc) => (
                                <div key={doc.id} className="p-4 rounded-lg border border-line hover:border-primary transition-colors">
                                    <div className="flex items-start justify-between gap-4">
                                        <div className="flex items-start gap-3 flex-1">
                                            <div className="size-10 rounded bg-primary/10 flex items-center justify-center text-primary shrink-0">
                                                <Icon name="description" className="text-[20px]" />
                                            </div>
                                            <div className="flex-1 min-w-0">
                                                <h4 className="text-sm font-bold text-ink truncate">{doc.filename}</h4>
                                                <p className="text-xs text-muted mt-1">
                                                    Uploaded: {doc.upload_timestamp ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                                                </p>
                                                {doc.ai_analysis && (
                                                    <div className="mt-2 text-xs text-success flex items-center gap-1">
                                                        <Icon name="check_circle" className="text-[14px]" />
                                                        <span>AI Analysis Complete</span>
                                                    </div>
                                                )}
                                            </div>
                                        </div>
                                        <button type="button" 
                                            onClick={() => navigate(`/document/${doc.id}`)}
                                            className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                                        >
                                            <Icon name="visibility" className="text-[16px]" />
                                            View
                                        </button>
                                    </div>
                                </div>
                            ))}
                        </div>
                    ) : (
                        <EmptyState icon="folder_off" title="No documents uploaded yet" />
                    )}
                </div>
            </Modal>
        </div>
    );
};

export default DoctorPatients;