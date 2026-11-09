import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import api, { unlinkPatient, analyzeDocument } from '../services/api.js';
import Icon from '../components/Icon.jsx';
import { ui } from '../styles/ui.js';
import { Alert, Modal, ConfirmDialog, Spinner, EmptyState, Toast } from '../components/ui.jsx';

const DoctorPatients = ({ refreshKey = 0 }) => {
  const navigate = useNavigate();
  const [patients, setPatients] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState('recent'); // 'recent', 'name', 'documents'
  const [docFilter, setDocFilter] = useState('all'); // 'all', 'has_docs', 'no_docs'
  const [currentPage, setCurrentPage] = useState(1);
  const [selectedPatient, setSelectedPatient] = useState(null);
  const [patientDocuments, setPatientDocuments] = useState([]);
  const [loadingDocs, setLoadingDocs] = useState(false);
  const [patientToUnlink, setPatientToUnlink] = useState(null);
  const [unlinking, setUnlinking] = useState(false);
  const [analyzingDocId, setAnalyzingDocId] = useState(null);
  const [toast, setToast] = useState(null);

  const itemsPerPage = 6;

  const handleViewPatientDocuments = async (patient) => {
    setSelectedPatient(patient);
    setLoadingDocs(true);
    try {
      const response = await api.get(`/doctor/patients/${patient.id}/documents`);
      setPatientDocuments(response.data || []);
    } catch (err) {
      console.error(err);
      setError(`Failed to fetch documents for ${patient.email}`);
    } finally {
      setLoadingDocs(false);
    }
  };

  const handleAnalyzeInModal = async (docId) => {
    setAnalyzingDocId(docId);
    try {
      await analyzeDocument(docId);
      if (selectedPatient) {
        const response = await api.get(`/doctor/patients/${selectedPatient.id}/documents`);
        setPatientDocuments(response.data || []);
      }
      setToast({ type: 'success', message: 'AI Analysis complete!' });
    } catch (err) {
      console.error('Modal analysis failed', err);
      setToast({ type: 'error', message: err.response?.data?.detail || 'Analysis failed.' });
    } finally {
      setAnalyzingDocId(null);
    }
  };

  const fetchPatients = useCallback(async () => {
    try {
      setLoading(true);
      setError('');
      const response = await api.get('/doctor/patients');
      const patientsData = response.data || [];

      // Fetch document counts for all patients in parallel
      const patientsWithCounts = await Promise.all(
        patientsData.map(async (patient) => {
          try {
            const docsResponse = await api.get(`/doctor/patients/${patient.id}/documents`);
            return { ...patient, document_count: (docsResponse.data || []).length };
          } catch {
            return { ...patient, document_count: 0 };
          }
        })
      );

      setPatients(patientsWithCounts);
    } catch (err) {
      console.error('Failed to fetch patients:', err);
      setError(err.response?.data?.detail || 'Failed to fetch linked patients.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchPatients();
  }, [fetchPatients, refreshKey]);

  const handleUnlink = async () => {
    if (!patientToUnlink) return;
    setUnlinking(true);
    try {
      await unlinkPatient(patientToUnlink.id);
      setToast({
        type: 'success',
        message: `Patient ${patientToUnlink.name || patientToUnlink.email} has been unlinked.`,
      });
      setPatientToUnlink(null);
      await fetchPatients();
    } catch (err) {
      console.error('Failed to unlink patient:', err);
      setToast({
        type: 'error',
        message: err.response?.data?.detail || 'Failed to unlink patient.',
      });
    } finally {
      setUnlinking(false);
    }
  };

  // Filter & Sort
  const processedPatients = useMemo(() => {
    let result = patients.filter((patient) => {
      const q = searchQuery.toLowerCase();
      const matchesSearch =
        !q ||
        patient.email?.toLowerCase().includes(q) ||
        patient.name?.toLowerCase().includes(q) ||
        patient.id?.toString().includes(q);

      const matchesDoc =
        docFilter === 'all' ||
        (docFilter === 'has_docs' && (patient.document_count || 0) > 0) ||
        (docFilter === 'no_docs' && (patient.document_count || 0) === 0);

      return matchesSearch && matchesDoc;
    });

    result.sort((a, b) => {
      if (sortBy === 'name') {
        const nameA = a.name || a.email || '';
        const nameB = b.name || b.email || '';
        return nameA.localeCompare(nameB);
      }
      if (sortBy === 'documents') {
        return (b.document_count || 0) - (a.document_count || 0);
      }
      // 'recent' by default
      return new Date(b.created_at || 0) - new Date(a.created_at || 0);
    });

    return result;
  }, [patients, searchQuery, sortBy, docFilter]);

  const totalPages = Math.max(1, Math.ceil(processedPatients.length / itemsPerPage));
  const paginatedPatients = processedPatients.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );

  const getInitials = (patient) => {
    if (patient?.name) {
      return patient.name.charAt(0).toUpperCase();
    }
    return patient?.email?.charAt(0).toUpperCase() || '?';
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
      {/* Header */}
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <p className="ledger-label text-muted">Patient Directory</p>
          <h1 className={`${ui.pageTitle} mt-2`}>Linked Patients</h1>
          <p className={ui.pageSubtitle}>
            Manage patient relationships and review documents shared with you.
          </p>
        </div>
      </div>

      {error && <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>}

      {/* Toolbar */}
      <div className="flex flex-col md:flex-row gap-4 items-stretch md:items-center justify-between">
        <div className="relative flex-1 max-w-md">
          <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <Icon name="search" className="text-muted text-[20px]" />
          </div>
          <input
            aria-label="Search patients"
            className={ui.inputIcon}
            placeholder="Search by name, ID or email..."
            type="text"
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              setCurrentPage(1);
            }}
          />
        </div>

        <div className="flex flex-wrap items-center gap-3">
          {/* Filter by docs */}
          <div className="flex items-center gap-1.5 text-xs text-muted">
            <span>Filter:</span>
            <select
              value={docFilter}
              onChange={(e) => {
                setDocFilter(e.target.value);
                setCurrentPage(1);
              }}
              className="rounded border border-line bg-surface text-ink text-xs px-2.5 py-1.5 focus:outline-none focus:border-primary"
            >
              <option value="all">All patients</option>
              <option value="has_docs">With documents</option>
              <option value="no_docs">No documents yet</option>
            </select>
          </div>

          {/* Sort by */}
          <div className="flex items-center gap-1.5 text-xs text-muted">
            <span>Sort:</span>
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="rounded border border-line bg-surface text-ink text-xs px-2.5 py-1.5 focus:outline-none focus:border-primary"
            >
              <option value="recent">Recently linked</option>
              <option value="name">Name / Email</option>
              <option value="documents">Document count</option>
            </select>
          </div>
        </div>
      </div>

      {/* Table Card */}
      <div className={`${ui.card} overflow-hidden flex flex-col`}>
        <div className={ui.cardHeader}>
          <h3 className="font-semibold text-ink">Active Patients</h3>
          <p className="ledger-label text-muted">
            {processedPatients.length} {processedPatients.length === 1 ? 'patient' : 'patients'}
          </p>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center py-20 gap-3">
            <Spinner className="size-10 text-primary" />
            <p className="text-sm text-muted">Loading linked patients...</p>
          </div>
        ) : paginatedPatients.length > 0 ? (
          <>
            <div className="overflow-x-auto">
              <table className={ui.table}>
                <thead>
                  <tr className="border-b border-line bg-surface-2/50">
                    <th className={`${ui.th} w-[280px]`}>Patient</th>
                    <th className={ui.th}>Identifier</th>
                    <th className={ui.th}>Linked Since</th>
                    <th className={ui.th}>Shared Docs</th>
                    <th className={`${ui.th} text-right`}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {paginatedPatients.map((patient, index) => (
                    <tr
                      key={patient.id}
                      className={`${ui.tr} group`}
                    >
                      <td
                        className={`${ui.td} cursor-pointer`}
                        onClick={() => handleViewPatientDocuments(patient)}
                      >
                        <div className="flex items-center gap-3">
                          <div
                            className={`flex items-center justify-center size-10 rounded-full ${getAvatarColor(
                              index
                            )} font-bold text-sm shrink-0`}
                          >
                            {getInitials(patient)}
                          </div>
                          <div className="flex flex-col min-w-0">
                            <span className="text-sm font-bold text-ink truncate">
                              {patient.name || patient.email?.split('@')[0]}
                            </span>
                            <span className="text-xs text-muted truncate">{patient.email}</span>
                          </div>
                        </div>
                      </td>

                      <td
                        className={`${ui.td} cursor-pointer`}
                        onClick={() => handleViewPatientDocuments(patient)}
                      >
                        <span className="text-xs font-mono font-medium text-ink bg-surface-2 px-2 py-1 rounded border border-line">
                          ID: #{patient.id}
                        </span>
                      </td>

                      <td
                        className={`${ui.td} cursor-pointer`}
                        onClick={() => handleViewPatientDocuments(patient)}
                      >
                        <span className="text-xs font-mono text-muted tnum">
                          {patient.created_at
                            ? new Date(patient.created_at).toLocaleDateString('en-US', {
                                month: 'short',
                                day: 'numeric',
                                year: 'numeric',
                              })
                            : 'N/A'}
                        </span>
                      </td>

                      <td
                        className={`${ui.td} cursor-pointer`}
                        onClick={() => handleViewPatientDocuments(patient)}
                      >
                        {patient.document_count > 0 ? (
                          <span className={`${ui.badge} ${ui.badgeSuccess}`}>
                            <Icon name="description" className="text-[12px]" />
                            {patient.document_count} shared
                          </span>
                        ) : (
                          <span className={`${ui.badge} ${ui.badgeNeutral}`}>
                            0 shared
                          </span>
                        )}
                      </td>

                      <td className={`${ui.td} text-right whitespace-nowrap`}>
                        <div className="flex items-center justify-end gap-2">
                          <button
                            type="button"
                            onClick={() => handleViewPatientDocuments(patient)}
                            className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                            title="View shared documents"
                          >
                            <Icon name="folder_open" className="text-[15px]" />
                            Documents
                          </button>
                          <button
                            type="button"
                            onClick={() => setPatientToUnlink(patient)}
                            className="size-8 flex items-center justify-center rounded hover:bg-danger/10 text-muted hover:text-danger transition-colors"
                            title="Unlink patient"
                          >
                            <Icon name="link_off" className="text-[18px]" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {totalPages > 1 && (
              <div className="p-4 border-t border-line flex items-center justify-between">
                <span className="text-xs text-muted">
                  Showing {(currentPage - 1) * itemsPerPage + 1} to{' '}
                  {Math.min(currentPage * itemsPerPage, processedPatients.length)} of{' '}
                  {processedPatients.length} entries
                </span>
                <div className="flex items-center gap-1.5">
                  <button
                    type="button"
                    onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                    disabled={currentPage === 1}
                    className="size-8 flex items-center justify-center rounded border border-line text-muted hover:bg-surface-2 disabled:opacity-40"
                  >
                    <Icon name="chevron_left" className="text-[18px]" />
                  </button>
                  {Array.from({ length: totalPages }, (_, i) => i + 1).map((page) => (
                    <button
                      type="button"
                      key={page}
                      onClick={() => setCurrentPage(page)}
                      className={`size-8 flex items-center justify-center rounded text-xs font-semibold ${
                        currentPage === page
                          ? 'bg-primary text-white border border-primary'
                          : 'border border-line text-muted hover:bg-surface-2'
                      }`}
                    >
                      {page}
                    </button>
                  ))}
                  <button
                    type="button"
                    onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                    disabled={currentPage === totalPages}
                    className="size-8 flex items-center justify-center rounded border border-line text-muted hover:bg-surface-2 disabled:opacity-40"
                  >
                    <Icon name="chevron_right" className="text-[18px]" />
                  </button>
                </div>
              </div>
            )}
          </>
        ) : (
          <EmptyState
            icon="person_off"
            title="No linked patients found"
            hint={
              searchQuery || docFilter !== 'all'
                ? 'Try adjusting your search criteria or filter.'
                : 'Have your patient provide an access code, then click "Link patient" in the top bar to connect.'
            }
          />
        )}
      </div>

      {/* Patient Documents Modal */}
      <Modal
        open={Boolean(selectedPatient)}
        onClose={() => setSelectedPatient(null)}
        title={`${selectedPatient?.name || selectedPatient?.email?.split('@')[0] || 'Patient'}'s Shared Records`}
        maxWidth="max-w-2xl"
      >
        <div className="flex flex-col gap-4">
          <div className="flex items-center justify-between p-3 bg-surface-2 rounded-lg border border-line">
            <div className="flex items-center gap-3">
              <div className="size-9 rounded-full bg-primary/10 text-primary flex items-center justify-center font-bold text-sm">
                {selectedPatient?.email?.charAt(0).toUpperCase()}
              </div>
              <div>
                <p className="text-sm font-semibold text-ink">
                  {selectedPatient?.name || selectedPatient?.email}
                </p>
                <p className="text-xs text-muted">ID: #{selectedPatient?.id}</p>
              </div>
            </div>
            <span className={`${ui.badge} ${ui.badgeNeutral}`}>
              {patientDocuments.length} document{patientDocuments.length === 1 ? '' : 's'}
            </span>
          </div>

          <div className="max-h-[50vh] overflow-y-auto space-y-3">
            {loadingDocs ? (
              <div className="flex items-center justify-center py-12">
                <Spinner className="size-8 text-primary" />
              </div>
            ) : patientDocuments.length > 0 ? (
              patientDocuments.map((doc) => {
                const isAnalyzed = Boolean(doc.ai_analysis);
                return (
                  <div
                    key={doc.id}
                    className="p-3.5 rounded-lg border border-line bg-surface hover:border-primary transition-colors flex items-center justify-between gap-3"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <div className="size-9 rounded bg-primary/10 flex items-center justify-center text-primary shrink-0">
                        <Icon name="description" className="text-[20px]" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <h4 className="text-sm font-semibold text-ink truncate" title={doc.filename}>
                          {doc.filename}
                        </h4>
                        <div className="flex items-center gap-2 mt-0.5">
                          <span className="text-xs text-muted">
                            {doc.upload_timestamp
                              ? new Date(doc.upload_timestamp).toLocaleDateString('en-US', {
                                  month: 'short',
                                  day: 'numeric',
                                  year: 'numeric',
                                })
                              : 'N/A'}
                          </span>
                          {isAnalyzed ? (
                            <span className="text-[11px] text-success flex items-center gap-1 font-medium">
                              <Icon name="check_circle" className="text-[13px]" />
                              AI Ready
                            </span>
                          ) : (
                            <span className="text-[11px] text-muted">Pending AI</span>
                          )}
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      {!isAnalyzed && (
                        <button
                          type="button"
                          onClick={() => handleAnalyzeInModal(doc.id)}
                          disabled={analyzingDocId === doc.id}
                          className={`${ui.btn} ${ui.btnSoftPrimary} ${ui.btnSm}`}
                        >
                          {analyzingDocId === doc.id ? (
                            <Spinner className="size-3" />
                          ) : (
                            <>
                              <Icon name="smart_toy" className="text-[14px]" />
                              Analyze
                            </>
                          )}
                        </button>
                      )}
                      <button
                        type="button"
                        onClick={() => navigate(`/document/${doc.id}`)}
                        className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                      >
                        <Icon name="visibility" className="text-[15px]" />
                        View
                      </button>
                    </div>
                  </div>
                );
              })
            ) : (
              <EmptyState
                icon="folder_off"
                title="No documents shared yet"
                hint="This patient has not shared any documents with you."
              />
            )}
          </div>
        </div>
      </Modal>

      {/* Unlink Confirmation Dialog */}
      <ConfirmDialog
        open={Boolean(patientToUnlink)}
        title="Unlink Patient"
        message={`Are you sure you want to unlink ${
          patientToUnlink?.name || patientToUnlink?.email
        }? You will no longer have access to their shared documents.`}
        confirmLabel="Unlink Patient"
        danger
        busy={unlinking}
        onConfirm={handleUnlink}
        onCancel={() => setPatientToUnlink(null)}
      />

      {/* Toast */}
      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
};

export default DoctorPatients;
