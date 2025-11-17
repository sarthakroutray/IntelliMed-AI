import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './context/AuthContext.jsx';
import PrivateRoute from './components/PrivateRoute.jsx';
import Navbar from './components/Navbar.jsx';
import LoginPage from './pages/LoginPage.jsx';
import SignUpPage from './pages/SignUpPage.jsx';
import PatientDashboard from './pages/PatientDashboard.jsx';
import DoctorDashboard from './pages/DoctorDashboard.jsx';
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
    return <Navigate to="/doctor-dashboard" replace />;
  }
  
  return <Navigate to="/login" replace />;
};

function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Navbar />
        <div className="container">
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<SignUpPage />} />
            <Route path="/dashboard" element={<DashboardRedirect />} />
            <Route 
              path="/patient-dashboard" 
              element={
                <PrivateRoute roles={['patient']}>
                  <PatientDashboard />
                </PrivateRoute>
              } 
            />
            <Route 
              path="/doctor-dashboard" 
              element={
                <PrivateRoute roles={['doctor', 'admin']}>
                  <DoctorDashboard />
                </PrivateRoute>
              } 
            />
            <Route path="/" element={<LoginPage />} />
          </Routes>
        </div>
      </BrowserRouter>
    </AuthProvider>
  );
}

export default App;
