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
  return api.post('/token', formData);
};

export const googleLogin = (googleToken) => {
  return api.post('/google-login', { token: googleToken });
};

export const register = (email, password, role) => {
  return api.post('/register', { email, password, role });
};

export const uploadDocument = (file) => {
  const formData = new FormData();
  formData.append('file', file);
  return api.post('/upload/', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });
};

export const getPatients = () => {
  return api.get('/patients/');
};

export const getPatientDocuments = (patientId) => {
  return api.get(`/patients/${patientId}/documents`);
};

export default api;
