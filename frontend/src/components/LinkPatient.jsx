import React, { useState } from 'react';
import api from '../services/api';
import '../styles/CodeManagement.css';

const LinkPatient = ({ onPatientLinked }) => {
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
      const response = await api.post('/doctor/link-patient', null, {
        params: { access_code: accessCode },
      });
      setMessage(response.data.message);
      setAccessCode('');
      if (onPatientLinked) {
        onPatientLinked();
      }
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to link patient.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="link-patient-container">
      <h3>Link New Patient</h3>
      <form onSubmit={handleLinkPatient}>
        <input
          type="text"
          placeholder="Enter Patient Access Code"
          value={accessCode}
          onChange={(e) => setAccessCode(e.target.value)}
          disabled={loading}
        />
        <button type="submit" disabled={loading}>
          {loading ? 'Linking...' : 'Link Patient'}
        </button>
      </form>
      {message && <p className="success-message">{message}</p>}
      {error && <p className="error-message">{error}</p>}
    </div>
  );
};

export default LinkPatient;
