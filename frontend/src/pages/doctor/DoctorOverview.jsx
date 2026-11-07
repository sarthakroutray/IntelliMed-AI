import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../../context/AuthContext';
import { getLinkedDoctors, getDoctorStats, getPatientDocuments, deleteDocument } from '../../services/api';
import Icon from '../../components/Icon.jsx';
import { Alert, EmptyState } from '../../components/ui.jsx';
import { ui } from '../../styles/ui.js';

const DoctorOverview = () => {
  const { user } = useAuth();
  const [stats, setStats] = useState(null);
  const [linkedDoctors, setLinkedDoctors] = useState([]);
  const [patients, setPatients] = useState([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  const fetchOverview = useCallback(async () => {
    try {
      const doctorsRes = await getLinkedDoctors();
      const statsRes = await getDoctorStats(user.id);
      const patientsRes = await getPatientDocuments();
      
      setLinkedDoctors(doctorsRes.data || []);
      setStats({
        patients: patientsRes.data?.length || 0,
        documents: patientsRes.data?.reduce((sum, doc) => sum + (doc.pageviews || 0), 0) || 0,
        ai_analysis_count: 0,
      });
      setPatients(patientsRes.data || []);
    } catch (err) {
      console.error('Fetch overview failed:', err);
      setError(err.response?.data?.detail || 'Failed to load data.');
    } finally {
      setLoading(false);
    }
  }, [user.id]);

  useEffect(() => { fetchOverview(); }, [fetchOverview]);

  const statItems = [
    { label: 'Linked doctors', value: stats?.patients || 0, icon: 'people' },
    { label: 'Documents', value: stats?.documents || 0, icon: 'description' },
    { label: 'AI analyses', value: stats?.ai_analysis_count || 0, icon: 'smart_toy' },
  ];

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <div className="flex flex-col">
          <h1 className={`${ui.pageTitle} mt-2`}>Dashboard</h1>
          <p className={ui.pageSubtitle}>Your patient activity, documents, and AI analyses.</p>
        </div>
      </div>

      {error && <Alert type="error">{error}</Alert>}

      {loading ? (
        <div className="grid md:grid-cols-3 gap-4">
          {[1,2,3].map(i => (
            <div key={i} className={ui.card}>
              <div className="flex items-center justify-between px-5 md:px-7 py-4 border-b border-line">
                <div className="h-5 w-24 bg-surface-2 rounded"></div>
                <div className="h-8 w-8 bg-surface-2 rounded-full"></div>
              </div>
              <div className="p-5 md:p-7">
                <div className="h-8 w-16 bg-surface-2 rounded mb-3"></div>
                <div className="h-4 w-32 bg-surface-2 rounded"></div>
              </div>
            </div>
          ))}
        </div>
      ) : stats && (
        <section className="grid md:grid-cols-3 gap-4">
          {statItems.map((item) => (
            <div key={item.label} className={ui.card}>
              <div className={ui.cardHeader}>
                <div className="flex items-center gap-3">
                  <div className="size-10 rounded-full bg-primary/10 text-primary flex items-center justify-center">
                    <Icon name={item.icon} className="text-[22px]" />
                  </div>
                  <p className="ledger-label text-muted">{item.label}</p>
                </div>
              </div>
              <div className="p-5 md:p-7 text-center">
                <p className="text-[36px] font-serif font-semibold text-ink tnum">{item.value}</p>
                <p className="text-muted text-sm mt-1 font-medium">{item.value === 0 ? 'No activity yet' : 'This month'}</p>
              </div>
            </div>
          ))}
        </section>
      )}

      <section className={`${ui.card} overflow-hidden`}>
        <div className={ui.cardHeader}>
          <h3 className="text-base font-semibold text-ink">Recent documents</h3>
          <p className="ledger-label text-muted">Your patients' uploads</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr>
                <th className={ui.th}>Patient</th>
                <th className={ui.th}>Document</th>
                <th className={ui.th}>Uploaded</th>
                <th className={`${ui.th} text-right`}>Status</th>
              </tr>
            </thead>
            <tbody>
              {patients.length === 0 ? (
                <tr>
                  <td colSpan="4">
                    <EmptyState icon="inbox" title="No documents uploaded yet." hint="Wait for patients to upload their records." />
                  </td>
                </tr>
              ) : (
                patients.slice(0, 5).map(doc => (
                  <tr key={doc.id} className={`${ui.tr} group`}>
                    <td className="px-5 md:px-6 py-4">
                      <span className="text-sm font-medium text-ink">{doc.patient_name || 'Unknown patient'}</span>
                    </td>
                    <td className={`${ui.td} max-w-xs truncate`}>{doc.filename}</td>
                    <td className={`${ui.td}`}>{new Date(doc.upload_timestamp).toLocaleDateString('en-US')}</td>
                    <td className="px-5 md:px-6 py-4 text-right text-muted text-sm font-mono">
                      {doc.pageviews ? `${doc.pageviews} views` : 'Not yet viewed'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
};

export default DoctorOverview;