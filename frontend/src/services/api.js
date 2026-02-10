import axios from 'axios';
import { apiCache, withCache, cacheKeys, invalidateCache } from '../utils/cache';

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
  }).then(result => {
    // Invalidate documents cache after upload
    invalidateCache.documents();
    return result;
  });
};

export const getDoctorPatients = withCache(
  () => api.get('/doctor/patients'),
  cacheKeys.patients,
  3 * 60 * 1000 // 3 minutes cache
);

export const getPatientDocuments = withCache(
  (patientId) => {
    const url = patientId ? `/doctor/patients/${patientId}/documents` : '/patient/documents';
    return api.get(url);
  },
  (patientId) => cacheKeys.documents(patientId),
  2 * 60 * 1000 // 2 minutes cache
);

export const deleteDocument = (documentId) => {
  return api.delete(`/patient/documents/${documentId}`).then(result => {
    // Invalidate documents cache after deletion
    invalidateCache.documents();
    return result;
  });
};

export const getDocument = withCache(
  (documentId) => api.get(`/documents/${documentId}`),
  (documentId) => cacheKeys.document(documentId),
  5 * 60 * 1000 // 5 minutes cache
);

export const verifyDocument = (documentId, notes) => {
  return api.post(`/documents/${documentId}/verify`, { notes });
};

export const addClinicalNote = (documentId, note) => {
  return api.post(`/documents/${documentId}/notes`, { note });
};

export const shareDocument = (documentId, doctorId) => {
  return api.post(`/patient/documents/${documentId}/share/${doctorId}`).then(result => {
    // Invalidate shared doctors cache
    apiCache.delete(cacheKeys.sharedDoctors(documentId));
    return result;
  });
};

export const unshareDocument = (documentId, doctorId) => {
  return api.delete(`/patient/documents/${documentId}/share/${doctorId}`).then(result => {
    // Invalidate shared doctors cache
    apiCache.delete(cacheKeys.sharedDoctors(documentId));
    return result;
  });
};

export const getSharedDoctors = withCache(
  (documentId) => api.get(`/patient/documents/${documentId}/shared-doctors`),
  (documentId) => cacheKeys.sharedDoctors(documentId),
  2 * 60 * 1000 // 2 minutes cache
);

export const archiveDocument = (documentId) => {
  return api.post(`/documents/${documentId}/archive`);
};

export const analyzeDocument = (documentId) => {
  return api.post(`/documents/${documentId}/analyze`).then(result => {
    // Invalidate document cache after analysis
    invalidateCache.document(documentId);
    return result;
  });
};

export const downloadDocument = (documentId) => {
  return api.get(`/documents/${documentId}/download`, {
    responseType: 'blob'
  });
};

// Linked doctors API with caching
export const getLinkedDoctors = withCache(
  () => api.get('/patient/linked-doctors'),
  cacheKeys.linkedDoctors,
  3 * 60 * 1000 // 3 minutes cache
);

export const linkDoctor = (accessCode) => {
  return api.post('/patient/link-doctor', { access_code: accessCode }).then(result => {
    // Invalidate linked doctors cache after linking
    invalidateCache.linkedDoctors();
    return result;
  });
};

// Export cache utilities for use in components
export { apiCache, invalidateCache };

export default api;

