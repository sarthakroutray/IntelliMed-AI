import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext.jsx';
import { useNavigate } from 'react-router-dom';
import api from '../services/api.js';
import Icon from '../components/Icon.jsx';

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
            'bg-blue-100 text-primary dark:bg-primary/20',
            'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300',
            'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300',
            'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300',
        ];
        return colors[index % colors.length];
    };

    return (
        <div className="flex-1 overflow-y-auto p-4 md:p-8">
            <div className="max-w-[1200px] mx-auto flex flex-col gap-6">
                {/* Page Header & Actions */}
                <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
                    <div className="flex flex-col gap-1">
                        <h1 className="text-[#111318] dark:text-white text-3xl font-black leading-tight tracking-[-0.033em]">Patient List</h1>
                        <p className="text-[#637588] dark:text-gray-400 text-sm">Manage your patient records and documents.</p>
                    </div>
                </div>

                {error && (
                    <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-300 px-4 py-3 rounded-lg">
                        {error}
                    </div>
                )}

                {/* Filters / Toolbar */}
                <div className="flex flex-col sm:flex-row gap-4">
                    <div className="relative flex-1 max-w-md">
                        <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <Icon name="search" className="text-[#637588] text-[20px]" />
                        </div>
                        <input 
                            className="block w-full pl-10 pr-3 py-2.5 rounded-lg border-none bg-white dark:bg-[#1a202c] text-[#111318] dark:text-white placeholder-[#637588] focus:ring-2 focus:ring-primary shadow-sm text-sm"
                            placeholder="Search by name, ID or email..."
                            type="text"
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                        />
                    </div>
                    <div className="flex items-center gap-2">
                        <button className="flex items-center gap-2 h-[42px] px-3 bg-white dark:bg-[#1a202c] rounded-lg text-[#637588] dark:text-gray-300 font-medium text-sm shadow-sm hover:text-primary transition-colors">
                            <Icon name="filter_list" className="text-[20px]" />
                            Filter
                        </button>
                        <button className="flex items-center gap-2 h-[42px] px-3 bg-white dark:bg-[#1a202c] rounded-lg text-[#637588] dark:text-gray-300 font-medium text-sm shadow-sm hover:text-primary transition-colors">
                            <Icon name="sort" className="text-[20px]" />
                            Sort
                        </button>
                    </div>
                </div>

                {/* Table Card */}
                <div className="bg-white dark:bg-[#1a202c] rounded-xl shadow-sm border border-[#e5e7eb] dark:border-gray-800 overflow-hidden flex flex-col">
                    {loading ? (
                        <div className="flex items-center justify-center py-20">
                            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
                        </div>
                    ) : (
                        <>
                            <div className="overflow-x-auto">
                                <table className="w-full text-left border-collapse">
                                    <thead>
                                        <tr className="bg-[#f8fafc] dark:bg-[#1e2532] border-b border-[#e5e7eb] dark:border-gray-800">
                                            <th className="py-3 px-4 text-xs font-bold text-[#637588] dark:text-gray-400 uppercase tracking-wider w-[280px]">Patient Name</th>
                                            <th className="py-3 px-4 text-xs font-bold text-[#637588] dark:text-gray-400 uppercase tracking-wider">Patient ID / Contact</th>
                                            <th className="py-3 px-4 text-xs font-bold text-[#637588] dark:text-gray-400 uppercase tracking-wider">Last Visit</th>
                                            <th className="py-3 px-4 text-xs font-bold text-[#637588] dark:text-gray-400 uppercase tracking-wider">Documents</th>
                                            <th className="py-3 px-4 text-xs font-bold text-[#637588] dark:text-gray-400 uppercase tracking-wider text-right">Actions</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-[#e5e7eb] dark:divide-gray-800">
                                        {paginatedPatients.length > 0 ? paginatedPatients.map((patient, index) => (
                                            <tr key={patient.id} onClick={() => handleViewPatientDocuments(patient)} className="group hover:bg-[#f0f2f4] dark:hover:bg-gray-800/50 transition-colors cursor-pointer">
                                                <td className="py-3 px-4">
                                                    <div className="flex items-center gap-3">
                                                        <div className={`flex items-center justify-center size-10 rounded-full ${getAvatarColor(index)} font-bold text-sm`}>
                                                            {getInitials(patient.email)}
                                                        </div>
                                                        <div className="flex flex-col">
                                                            <span className="text-sm font-bold text-[#111318] dark:text-white">{patient.email?.split('@')[0]}</span>
                                                            <span className="text-xs text-[#637588] dark:text-gray-400">Patient</span>
                                                        </div>
                                                    </div>
                                                </td>
                                                <td className="py-3 px-4 align-middle">
                                                    <div className="flex flex-col">
                                                        <span className="text-sm font-medium text-[#111318] dark:text-gray-200">ID: #{patient.id}</span>
                                                        <span className="text-xs text-[#637588] dark:text-gray-500">{patient.email}</span>
                                                    </div>
                                                </td>
                                                <td className="py-3 px-4 align-middle">
                                                    <span className="text-sm text-[#111318] dark:text-gray-200">
                                                        {patient.created_at ? new Date(patient.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                                                    </span>
                                                </td>
                                                <td className="py-3 px-4 align-middle">
                                                    <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-[#f0f2f4] dark:bg-gray-700 text-xs font-bold text-[#637588] dark:text-gray-300">
                                                        <Icon name="description" className="text-[14px]" />
                                                        {patient.document_count || 0}
                                                    </div>
                                                </td>
                                                <td className="py-3 px-4 align-middle text-right">
                                                    <button className="size-8 rounded hover:bg-white dark:hover:bg-gray-600 text-[#637588] dark:text-gray-400 transition-colors">
                                                        <Icon name="more_vert" className="text-[20px]" />
                                                    </button>
                                                </td>
                                            </tr>
                                        )) : (
                                            <tr>
                                                <td colSpan="5" className="py-12 text-center">
                                                    <div className="flex flex-col items-center gap-3">
                                                        <Icon name="person_off" className="text-[48px] text-gray-300 dark:text-gray-600" />
                                                        <p className="text-[#637588] dark:text-gray-400">No patients found</p>
                                                    </div>
                                                </td>
                                            </tr>
                                        )}
                                    </tbody>
                                </table>
                            </div>
                            
                            {/* Pagination */}
                            {filteredPatients.length > 0 && (
                                <div className="p-4 border-t border-[#e5e7eb] dark:border-gray-800 flex items-center justify-between">
                                    <span className="text-sm text-[#637588] dark:text-gray-400">
                                        Showing {(currentPage - 1) * itemsPerPage + 1} to {Math.min(currentPage * itemsPerPage, filteredPatients.length)} of {filteredPatients.length} entries
                                    </span>
                                    <div className="flex items-center gap-2">
                                        <button 
                                            onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                                            disabled={currentPage === 1}
                                            className="size-8 flex items-center justify-center rounded-lg border border-[#e5e7eb] dark:border-gray-700 text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors disabled:opacity-50"
                                        >
                                            <Icon name="chevron_left" className="text-[18px]" />
                                        </button>
                                        {[...Array(Math.min(totalPages, 3))].map((_, i) => (
                                            <button 
                                                key={i + 1}
                                                onClick={() => setCurrentPage(i + 1)}
                                                className={`size-8 flex items-center justify-center rounded-lg font-bold text-sm transition-colors ${
                                                    currentPage === i + 1
                                                        ? 'bg-primary text-white'
                                                        : 'border border-[#e5e7eb] dark:border-gray-700 text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800'
                                                }`}
                                            >
                                                {i + 1}
                                            </button>
                                        ))}
                                        {totalPages > 3 && <span className="text-[#637588] dark:text-gray-400">...</span>}
                                        <button 
                                            onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                                            disabled={currentPage === totalPages}
                                            className="size-8 flex items-center justify-center rounded-lg border border-[#e5e7eb] dark:border-gray-700 text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors disabled:opacity-50"
                                        >
                                            <Icon name="chevron_right" className="text-[18px]" />
                                        </button>
                                    </div>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>

            {/* Patient Documents Modal */}
            {selectedPatient && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setSelectedPatient(null)}>
                    <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-3xl w-full max-h-[80vh] overflow-hidden flex flex-col" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
                            <div>
                                <h3 className="text-xl font-bold text-[#111318] dark:text-white">{selectedPatient.email?.split('@')[0]}'s Documents</h3>
                                <p className="text-sm text-[#637588] dark:text-gray-400 mt-1">{selectedPatient.email}</p>
                            </div>
                            <button onClick={() => setSelectedPatient(null)} className="text-gray-400 hover:text-gray-600">
                                <Icon name="close" className="text-[24px]" />
                            </button>
                        </div>
                        <div className="flex-1 overflow-y-auto p-6">
                            {loadingDocs ? (
                                <div className="flex items-center justify-center py-12">
                                    <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
                                </div>
                            ) : patientDocuments.length > 0 ? (
                                <div className="space-y-4">
                                    {patientDocuments.map((doc) => (
                                        <div key={doc.id} className="p-4 rounded-lg border border-gray-200 dark:border-gray-700 hover:border-primary dark:hover:border-primary transition-colors">
                                            <div className="flex items-start justify-between gap-4">
                                                <div className="flex items-start gap-3 flex-1">
                                                    <div className="size-10 rounded bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-blue-600 dark:text-blue-400 flex-shrink-0">
                                                        <Icon name="description" className="text-[20px]" />
                                                    </div>
                                                    <div className="flex-1 min-w-0">
                                                        <h4 className="text-sm font-bold text-[#111318] dark:text-white truncate">{doc.filename}</h4>
                                                        <p className="text-xs text-[#637588] dark:text-gray-400 mt-1">
                                                            Uploaded: {doc.upload_timestamp ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'N/A'}
                                                        </p>
                                                        {doc.ai_analysis && (
                                                            <div className="mt-2 text-xs text-green-600 dark:text-green-400 flex items-center gap-1">
                                                                <Icon name="check_circle" className="text-[14px]" />
                                                                <span>AI Analysis Complete</span>
                                                            </div>
                                                        )}
                                                    </div>
                                                </div>
                                                <button 
                                                    onClick={() => navigate(`/document/${doc.id}`)}
                                                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary/10 hover:bg-primary/20 text-primary text-xs font-bold transition-colors"
                                                >
                                                    <Icon name="visibility" className="text-[16px]" />
                                                    View
                                                </button>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            ) : (
                                <div className="flex flex-col items-center justify-center py-12">
                                    <Icon name="folder_off" className="text-[64px] text-gray-300 dark:text-gray-600" />
                                    <p className="text-[#637588] dark:text-gray-400 mt-4">No documents uploaded yet</p>
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
};

export default DoctorPatients;
