import React, { useState } from 'react';
import api from '../services/api';
import Icon from './Icon.jsx';

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
      <p className="text-sm text-[#637588] dark:text-gray-400">
        Generate a secure, one-time access code for your doctor to view your medical records.
      </p>
      
      <button 
        onClick={handleGenerateCode} 
        disabled={loading}
        className="w-full flex items-center justify-center gap-2 py-2.5 rounded-lg bg-primary hover:bg-blue-700 text-white font-bold text-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {loading ? (
          <>
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
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
        <div className="flex flex-col gap-3 p-4 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800">
          <div className="flex items-start gap-2">
            <Icon name="info" className="text-blue-600 dark:text-blue-400 text-[20px] flex-shrink-0 mt-0.5" />
            <p className="text-sm text-blue-700 dark:text-blue-300">{message}</p>
          </div>
          
          <div className="flex items-center gap-2 p-3 rounded-lg bg-white dark:bg-gray-800 border border-blue-300 dark:border-blue-700">
            <code className="flex-1 text-2xl font-bold text-primary dark:text-blue-400 tracking-wider text-center">
              {accessCode}
            </code>
            <button
              onClick={handleCopyCode}
              className="flex items-center justify-center size-9 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-600 dark:text-gray-400 transition-colors"
              title="Copy to clipboard"
            >
              <Icon name={copied ? 'check' : 'content_copy'} className="text-[20px]" />
            </button>
          </div>
          
          {copied && (
            <p className="text-xs text-center text-green-600 dark:text-green-400 font-medium">
              ✓ Copied to clipboard!
            </p>
          )}
        </div>
      )}
      
      {error && (
        <div className="flex items-start gap-2 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
          <Icon name="error" className="text-red-600 dark:text-red-400 text-[20px] flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-700 dark:text-red-300">{error}</p>
        </div>
      )}
    </div>
  );
};

export default GenerateAccessCode;
