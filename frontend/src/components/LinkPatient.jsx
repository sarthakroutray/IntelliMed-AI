import React, { useState } from 'react';
import api from '../services/api';
import Icon from './Icon.jsx';

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
    <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-md w-full p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-xl font-bold text-[#111318] dark:text-white">Link Patient</h3>
        <button onClick={onClose} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
          <Icon name="close" className="text-[24px]" />
        </button>
      </div>
      
      <div className="flex flex-col gap-4">
      <p className="text-sm text-[#637588] dark:text-gray-400">
        Enter the access code provided by your patient to link their account and view their medical documents.
      </p>
      
      <form onSubmit={handleLinkPatient} className="flex flex-col gap-4">
        <div className="relative">
          <Icon name="vpn_key" className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-[20px]" />
          <input
            type="text"
            placeholder="Enter Patient Access Code"
            value={accessCode}
            onChange={(e) => setAccessCode(e.target.value)}
            disabled={loading}
            className="w-full pl-10 pr-4 py-2.5 rounded-lg border border-[#dbdfe6] dark:border-gray-700 bg-white dark:bg-[#1a202c] text-[#111318] dark:text-white placeholder-gray-400 focus:border-primary focus:ring-2 focus:ring-primary/20 disabled:opacity-50 disabled:cursor-not-allowed"
          />
        </div>
        
        <button 
          type="submit" 
          disabled={loading || !accessCode}
          className="w-full flex items-center justify-center gap-2 py-2.5 rounded-lg bg-primary hover:bg-blue-700 text-white font-bold text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {loading ? (
            <>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
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
        <div className="flex items-start gap-2 p-3 rounded-lg bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800">
          <Icon name="check_circle" className="text-green-600 dark:text-green-400 text-[20px] flex-shrink-0 mt-0.5" />
          <p className="text-sm text-green-700 dark:text-green-300">{message}</p>
        </div>
      )}
      
      {error && (
        <div className="flex items-start gap-2 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <Icon name="error" className="text-red-600 dark:text-red-400 text-[20px] flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
        </div>
      )}
      </div>
    </div>
  );
};

export default LinkPatient;
