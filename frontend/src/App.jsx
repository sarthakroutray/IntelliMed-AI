import React, { Suspense, lazy } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext.jsx';
import PrivateRoute from './components/PrivateRoute.jsx';
import { useAuth } from './context/AuthContext.jsx';
const LoginPage = lazy(() => import('./pages/LoginPage.jsx'));
const SignUpPage = lazy(() => import('./pages/SignUpPage.jsx'));
const PatientDashboardLayout = lazy(() => import('./pages/PatientDashboardLayout.jsx'));
const DoctorDashboardLayout = lazy(() => import('./pages/DoctorDashboardLayout.jsx'));
const MedicalDocumentViewer = lazy(() => import('./pages/MedicalDocumentViewer.jsx'));

// Loading fallback component
const LoadingFallback = () => (
  <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-[#0f1419]">
    <div className="flex flex-col items-center gap-4">
      <div className="w-12 h-12 border-4 border-blue-500 border-t-transparent rounded-full animate-spin"></div>
      <p className="text-gray-600 dark:text-gray-400 text-sm">Loading...</p>
    </div>
  </div>
);

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
        <Suspense fallback={<LoadingFallback />}>
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
        </Suspense>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
