import React, { useState } from 'react';
import { uploadDocument } from '../services/api';

const PatientDashboard = () => {
  const [selectedFile, setSelectedFile] = useState(null);
  const [documents, setDocuments] = useState([]);
  const [message, setMessage] = useState('');
  const [uploading, setUploading] = useState(false);

  const handleFileChange = (event) => {
    setSelectedFile(event.target.files[0]);
    setMessage('');
  };

  const handleUpload = async () => {
    if (!selectedFile) {
      setMessage('Please select a file first.');
      return;
    }
    setUploading(true);
    setMessage(`Uploading and analyzing ${selectedFile.name}...`);
    try {
      const response = await uploadDocument(selectedFile);
      setMessage('File analysis complete!');
      setDocuments([response.data, ...documents]);
      setSelectedFile(null);
    } catch (error) {
      setMessage('File upload failed. Please try again.');
      console.error(error);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div>
      <h1 className="text-4xl font-bold mb-8">Patient Health Dashboard</h1>
      
      <div className="card">
        <h2 className="text-2xl font-semibold mb-4">Upload New Medical Record</h2>
        <div className="flex items-center space-x-6">
          <label className="w-full flex items-center px-4 py-3 bg-white text-blue-500 rounded-lg shadow-md tracking-wide uppercase border border-blue-500 cursor-pointer hover:bg-blue-500 hover:text-white">
            <svg className="w-8 h-8" fill="currentColor" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
                <path d="M16.88 9.1A4 4 0 0 1 16 17H5a5 5 0 0 1-1-9.9V7a3 3 0 0 1 4.52-2.59A4.98 4.98 0 0 1 17 8c0 .38-.04.74-.12 1.1zM11 11h3l-4 4-4-4h3V3h2v8z" />
            </svg>
            <span className="ml-4 text-base leading-normal">{selectedFile ? selectedFile.name : 'Select a file'}</span>
            <input type='file' className="hidden" onChange={handleFileChange} />
          </label>
          <button onClick={handleUpload} className="btn" disabled={uploading || !selectedFile}>
            {uploading ? 'Processing...' : 'Upload & Analyze'}
          </button>
        </div>
        {message && <p className="mt-4 text-center font-medium">{message}</p>}
      </div>

      <h2 className="text-3xl font-semibold mt-10 mb-6">Your Document History</h2>
      {documents.length > 0 ? (
        <div className="space-y-6">
          {documents.map((doc, index) => (
            <div key={index} className="card">
              <div className="flex justify-between items-start">
                <div>
                  <h3 className="text-2xl font-semibold">{doc.filename}</h3>
                  <p className="text-sm text-gray-500 mt-1">
                    Uploaded: {new Date(doc.upload_timestamp).toLocaleString()}
                  </p>
                </div>
                <span className="text-base font-semibold bg-green-200 text-green-800 py-1 px-4 rounded-full">
                  Analyzed
                </span>
              </div>
              <div className="mt-6 pt-6 border-t">
                <h4 className="font-semibold text-lg mb-3">AI Analysis Summary:</h4>
                <pre className="bg-gray-100 p-4 rounded-lg mt-2 overflow-auto text-sm leading-relaxed">
                  {JSON.stringify(doc.ai_analysis, null, 2)}
                </pre>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="card text-center py-16">
          <h3 className="text-2xl font-semibold">No Documents Found</h3>
          <p className="text-gray-500 mt-3">Upload your first medical record to see its AI-powered analysis here.</p>
        </div>
      )}
    </div>
  );
};

export default PatientDashboard;

