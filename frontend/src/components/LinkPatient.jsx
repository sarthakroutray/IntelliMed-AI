import React, { useState } from 'react';
import api from '../services/api';
import Icon from './Icon.jsx';
import { ui } from '../styles/ui.js';
import { Alert, Spinner } from '../components/ui.jsx';

const LinkPatient = ({ onPatientLinked, onClose }) => {
  const [accessCode, setAccessCode] = useState('');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLinkPatient = async (e) => {
    e.preventDefault();
    setError('');
    setMessage('');

    if (!accessCode) {
      setError('Please enter an access code.');
      return;
    }

    setLoading(true);
    try {
      const response = await api.post('/doctor/link-patient', {
        access_code: accessCode,
      });
      setMessage(response.data.message);
      setAccessCode('');

      // Close modal after successful link
      setTimeout(() => {
        if (onClose) onClose();
        if (onPatientLinked) onPatientLinked();
      }, 1500);
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to link patient.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className={`${ui.card} max-w-md w-full p-6`}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-xl font-bold text-ink">Link Patient</h3>
        <button type="button" onClick={onClose} className="text-muted hover:text-ink transition-colors">
          <Icon name="close" className="text-[24px]" />
        </button>
      </div>

      <div className="flex flex-col gap-4">
      <p className="text-sm text-body">
        Enter the access code provided by your patient to link their account and view their medical documents.
      </p>

      <form onSubmit={handleLinkPatient} className="flex flex-col gap-4">
        <div className="relative">
          <Icon name="vpn_key" className="absolute left-3 top-1/2 -translate-y-1/2 text-muted text-[20px]" />
          <input aria-label="Access code"
            type="text"
            placeholder="Enter Patient Access Code"
            value={accessCode}
            onChange={(e) => setAccessCode(e.target.value)}
            disabled={loading}
            className={ui.inputIcon}
          />
        </div>

        <button
          type="submit"
          disabled={loading || !accessCode}
          className={`${ui.btn} ${ui.btnPrimary} w-full`}
        >
          {loading ? (
            <>
              <Spinner className="size-4" />
              <span>Linking Patient...</span>
            </>
          ) : (
            <>
              <Icon name="link" className="text-[18px]" />
              <span>Link Patient</span>
            </>
          )}
        </button>
      </form>

      {message && (
        <Alert type="success">{message}</Alert>
      )}

      {error && (
        <Alert type="error">{error}</Alert>
      )}
      </div>
    </div>
  );
};

export default LinkPatient;