import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext.jsx';
import { useNavigate } from 'react-router-dom';
import api from '../services/api.js';
import Icon from '../components/Icon.jsx';
import LinkPatient from '../components/LinkPatient.jsx';

const DoctorDashboard = () => {
    const { token, user, logout } = useAuth();
    const navigate = useNavigate();
    const [patients, setPatients] = useState([]);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');
    const [currentPage, setCurrentPage] = useState(1);
    const [showLinkModal, setShowLinkModal] = useState(false);
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
        if (token) {
            fetchPatients();
        }
    }, [token, fetchPatients]);

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
        <div className="flex h-screen w-full bg-background-light dark:bg-background-dark font-display">
            {/* Sidebar */}
            <aside className="w-64 flex-shrink-0 bg-white dark:bg-[#1a202c] border-r border-[#f0f2f4] dark:border-gray-800 flex flex-col z-20">
                {/* Logo */}
                <div className="h-16 flex items-center gap-3 px-6 border-b border-[#f0f2f4] dark:border-gray-800">
                    <div className="size-8 text-primary">
                        <svg className="w-full h-full" fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
                            <path d="M39.5563 34.1455V13.8546C39.5563 15.708 36.8773 17.3437 32.7927 18.3189C30.2914 18.916 27.263 19.2655 24 19.2655C20.737 19.2655 17.7086 18.916 15.2073 18.3189C11.1227 17.3437 8.44365 15.708 8.44365 13.8546V34.1455C8.44365 35.9988 11.1227 37.6346 15.2073 38.6098C17.7086 39.2069 20.737 39.5564 24 39.5564C27.263 39.5564 30.2914 39.2069 32.7927 38.6098C36.8773 37.6346 39.5563 35.9988 39.5563 34.1455Z" fill="currentColor"/>
                            <path clipRule="evenodd" d="M10.4485 13.8519C10.4749 13.9271 10.6203 14.246 11.379 14.7361C12.298 15.3298 13.7492 15.9145 15.6717 16.3735C18.0007 16.9296 20.8712 17.2655 24 17.2655C27.1288 17.2655 29.9993 16.9296 32.3283 16.3735C34.2508 15.9145 35.702 15.3298 36.621 14.7361C37.3796 14.246 37.5251 13.9271 37.5515 13.8519C37.5287 13.7876 37.4333 13.5973 37.0635 13.2931C36.5266 12.8516 35.6288 12.3647 34.343 11.9175C31.79 11.0295 28.1333 10.4437 24 10.4437C19.8667 10.4437 16.2099 11.0295 13.657 11.9175C12.3712 12.3647 11.4734 12.8516 10.9365 13.2931C10.5667 13.5973 10.4713 13.7876 10.4485 13.8519ZM37.5563 18.7877C36.3176 19.3925 34.8502 19.8839 33.2571 20.2642C30.5836 20.9025 27.3973 21.2655 24 21.2655C20.6027 21.2655 17.4164 20.9025 14.7429 20.2642C13.1498 19.8839 11.6824 19.3925 10.4436 18.7877V34.1275C10.4515 34.1545 10.5427 34.4867 11.379 35.027C12.298 35.6207 13.7492 36.2054 15.6717 36.6644C18.0007 37.2205 20.8712 37.5564 24 37.5564C27.1288 37.5564 29.9993 37.2205 32.3283 36.6644C34.2508 36.2054 35.702 35.6207 36.621 35.027C37.4573 34.4867 37.5485 34.1546 37.5563 34.1275V18.7877ZM41.5563 13.8546V34.1455C41.5563 36.1078 40.158 37.5042 38.7915 38.3869C37.3498 39.3182 35.4192 40.0389 33.2571 40.5551C30.5836 41.1934 27.3973 41.5564 24 41.5564C20.6027 41.5564 17.4164 41.1934 14.7429 40.5551C12.5808 40.0389 10.6502 39.3182 9.20848 38.3869C7.84205 37.5042 6.44365 36.1078 6.44365 34.1455L6.44365 13.8546C6.44365 12.2684 7.37223 11.0454 8.39581 10.2036C9.43325 9.3505 10.8137 8.67141 12.343 8.13948C15.4203 7.06909 19.5418 6.44366 24 6.44366C28.4582 6.44366 32.5797 7.06909 35.657 8.13948C37.1863 8.67141 38.5667 9.3505 39.6042 10.2036C40.6278 11.0454 41.5563 12.2684 41.5563 13.8546Z" fill="currentColor" fillRule="evenodd"/>
                        </svg>
                    </div>
                    <h2 className="text-[#111318] dark:text-white text-lg font-bold leading-tight tracking-[-0.015em]">IntelliMed-AI</h2>
                </div>
                
                {/* Navigation */}
                <div className="flex flex-col gap-2 p-4 flex-1 overflow-y-auto">
                    <button className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors text-left" onClick={() => {/* Future: Navigate to dashboard overview */}}>
                        <Icon name="dashboard" className="text-xl" />
                        <span className="text-sm font-medium leading-normal">Dashboard</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 rounded-lg bg-primary/10 text-primary dark:text-primary transition-colors text-left" disabled>
                        <Icon name="group" filled className="text-xl" />
                        <span className="text-sm font-bold leading-normal">Patients</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors text-left" onClick={() => {/* Future: Navigate to documents */}}>
                        <Icon name="folder_open" className="text-xl" />
                        <span className="text-sm font-medium leading-normal">Documents</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors text-left" onClick={() => {/* Future: Navigate to AI analysis */}}>
                        <Icon name="auto_awesome" className="text-xl" />
                        <span className="text-sm font-medium leading-normal">AI Analysis</span>
                    </button>
                </div>
                
                {/* Bottom Settings */}
                <div className="p-4 border-t border-[#f0f2f4] dark:border-gray-800">
                    <button onClick={logout} className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-[#637588] dark:text-gray-400 hover:bg-[#f0f2f4] dark:hover:bg-gray-800 transition-colors w-full">
                        <Icon name="logout" className="text-xl" />
                        <span className="text-sm font-medium leading-normal">Logout</span>
                    </button>
                </div>
            </aside>

            {/* Main Content */}
            <main className="flex-1 flex flex-col min-w-0 bg-background-light dark:bg-background-dark overflow-hidden">
                {/* Top Header */}
                <header className="h-16 flex items-center justify-between px-6 bg-white dark:bg-[#1a202c] border-b border-[#f0f2f4] dark:border-gray-800 sticky top-0 z-10">
                    {/* Breadcrumbs */}
                    <div className="flex items-center gap-2">
                        <a className="text-[#637588] dark:text-gray-400 text-sm font-medium leading-normal hover:text-primary transition-colors" href="#">Dashboard</a>
                        <span className="text-[#637588] dark:text-gray-500 text-sm font-medium leading-normal">/</span>
                        <span className="text-[#111318] dark:text-white text-sm font-bold leading-normal">Patients</span>
                    </div>
                    
                    {/* Right Side Actions */}
                    <div className="flex items-center gap-6">
                        {/* Notifications */}
                        <button className="relative flex items-center justify-center size-10 rounded-full hover:bg-[#f0f2f4] dark:hover:bg-gray-700 text-[#637588] dark:text-gray-300 transition-colors">
                            <Icon name="notifications" className="text-[24px]" />
                            <span className="absolute top-2 right-2.5 size-2 rounded-full bg-red-500 ring-2 ring-white dark:ring-[#1a202c]"></span>
                        </button>
                        
                        {/* User Profile */}
                        <div className="flex items-center gap-3 pl-6 border-l border-[#f0f2f4] dark:border-gray-700">
                            <div className="flex flex-col items-end hidden sm:flex">
                                <span className="text-sm font-bold text-[#111318] dark:text-white leading-none">Dr. {user?.email?.split('@')[0]}</span>
                                <span className="text-xs text-[#637588] dark:text-gray-400 mt-1">Physician</span>
                            </div>
                            <div className="relative">
                                <div className="bg-primary flex items-center justify-center rounded-full size-10 ring-2 ring-[#f0f2f4] dark:ring-gray-700 text-white font-bold text-sm">
                                    {user?.email?.charAt(0).toUpperCase()}
                                </div>
                                <span className="absolute bottom-0 right-0 size-3 rounded-full bg-green-500 ring-2 ring-white dark:ring-[#1a202c]"></span>
                            </div>
                        </div>
                    </div>
                </header>

                {/* Scrollable Content */}
                <div className="flex-1 overflow-y-auto p-4 md:p-8">
                    <div className="max-w-[1200px] mx-auto flex flex-col gap-6">
                        {/* Page Header & Actions */}
                        <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
                            <div className="flex flex-col gap-1">
                                <h1 className="text-[#111318] dark:text-white text-3xl font-black leading-tight tracking-[-0.033em]">Patient List</h1>
                                <p className="text-[#637588] dark:text-gray-400 text-sm">Manage your patient records and documents.</p>
                            </div>
                            <div className="flex gap-3">
                                <button 
                                    onClick={() => setShowLinkModal(true)}
                                    className="flex items-center gap-2 h-10 px-4 rounded-lg bg-primary hover:bg-blue-700 text-white font-bold text-sm shadow-sm transition-colors"
                                >
                                    <Icon name="link" className="text-[20px]" />
                                    Link Patient
                                </button>
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
                </div>
            </main>

            {/* Modals */}
            {showLinkModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                    <LinkPatient 
                        onClose={() => setShowLinkModal(false)} 
                        onPatientLinked={() => fetchPatients()} 
                    />
                </div>
            )}

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

export default DoctorDashboard;

