import axios from 'axios';
import { apiCache, withCache, cacheKeys, invalidateCache } from '../utils/cache';

const rawApiBaseUrl = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000/api/v1').trim();
const normalizedApiBaseUrl = rawApiBaseUrl.replace(/\/+$/, '');
const apiBaseUrl = normalizedApiBaseUrl.endsWith('/api/v1')
  ? normalizedApiBaseUrl
  : `${normalizedApiBaseUrl}/api/v1`;

// v2 base shares the same origin: http://host/api/v1 -> http://host/api/v2
const apiV2BaseUrl = apiBaseUrl.replace(/\/api\/v1$/, '/api/v2');

const REQUEST_TIMEOUT_MS = parseInt(import.meta.env.VITE_REQUEST_TIMEOUT_MS || '120000', 10);
const HEAVY_TIMEOUT_MS = parseInt(import.meta.env.VITE_HEAVY_TIMEOUT_MS || '900000', 10);

const api = axios.create({
  baseURL: apiBaseUrl,
  timeout: REQUEST_TIMEOUT_MS,
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

export const uploadDocument = (file, onUploadProgress) => {
  const formData = new FormData();
  formData.append('file', file);
  return api.post('/patient/upload/', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
    timeout: HEAVY_TIMEOUT_MS,
    onUploadProgress,
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

export const getDoctorDocuments = withCache(
  () => api.get('/doctor/documents'),
  () => 'doctor-documents',
  2 * 60 * 1000 // 2 minutes cache
);

export const unlinkPatient = (patientId) => {
  return api.delete(`/doctor/patients/${patientId}`).then(result => {
    apiCache.delete(cacheKeys.patients());
    apiCache.delete('doctor-documents');
    invalidateCache.documents();
    return result;
  });
};

export const getDoctorStats = async () => {
  const [patientsRes, docsRes] = await Promise.all([
    getDoctorPatients(),
    getDoctorDocuments(),
  ]);
  const patients = patientsRes.data || [];
  const docs = docsRes.data || [];
  const aiCompleted = docs.filter(d => Boolean(d.ai_analysis)).length;
  return {
    data: {
      totalPatients: patients.length,
      totalDocuments: docs.length,
      aiAnalysisComplete: aiCompleted,
      pendingReviews: docs.length - aiCompleted,
    }
  };
};

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
  return api.post(`/documents/${documentId}/verify`, { notes }).then(result => {
    invalidateCache.document(documentId);
    invalidateCache.documents();
    return result;
  });
};

export const addClinicalNote = (documentId, note) => {
  return api.post(`/documents/${documentId}/notes`, { note }).then(result => {
    invalidateCache.document(documentId);
    return result;
  });
};

export const shareDocument = (documentId, doctorId) => {
  return api.post(`/patient/documents/${documentId}/share/${doctorId}`).then(result => {
    // Invalidate shared doctors cache
    apiCache.delete(cacheKeys.sharedDoctors(documentId));
    invalidateCache.documents();
    return result;
  });
};

export const unshareDocument = (documentId, doctorId) => {
  return api.delete(`/patient/documents/${documentId}/share/${doctorId}`).then(result => {
    // Invalidate shared doctors cache
    apiCache.delete(cacheKeys.sharedDoctors(documentId));
    invalidateCache.documents();
    return result;
  });
};

export const getSharedDoctors = withCache(
  (documentId) => api.get(`/patient/documents/${documentId}/shared-doctors`),
  (documentId) => cacheKeys.sharedDoctors(documentId),
  2 * 60 * 1000 // 2 minutes cache
);

export const archiveDocument = (documentId) => {
  return api.post(`/documents/${documentId}/archive`).then(result => {
    invalidateCache.document(documentId);
    invalidateCache.documents();
    return result;
  });
};

export const analyzeDocument = (documentId) => {
  return api.post(`/documents/${documentId}/analyze`, null, {
    timeout: HEAVY_TIMEOUT_MS,
  }).then(result => {
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
  return api.post('/doctor/link-patient', { access_code: accessCode }).then(result => {
    // Invalidate linked doctors and doctor patients caches after linking
    invalidateCache.linkedDoctors();
    invalidateCache.patients();
    apiCache.delete('doctor-documents');
    return result;
  });
};

// Lab reports API (v2 pipeline + listing for web parity). v2 lives on a
// separate axios instance so cached v1 keys and interceptors stay unchanged.
const apiV2 = axios.create({
  baseURL: apiV2BaseUrl,
  timeout: REQUEST_TIMEOUT_MS,
});

apiV2.interceptors.request.use(
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

export const uploadLabReport = (file, source = 'web', onUploadProgress) => {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('source', source);
  return apiV2.post('/lab-reports/upload', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
    timeout: HEAVY_TIMEOUT_MS,
    onUploadProgress,
  });
};

export const getLabReports = () => {
  return apiV2.get('/lab-reports');
};

export const getLabReport = (labReportId) => {
  return apiV2.get(`/lab-reports/${labReportId}`);
};

export const deleteLabReport = (labReportId) => {
  return apiV2.delete(`/lab-reports/${labReportId}`);
};

export const getPatientLabReports = (patientId) => {
  return apiV2.get(`/lab-reports/patient/${patientId}`);
};

// Export cache utilities for use in components
export { apiCache, invalidateCache };

export default api;

