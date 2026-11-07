import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { getLinkedPatients, deletePatient } from '../services/api';
import Icon from '../components/Icon.jsx';
import { Alert, ConfirmDialog, EmptyState } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const Patients = () => {
  const { user } = useAuth();
  const [patients, setPatients] = useState([]);
  const [error, setError] = useState('');
  const [pendingDelete, setPendingDelete] = useState(null);
  const [loading, setLoading] = useState(true);

  const fetchPatients = useCallback(async () => {
    try {
      setLoading(true);
      const res = await getLinkedPatients(user.id);
      setPatients(res.data || []);
    } catch (err) {
      setError('Failed to load your linked patients.');
    } finally {
      setLoading(false);
    }
  }, [user.id]);

  useEffect(() => {
    fetchPatients();
  }, [fetchPatients]);

  const handleDeletePatient = async (patientId) => {
    try {
      await deletePatient(patientId);
      setPatients(prev => prev.filter(p => p.id !== patientId));
    } catch (err) {
      console.error('Delete failed', err);
    }
  };

  return (
    <div className="space-y-6">
      <div className={ui.pageHeader}>
        <h1 className={`${ui.pageTitle} mt-2`}>Patients</h1>
        <p className={ui.pageSubtitle}>Manage your linked patients.</p>
      </div>

      {error && <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>}

      {loading ? (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map(i => (
            <div key={i} className={ui.card}>
              <div className={ui.cardHeader}>
                <div className="h-4 w-24 bg-surface-2 rounded"></div>
                <div className="h-8 w-8 bg-surface-2 rounded-full"></div>
              </div>
              <div className="p-5 md:p-7">
                <div className="h-3 w-full bg-surface-2 rounded mb-2"></div>
                <div className="h-3 w-2/3 bg-surface-2 rounded"></div>
              </div>
            </div>
          ))}
        </div>
      ) : patients.length === 0 ? (
        <EmptyState
          icon="people"
          title="No patients linked"
          hint="You must first link a patient from their dashboard."
        />
      ) : (
        <section className={`${ui.card} overflow-hidden`}>
          <div className={ui.cardHeader}>
            <h3 className="text-base font-semibold text-ink">Your linked patients</h3>
            <p className="ledger-label text-muted">{patients.length}</p>
          </div>
          <table className="w-full text-left border-collapse">
            <thead>
              <tr>
                <th className={ui.th}>Patient</th>
                <th className={`${ui.th} text-right`}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {patients.map(p => (
                <tr key={p.id} className={`${ui.tr} group`}>
                  <td className="px-5 md:px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="bg-primary/10 text-primary rounded-full size-8 flex items-center justify-center">
                        <Icon name="person" className="text-[18px]" />
                      </div>
                      <span className="text-sm font-medium text-ink truncate">{p.name}</span>
                    </div>
                  </td>
                  <td className="px-5 md:px-6 py-4 text-right">
                    <button
                      onClick={() => window.location.href = `/patient-dashboard?doctor=${p.id}`}
                      className={`${ui.btn} ${ui.btnSecondary} ${ui.btnSm}`}
                    >
                      <Icon name="visibility" className="text-[15px]" />
                    </button>
                    <button
                      onClick={() => setPendingDelete(p.id)}
                      className="size-9 flex items-center justify-center rounded hover:bg-danger/10 text-subtle hover:text-danger ml-1"
                    >
                      <Icon name="delete" className="text-[19px]" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      <ConfirmDialog
        open={pendingDelete !== null}
        title="Delete patient?"
        message="This will remove the patient from your linked list."
        confirmLabel="Delete"
        danger
        onConfirm={() => handleDeletePatient(pendingDelete)}
        onCancel={() => setPendingDelete(null)}
      />
    </div>
  );
};

export default Patients;
