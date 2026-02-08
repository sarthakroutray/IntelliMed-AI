import axios from 'axios';

const api = axios.create({
  baseURL: 'http://localhost:8000/api',
});

api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('token');
    if (token) {
      config.headers['Authorization'] = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

export const login = (email, password) => {
  const formData = new FormData();
  formData.append('username', email);
  formData.append('password', password);
  return api.post('/auth/token', formData);
};

export const googleLogin = (googleToken, role) => {
  return api.post('/auth/google-login', { token: googleToken, role: role });
};

export const register = (email, password, role, doctorAccessCode) => {
  return api.post('/auth/register', { email, password, role, doctor_access_code: doctorAccessCode });
};

export const uploadDocument = (file) => {
  const formData = new FormData();
  formData.append('file', file);
  return api.post('/patient/upload/', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });
};

export const getDoctorPatients = () => {
    return api.get('/doctor/patients');
};

export const getPatientDocuments = (patientId, token) => {
  // If patientId is not provided, the backend should infer the user from the token
  const url = patientId ? `/doctor/patients/${patientId}/documents` : '/patient/documents';
  return api.get(url);
};

export const deleteDocument = (documentId) => {
  return api.delete(`/patient/documents/${documentId}`);
};

export const getDocument = (documentId) => {
  return api.get(`/documents/${documentId}`);
};

export const verifyDocument = (documentId, notes) => {
  return api.post(`/documents/${documentId}/verify`, { notes });
};

export const addClinicalNote = (documentId, note) => {
  return api.post(`/documents/${documentId}/notes`, { note });
};

export const shareDocument = (documentId, doctorId) => {
  return api.post(`/patient/documents/${documentId}/share/${doctorId}`);
};

export const unshareDocument = (documentId, doctorId) => {
  return api.delete(`/patient/documents/${documentId}/share/${doctorId}`);
};

export const getSharedDoctors = (documentId) => {
  return api.get(`/patient/documents/${documentId}/shared-doctors`);
};

export const archiveDocument = (documentId) => {
  return api.post(`/documents/${documentId}/archive`);
};

export const analyzeDocument = (documentId) => {
  return api.post(`/documents/${documentId}/analyze`);
};

export const downloadDocument = (documentId) => {
  return api.get(`/documents/${documentId}/download`, {
    responseType: 'blob'
  });
};

export default api;
