import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api from '../services/api';
import Icon from '../components/Icon';
import { ui } from '../styles/ui.js';
import { Spinner, EmptyState } from '../components/ui.jsx';

const AllDocuments = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState('all'); // all, analyzed, pending
  const [sortBy, setSortBy] = useState('date'); // date, patient, name

  useEffect(() => {
    const fetchAllDocuments = async () => {
      try {
        setLoading(true);
        const patientsResponse = await api.get('/doctor/patients');
        const patients = patientsResponse.data;
        
        const docPromises = patients.map(patient =>
          api.get(`/doctor/patients/${patient.id}/documents`)
            .then(docsResponse => docsResponse.data.map(doc => ({
              ...doc,
              patientName: patient.email?.split('@')[0],
              patientEmail: patient.email,
              patientId: patient.id
            })))
            .catch(err => {
              console.error(`Failed to fetch documents for patient ${patient.id}`, err);
              return [];
            })
        );
        const results = await Promise.all(docPromises);
        setDocuments(results.flat());
      } catch (err) {
        console.error('Failed to fetch documents', err);
      } finally {
        setLoading(false);
      }
    };

    fetchAllDocuments();
  }, []);

  const getFileIcon = (filename) => {
    if (filename?.endsWith('.pdf')) 
      return { icon: 'picture_as_pdf', color: 'bg-danger/10 text-danger' };
    if (filename?.endsWith('.dcm')) 
      return { icon: 'imagesmode', color: 'bg-primary/10 text-primary' };
    if (filename?.match(/\.(jpg|jpeg|png)$/i)) 
      return { icon: 'image', color: 'bg-info/10 text-info' };
    return { icon: 'description', color: 'bg-surface-2 text-muted' };
  };

  // Filter and sort documents
  let filteredDocs = documents.filter(doc => {
    const matchesSearch = 
      doc.filename?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      doc.patientName?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      doc.patientEmail?.toLowerCase().includes(searchQuery.toLowerCase());
    
    if (!matchesSearch) return false;
    
    if (filterStatus === 'analyzed') return doc.ai_analysis;
    if (filterStatus === 'pending') return !doc.ai_analysis;
    return true;
  });

  // Sort documents
  filteredDocs.sort((a, b) => {
    if (sortBy === 'date') {
      return new Date(b.upload_timestamp) - new Date(a.upload_timestamp);
    } else if (sortBy === 'patient') {
      return (a.patientName || '').localeCompare(b.patientName || '');
    } else if (sortBy === 'name') {
      return (a.filename || '').localeCompare(b.filename || '');
    }
    return 0;
  });

  return (
    <div className={`${ui.page} overflow-y-auto`}>
      {/* Header */}
      <div className={ui.pageHeader}>
        <div>
          <h1 className={ui.pageTitle}>
            All Documents
          </h1>
          <p className={ui.pageSubtitle}>
            Browse and manage medical records from all patients.
          </p>
        </div>
      </div>

      {/* Filters Bar */}
      <div className="flex flex-col lg:flex-row gap-4 items-start lg:items-center justify-between">
        {/* Search */}
        <div className="relative flex-1 max-w-md w-full">
          <Icon name="search" className="absolute left-3 top-1/2 -translate-y-1/2 text-muted text-[20px]" />
          <input aria-label="Search documents"
            className={ui.inputIcon}
            placeholder="Search by document name or patient..."
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        {/* Filters */}
        <div className="flex gap-2 items-center flex-wrap">
          <div className="flex gap-1 p-1 bg-surface-2 rounded-lg">
            <button type="button" 
              onClick={() => setFilterStatus('all')}
              className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                filterStatus === 'all' ? 'bg-surface text-primary shadow-sm' : 'text-muted'
              }`}
            >
              All ({documents.length})
            </button>
            <button type="button" 
              onClick={() => setFilterStatus('analyzed')}
              className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                filterStatus === 'analyzed' ? 'bg-surface text-primary shadow-sm' : 'text-muted'
              }`}
            >
              Analyzed ({documents.filter(d => d.ai_analysis).length})
            </button>
            <button type="button" 
              onClick={() => setFilterStatus('pending')}
              className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                filterStatus === 'pending' ? 'bg-surface text-primary shadow-sm' : 'text-muted'
              }`}
            >
              Pending ({documents.filter(d => !d.ai_analysis).length})
            </button>
          </div>

          <select aria-label="Sort documents"
            value={sortBy}
            onChange={(e) => setSortBy(e.target.value)}
            className="h-9 px-3 rounded-lg border border-line bg-surface text-sm text-ink focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary"
          >
            <option value="date">Sort by Date</option>
            <option value="patient">Sort by Patient</option>
            <option value="name">Sort by Name</option>
          </select>
        </div>
      </div>

      {/* Documents Grid */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Spinner className="size-12" />
        </div>
      ) : filteredDocs.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredDocs.map((doc) => {
            const fileInfo = getFileIcon(doc.filename);
            return (
              <div 
                key={doc.id}
                onClick={() => navigate(`/document/${doc.id}`)}
                className={`${ui.card} p-4 hover:shadow-lg hover:border-primary transition-all cursor-pointer group`}
              >
                <div className="flex items-start gap-3 mb-3">
                  <div className={`size-12 rounded-lg ${fileInfo.color} flex items-center justify-center shrink-0`}>
                    <Icon name={fileInfo.icon} className="text-2xl" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <h3 className="text-sm font-bold text-ink truncate group-hover:text-primary transition-colors">
                      {doc.filename}
                    </h3>
                    <p className="text-xs text-muted mt-0.5">
                      {doc.filename?.split('.').pop().toUpperCase()}
                    </p>
                  </div>
                </div>

                <div className="space-y-2 mb-3">
                  <div className="flex items-center gap-2 text-xs text-body">
                    <Icon name="person" className="text-[14px]" />
                    <span className="font-medium">{doc.patientName}</span>
                  </div>
                  <div className="flex items-center gap-2 text-xs text-body">
                    <Icon name="calendar_today" className="text-[14px]" />
                    <span>{new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</span>
                  </div>
                </div>

                {doc.ai_analysis ? (
                  <div className={`${ui.badge} ${ui.badgeSuccess}`}>
                    <Icon name="check_circle" className="text-[14px]" />
                    <span>AI Analysis Complete</span>
                  </div>
                ) : (
                  <div className={`${ui.badge} ${ui.badgeWarning}`}>
                    <Icon name="pending" className="text-[14px]" />
                    <span>Pending Analysis</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      ) : (
        <div className={`${ui.card}`}>
          <EmptyState
            icon="folder_off"
            title="No documents found"
            hint={searchQuery ? 'Try adjusting your search or filters' : 'No documents have been uploaded yet'}
          />
        </div>
      )}
    </div>
  );
};

export default AllDocuments;