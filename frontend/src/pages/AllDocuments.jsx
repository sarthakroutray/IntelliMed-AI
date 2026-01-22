import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api from '../services/api';
import Icon from '../components/Icon';

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
        
        const allDocs = [];
        for (const patient of patients) {
          try {
            const docsResponse = await api.get(`/doctor/patients/${patient.id}/documents`);
            const docs = docsResponse.data.map(doc => ({
              ...doc,
              patientName: patient.email?.split('@')[0],
              patientEmail: patient.email,
              patientId: patient.id
            }));
            allDocs.push(...docs);
          } catch (err) {
            console.error(`Failed to fetch documents for patient ${patient.id}`, err);
          }
        }
        
        setDocuments(allDocs);
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
      return { icon: 'picture_as_pdf', color: 'bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400' };
    if (filename?.endsWith('.dcm')) 
      return { icon: 'imagesmode', color: 'bg-blue-100 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400' };
    if (filename?.match(/\.(jpg|jpeg|png)$/i)) 
      return { icon: 'image', color: 'bg-purple-100 dark:bg-purple-900/30 text-purple-600 dark:text-purple-400' };
    return { icon: 'description', color: 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400' };
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
    <div className="flex-1 overflow-y-auto p-4 md:p-8">
      <div className="max-w-[1400px] mx-auto flex flex-col gap-6">
        {/* Header */}
        <div>
          <h1 className="text-3xl font-black text-gray-900 dark:text-white mb-2">
            All Documents
          </h1>
          <p className="text-gray-500 dark:text-gray-400">
            Browse and manage medical records from all patients.
          </p>
        </div>

        {/* Filters Bar */}
        <div className="flex flex-col lg:flex-row gap-4 items-start lg:items-center justify-between">
          {/* Search */}
          <div className="relative flex-1 max-w-md w-full">
            <Icon name="search" className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-[20px]" />
            <input 
              className="w-full h-10 pl-10 pr-4 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-[#1a202c] text-sm focus:border-primary focus:ring-0 placeholder:text-gray-400 dark:text-white"
              placeholder="Search by document name or patient..."
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          {/* Filters */}
          <div className="flex gap-2 items-center flex-wrap">
            <div className="flex gap-1 p-1 bg-gray-100 dark:bg-gray-800 rounded-lg">
              <button 
                onClick={() => setFilterStatus('all')}
                className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                  filterStatus === 'all' ? 'bg-white dark:bg-[#1a202c] text-primary shadow-sm' : 'text-gray-600 dark:text-gray-400'
                }`}
              >
                All ({documents.length})
              </button>
              <button 
                onClick={() => setFilterStatus('analyzed')}
                className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                  filterStatus === 'analyzed' ? 'bg-white dark:bg-[#1a202c] text-primary shadow-sm' : 'text-gray-600 dark:text-gray-400'
                }`}
              >
                Analyzed ({documents.filter(d => d.ai_analysis).length})
              </button>
              <button 
                onClick={() => setFilterStatus('pending')}
                className={`px-3 py-1.5 rounded-md text-xs font-bold transition-colors ${
                  filterStatus === 'pending' ? 'bg-white dark:bg-[#1a202c] text-primary shadow-sm' : 'text-gray-600 dark:text-gray-400'
                }`}
              >
                Pending ({documents.filter(d => !d.ai_analysis).length})
              </button>
            </div>

            <select 
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value)}
              className="h-9 px-3 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-[#1a202c] text-sm text-gray-700 dark:text-gray-300 focus:border-primary focus:ring-0"
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
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
          </div>
        ) : filteredDocs.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filteredDocs.map((doc) => {
              const fileInfo = getFileIcon(doc.filename);
              return (
                <div 
                  key={doc.id}
                  onClick={() => navigate(`/document/${doc.id}`)}
                  className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 p-4 hover:shadow-lg hover:border-primary dark:hover:border-primary transition-all cursor-pointer group"
                >
                  <div className="flex items-start gap-3 mb-3">
                    <div className={`size-12 rounded-lg ${fileInfo.color} flex items-center justify-center flex-shrink-0`}>
                      <Icon name={fileInfo.icon} className="text-2xl" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <h3 className="text-sm font-bold text-gray-900 dark:text-white truncate group-hover:text-primary transition-colors">
                        {doc.filename}
                      </h3>
                      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                        {doc.filename?.split('.').pop().toUpperCase()}
                      </p>
                    </div>
                  </div>

                  <div className="space-y-2 mb-3">
                    <div className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
                      <Icon name="person" className="text-[14px]" />
                      <span className="font-medium">{doc.patientName}</span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-gray-600 dark:text-gray-400">
                      <Icon name="calendar_today" className="text-[14px]" />
                      <span>{new Date(doc.upload_timestamp).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</span>
                    </div>
                  </div>

                  {doc.ai_analysis ? (
                    <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 text-xs font-medium">
                      <Icon name="check_circle" className="text-[14px]" />
                      <span>AI Analysis Complete</span>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-orange-100 dark:bg-orange-900/30 text-orange-700 dark:text-orange-400 text-xs font-medium">
                      <Icon name="pending" className="text-[14px]" />
                      <span>Pending Analysis</span>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        ) : (
          <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 p-12 text-center">
            <Icon name="folder_off" className="text-gray-300 dark:text-gray-600 text-6xl mx-auto mb-4" />
            <h3 className="text-lg font-bold text-gray-900 dark:text-white mb-2">No documents found</h3>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {searchQuery ? 'Try adjusting your search or filters' : 'No documents have been uploaded yet'}
            </p>
          </div>
        )}
      </div>
    </div>
  );
};

export default AllDocuments;
