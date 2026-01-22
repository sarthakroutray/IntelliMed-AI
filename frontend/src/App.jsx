import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext.jsx';
import PrivateRoute from './components/PrivateRoute.jsx';
import LoginPage from './pages/LoginPage.jsx';
import SignUpPage from './pages/SignUpPage.jsx';
import PatientDashboardLayout from './pages/PatientDashboardLayout.jsx';
import DoctorDashboardLayout from './pages/DoctorDashboardLayout.jsx';
import MedicalDocumentViewer from './pages/MedicalDocumentViewer.jsx';
import { useAuth } from './context/AuthContext.jsx';

const DashboardRedirect = () => {
  const { user } = useAuth();
  
  if (!user) {
    return <Navigate to="/login" replace />;
  }
  
  if (user.role === 'patient') {
    return <Navigate to="/patient-dashboard" replace />;
  }
  
  if (user.role === 'doctor' || user.role === 'admin') {
    return <Navigate to="/dashboard/overview" replace />;
  }
  
  return <Navigate to="/login" replace />;
};

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<SignUpPage />} />
            <Route path="/dashboard" element={<DashboardRedirect />} />
            
            {/* Patient Routes */}
            <Route 
              path="/patient-dashboard/*" 
              element={
                <PrivateRoute roles={['patient']}>
                  <PatientDashboardLayout />
                </PrivateRoute>
              } 
            />

            {/* Doctor Routes */}
            <Route 
              path="/dashboard/*" 
              element={
                <PrivateRoute roles={['doctor', 'admin']}>
                  <DoctorDashboardLayout />
                </PrivateRoute>
              } 
            />
            
            {/* Document Viewer */}
            <Route 
              path="/document/:documentId" 
              element={
                <PrivateRoute roles={['doctor', 'admin', 'patient']}>
                  <MedicalDocumentViewer />
                </PrivateRoute>
              } 
            />
            
            <Route path="/" element={<LoginPage />} />
          </Routes>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
