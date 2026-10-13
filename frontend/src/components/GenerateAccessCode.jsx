import React, { useState } from 'react';
import api from '../services/api';
import Icon from './Icon.jsx';
import { ui } from '../styles/ui.js';
import { Alert, Spinner } from '../components/ui.jsx';

const GenerateAccessCode = () => {
  const [accessCode, setAccessCode] = useState('');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  const handleGenerateCode = async () => {
    setError('');
    setMessage('');
    setAccessCode('');
    setCopied(false);
    setLoading(true);
    try {
      const response = await api.post('/patient/generate-access-code');
      setAccessCode(response.data.access_code);
      setMessage('Share this code with your doctor to grant them access.');
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to generate access code.');
    } finally {
      setLoading(false);
    }
  };

  const handleCopyCode = () => {
    navigator.clipboard.writeText(accessCode);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="flex flex-col gap-4">
      <p className="text-sm text-body">
        Generate a secure, one-time access code for your doctor to view your medical records.
      </p>

      <button type="button"
        onClick={handleGenerateCode}
        disabled={loading}
        className={`${ui.btn} ${ui.btnPrimary} w-full`}
      >
        {loading ? (
          <>
            <Spinner className="size-4" />
            <span>Generating Code...</span>
          </>
        ) : (
          <>
            <Icon name="vpn_key" className="text-[18px]" />
            <span>Generate Access Code</span>
          </>
        )}
      </button>

      {accessCode && (
        <div className="flex flex-col gap-3 p-4 rounded-lg bg-info/10 border border-info/20">
          <div className="flex items-start gap-2">
            <Icon name="info" className="text-info text-[20px] shrink-0 mt-0.5" />
            <p className="text-sm text-body">{message}</p>
          </div>

          <div className="flex items-center gap-2 p-3 rounded-lg bg-surface border border-info/30">
            <code className="flex-1 text-2xl font-bold text-primary tracking-wider text-center">
              {accessCode}
            </code>
            <button type="button"
              onClick={handleCopyCode}
              className="flex items-center justify-center size-9 rounded-lg hover:bg-surface-2 text-muted transition-colors"
              title="Copy to clipboard"
            >
              <Icon name={copied ? 'check' : 'content_copy'} className="text-[20px]" />
            </button>
          </div>

          {copied && (
            <p className="text-xs text-center text-success font-medium">
              ✓ Copied to clipboard!
            </p>
          )}
        </div>
      )}

      {error && (
        <Alert type="error">{error}</Alert>
      )}
    </div>
  );
};

export default GenerateAccessCode;