import React, { useState, useEffect, useCallback, useRef } from 'react';
import Icon from './Icon.jsx';
import { Modal, Alert, Spinner } from './ui.jsx';
import { ui } from '../styles/ui.js';
import { getLinkedDoctors, getSharedDoctors, shareDocument, unshareDocument } from '../services/api';
import GenerateAccessCode from './GenerateAccessCode.jsx';

/**
 * Interactive dialog that allows patients to manage document sharing permissions
 * with their linked doctors.
 */
const ShareDocumentModal = ({
  open,
  onClose,
  document,
  initialSharedDoctors = [],
  onShareChange,
}) => {
  const [linkedDoctors, setLinkedDoctors] = useState([]);
  const [sharedDoctors, setSharedDoctors] = useState(initialSharedDoctors || []);
  const [loading, setLoading] = useState(false);
  const [togglingId, setTogglingId] = useState(null);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [showConnectCode, setShowConnectCode] = useState(false);

  const onShareChangeRef = useRef(onShareChange);
  useEffect(() => {
    onShareChangeRef.current = onShareChange;
  }, [onShareChange]);

  const loadData = useCallback(async () => {
    if (!open || !document?.id) return;
    setLoading(true);
    setError('');
    setShowConnectCode(false);
    try {
      const [linkedRes, sharedRes] = await Promise.all([
        getLinkedDoctors(),
        getSharedDoctors(document.id),
      ]);

      const linked = Array.isArray(linkedRes?.data)
        ? linkedRes.data
        : Array.isArray(linkedRes)
          ? linkedRes
          : [];

      const shared = Array.isArray(sharedRes?.data)
        ? sharedRes.data
        : Array.isArray(sharedRes)
          ? sharedRes
          : [];

      setLinkedDoctors(linked);
      setSharedDoctors(shared);
      onShareChangeRef.current?.(document.id, shared);
    } catch (err) {
      console.error('Failed to load sharing details:', err);
      setError(
        err.response?.data?.detail ||
          'Failed to load doctor connections. Please try again.'
      );
    } finally {
      setLoading(false);
    }
  }, [open, document?.id]);

  useEffect(() => {
    if (open && document?.id) {
      if (initialSharedDoctors && initialSharedDoctors.length > 0) {
        setSharedDoctors(initialSharedDoctors);
      }
      loadData();
    }
  }, [open, document?.id, loadData]);

  // Derived set of doctor IDs who have access
  const sharedDoctorIds = new Set(
    sharedDoctors.map((s) => s.doctor_id ?? s.id)
  );

  const handleToggle = async (doctor, isCurrentlyShared) => {
    if (!document?.id || togglingId !== null) return;
    setTogglingId(doctor.id);
    setError('');
    setSuccess('');

    try {
      if (isCurrentlyShared) {
        await unshareDocument(document.id, doctor.id);
        const nextShared = sharedDoctors.filter(
          (s) => (s.doctor_id ?? s.id) !== doctor.id
        );
        setSharedDoctors(nextShared);
        onShareChangeRef.current?.(document.id, nextShared);
        setSuccess(`Revoked access for ${doctor.name || doctor.email}.`);
      } else {
        await shareDocument(document.id, doctor.id);
        const newEntry = {
          doctor_id: doctor.id,
          doctor_email: doctor.email,
          doctor_name: doctor.name || null,
        };
        const nextShared = [...sharedDoctors, newEntry];
        setSharedDoctors(nextShared);
        onShareChangeRef.current?.(document.id, nextShared);
        setSuccess(`Document shared with ${doctor.name || doctor.email}.`);
      }
    } catch (err) {
      console.error('Error toggling document share:', err);
      const detail = err.response?.data?.detail;
      const message =
        typeof detail === 'string'
          ? detail
          : Array.isArray(detail)
            ? detail.map((d) => d?.msg || JSON.stringify(d)).join('; ')
            : detail?.message ||
              detail?.msg ||
              'Failed to update sharing permissions.';
      setError(message);
    } finally {
      setTogglingId(null);
    }
  };

  if (!open || !document) return null;

  const docTitle =
    document.filename ||
    document.fileName ||
    (document.id ? `Document #${document.id}` : 'Medical Document');

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Share Document"
      maxWidth="max-w-lg"
    >
      <div className="flex flex-col gap-4">
        {/* Document Info Card */}
        <div className="flex items-center gap-3 p-3.5 bg-surface-2 rounded-lg border border-line">
          <div className="size-10 rounded bg-primary/10 text-primary flex items-center justify-center shrink-0">
            <Icon name="description" className="text-[22px]" />
          </div>
          <div className="min-w-0 flex-1">
            <h4 className="text-sm font-semibold text-ink truncate" title={docTitle}>
              {docTitle}
            </h4>
            <p className="text-xs text-muted mt-0.5">
              {sharedDoctors.length > 0
                ? `Shared with ${sharedDoctors.length} doctor${sharedDoctors.length === 1 ? '' : 's'}`
                : 'Private record (not shared with any doctor)'}
            </p>
          </div>
          <div className="shrink-0">
            {sharedDoctors.length > 0 ? (
              <span className={`${ui.badge} ${ui.badgeSuccess}`}>
                <Icon name="share" className="text-[11px]" />
                Shared ({sharedDoctors.length})
              </span>
            ) : (
              <span className={`${ui.badge} ${ui.badgeNeutral}`}>
                <Icon name="lock" className="text-[11px]" />
                Private
              </span>
            )}
          </div>
        </div>

        {/* Feedback Alerts */}
        {error && (
          <Alert type="error" onDismiss={() => setError('')}>
            {error}
          </Alert>
        )}
        {success && (
          <Alert type="success" onDismiss={() => setSuccess('')}>
            {success}
          </Alert>
        )}

        {/* Loading State */}
        {loading ? (
          <div className="flex flex-col items-center justify-center py-10 gap-3">
            <Spinner className="size-7 text-primary" />
            <p className="text-xs text-muted">Loading doctor connections...</p>
          </div>
        ) : showConnectCode ? (
          /* Inline Generate Access Code */
          <div className="pt-2 border-t border-line">
            <div className="flex items-center justify-between mb-3">
              <h4 className="text-sm font-semibold text-ink">Connect a Doctor</h4>
              <button
                type="button"
                onClick={() => {
                  setShowConnectCode(false);
                  loadData();
                }}
                className={`${ui.btn} ${ui.btnGhost} ${ui.btnSm}`}
              >
                <Icon name="arrow_back" className="text-[15px]" />
                Back to doctors
              </button>
            </div>
            <GenerateAccessCode />
          </div>
        ) : linkedDoctors.length === 0 ? (
          /* Empty State: No linked doctors */
          <div className="text-center py-7 px-4 border border-dashed border-line rounded-lg bg-surface-2/40">
            <div className="size-11 rounded-full bg-primary/10 text-primary mx-auto flex items-center justify-center mb-3">
              <Icon name="person_search" className="text-[22px]" />
            </div>
            <h4 className="text-sm font-semibold text-ink">No linked doctors yet</h4>
            <p className="text-xs text-muted mt-1.5 max-w-sm mx-auto leading-relaxed">
              To share your records, you must first connect with a doctor using an access code.
              Once your doctor accepts the code, they will appear here.
            </p>
            <button
              type="button"
              onClick={() => setShowConnectCode(true)}
              className={`${ui.btn} ${ui.btnPrimary} ${ui.btnSm} mt-4`}
            >
              <Icon name="key" className="text-[15px]" />
              Generate Access Code
            </button>
          </div>
        ) : (
          /* List of Linked Doctors */
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <p className="text-xs text-muted">
                Choose which doctors can access this document and its AI analysis:
              </p>
              <button
                type="button"
                onClick={() => setShowConnectCode(true)}
                className="text-xs text-primary hover:underline font-medium inline-flex items-center gap-1"
              >
                <Icon name="add" className="text-[14px]" />
                Link another doctor
              </button>
            </div>

            <div className="divide-y divide-line rounded-lg border border-line bg-surface max-h-[300px] overflow-y-auto">
              {linkedDoctors.map((doc) => {
                const isShared = sharedDoctorIds.has(doc.id);
                const isToggling = togglingId === doc.id;
                const docName = doc.name || doc.email?.split('@')[0] || 'Doctor';

                return (
                  <div
                    key={doc.id}
                    className="flex items-center justify-between p-3.5 hover:bg-surface-2/50 transition-colors gap-3"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      <div className="size-9 rounded-full bg-surface-2 border border-line flex items-center justify-center text-primary shrink-0">
                        <Icon name="medical_services" className="text-[18px]" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium text-ink truncate">
                          {docName}
                        </p>
                        <p className="text-xs text-muted truncate">{doc.email}</p>
                      </div>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      {isShared ? (
                        <button
                          type="button"
                          onClick={() => handleToggle(doc, true)}
                          disabled={isToggling}
                          className={`${ui.btn} ${ui.btnSoftDanger} ${ui.btnSm}`}
                          title="Revoke access to this document"
                        >
                          {isToggling ? (
                            <Spinner className="size-3.5" />
                          ) : (
                            <>
                              <Icon name="check" className="text-[14px]" />
                              <span>Shared</span>
                            </>
                          )}
                        </button>
                      ) : (
                        <button
                          type="button"
                          onClick={() => handleToggle(doc, false)}
                          disabled={isToggling}
                          className={`${ui.btn} ${ui.btnPrimary} ${ui.btnSm}`}
                          title="Grant access to this document"
                        >
                          {isToggling ? (
                            <Spinner className="size-3.5" />
                          ) : (
                            <>
                              <Icon name="share" className="text-[14px]" />
                              <span>Share</span>
                            </>
                          )}
                        </button>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Footer */}
        <div className="flex justify-end pt-2 border-t border-line">
          <button
            type="button"
            onClick={onClose}
            className={`${ui.btn} ${ui.btnSecondary} w-full sm:w-auto px-6`}
          >
            Done
          </button>
        </div>
      </div>
    </Modal>
  );
};

export default ShareDocumentModal;
