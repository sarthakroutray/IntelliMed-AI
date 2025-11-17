import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import '../styles/LoginPage.css';

const LoginPage = () => {
  const [activeTab, setActiveTab] = useState('patient');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const { login, googleLogin } = useAuth();
  const navigate = useNavigate();

  const handleGoogleLogin = useCallback(
    (response) => {
      googleLogin(response.credential, activeTab)
        .then(() => {
          navigate('/dashboard');
        })
        .catch((err) => {
          setError(
            err.response?.data?.detail || 'Google login failed. Please try again.'
          );
        });
    },
    [googleLogin, navigate, activeTab]
  );

  useEffect(() => {
    const initializeGoogleSignIn = () => {
      if (window.google && document.getElementById('googleSignInDiv')) {
        window.google.accounts.id.initialize({
          client_id: import.meta.env.VITE_GOOGLE_CLIENT_ID,
          callback: handleGoogleLogin,
        });
        window.google.accounts.id.renderButton(
          document.getElementById('googleSignInDiv'),
          { theme: 'outline', size: 'large', text: 'continue_with', width: '300' }
        );
      }
    };

    if (document.querySelector('script[src="https://accounts.google.com/gsi/client"]')) {
      initializeGoogleSignIn();
    } else {
      const script = document.createElement('script');
      script.src = 'https://accounts.google.com/gsi/client';
      script.async = true;
      script.defer = true;
      script.onload = initializeGoogleSignIn;
      document.body.appendChild(script);
    }
  }, [handleGoogleLogin]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    try {
      const response = await login(email, password);
      const userRole = response.role;
      
      // Validate that the user role matches the selected tab
      if (activeTab === 'patient' && userRole !== 'patient') {
        // Clear the login state since role doesn't match
        localStorage.removeItem('token');
        setError('This account is not a patient account. Please use the Doctor tab.');
        return;
      }
      if (activeTab === 'doctor' && userRole !== 'doctor' && userRole !== 'admin') {
        // Clear the login state since role doesn't match
        localStorage.removeItem('token');
        setError('This account is not a doctor account. Please use the Patient tab.');
        return;
      }
      
      navigate('/dashboard');
    } catch (err) {
      setError(err.response?.data?.detail || 'Login failed. Please check your credentials.');
    }
  };

  const renderForm = () => (
    <form onSubmit={handleSubmit} className="login-form">
      <div className="form-header">
        <h2>Welcome Back!</h2>
        <p>Sign in to access your {activeTab === 'patient' ? 'health' : 'medical'} dashboard</p>
      </div>
      
      {error && (
        <div className="error-alert">
          <span className="error-icon">⚠</span>
          <span>{error}</span>
        </div>
      )}
      
      
      <div className="form-group">
        <label htmlFor="email">Email Address</label>
        <input
          type="email"
          id="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          required
        />
      </div>
      <div className="form-group">
        <label htmlFor="password">Password</label>
        <input
          type="password"
          id="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="••••••••"
          required
        />
      </div>
      <button type="submit" className="login-button">
        <span>Sign In</span>
        <span className="button-arrow">→</span>
      </button>
      
      {activeTab === 'patient' && (
        <>
          <div className="divider">
            <span>or continue with</span>
          </div>

          <div id="googleSignInDiv" className="google-login-button"></div>
        </>
      )}
      
      <p className="register-link">
        Don't have an account? <Link to="/register">Sign up here</Link>
      </p>
    </form>
  );

  return (
    <div className="login-page-container">
      <main className="login-main">
        <section className="login-art-section">
          <div className="art-content">
            <div className="logo">IM</div>
            <h1>IntelliMed AI</h1>
            <p>Your intelligent health partner, providing seamless access to medical records and AI-powered insights for better healthcare outcomes.</p>
            <div className="features">
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>Secure Document Storage</span>
              </div>
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>AI-Powered Analysis</span>
              </div>
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>24/7 Access</span>
              </div>
            </div>
          </div>
        </section>
        <section className="login-form-section">
          <div className="login-tabs">
            <div
              className={`login-tab ${activeTab === 'patient' ? 'active' : ''}`}
              onClick={() => setActiveTab('patient')}
            >
              <span className="tab-icon">Patient</span>
            </div>
            <div
              className={`login-tab ${activeTab === 'doctor' ? 'active' : ''}`}
              onClick={() => setActiveTab('doctor')}
            >
              <span className="tab-icon">Doctor</span>
            </div>
          </div>
          {renderForm()}
        </section>
      </main>
    </div>
  );
};

export default LoginPage;
