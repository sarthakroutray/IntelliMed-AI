import React, { useState } from 'react';
import api from '../services/api';
import '../styles/CodeManagement.css';

const GenerateAccessCode = () => {
  const [accessCode, setAccessCode] = useState('');
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleGenerateCode = async () => {
    setError('');
    setMessage('');
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

  return (
    <div className="generate-code-container">
      <h3>Grant Doctor Access</h3>
      <p>Generate a secure, one-time code for your doctor to view your records.</p>
      <button onClick={handleGenerateCode} disabled={loading}>
        {loading ? 'Generating...' : 'Generate Access Code'}
      </button>
      {accessCode && (
        <div className="access-code-display">
          <p>{message}</p>
          <strong>{accessCode}</strong>
        </div>
      )}
      {error && <p className="error-message">{error}</p>}
    </div>
  );
};

export default GenerateAccessCode;
