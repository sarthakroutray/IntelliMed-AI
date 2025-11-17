import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import '../styles/SignUpPage.css';

const SignUpPage = () => {
  const [activeTab, setActiveTab] = useState('patient');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [doctorAccessCode, setDoctorAccessCode] = useState('');
  const [error, setError] = useState('');
  const { register } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    try {
      await register(email, password, activeTab, doctorAccessCode);
      navigate('/login');
    } catch (err) {
      setError(err.response?.data?.detail || 'Registration failed. Please try again.');
    }
  };

  const renderForm = () => (
    <form onSubmit={handleSubmit} className="signup-form">
      <div className="form-header">
        <h2>Create Your Account</h2>
        <p>Join IntelliMed AI and take control of your health journey</p>
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
      <div className="form-group">
        <label htmlFor="confirmPassword">Confirm Password</label>
        <input
          type="password"
          id="confirmPassword"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          placeholder="••••••••"
          required
        />
      </div>

      {activeTab === 'doctor' && (
        <div className="form-group doctor-code">
          <label htmlFor="doctorAccessCode">Doctor Access Code</label>
          <input
            type="text"
            id="doctorAccessCode"
            value={doctorAccessCode}
            onChange={(e) => setDoctorAccessCode(e.target.value)}
            placeholder="Enter your verification code"
            required
          />
          <small className="hint">Contact admin for your access code</small>
        </div>
      )}

      <button type="submit" className="signup-button">
        <span>Create Account</span>
        <span className="button-arrow">→</span>
      </button>
      
      <p className="login-link">
        Already have an account? <Link to="/login">Sign in here</Link>
      </p>
    </form>
  );

  return (
    <div className="signup-page-container">
      <main className="signup-main">
        <section className="signup-art-section">
          <div className="art-content">
            <div className="logo">IM</div>
            <h1>Welcome to IntelliMed AI</h1>
            <p>Your intelligent health partner, providing seamless access to medical records and AI-powered insights for better healthcare outcomes.</p>
            <div className="features">
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>HIPAA Compliant Security</span>
              </div>
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>Advanced AI Analysis</span>
              </div>
              <div className="feature-item">
                <span className="feature-icon">✓</span>
                <span>Real-time Insights</span>
              </div>
            </div>
          </div>
        </section>
        <section className="signup-form-section">
          <div className="signup-tabs">
            <div
              className={`signup-tab ${activeTab === 'patient' ? 'active' : ''}`}
              onClick={() => setActiveTab('patient')}
            >
              <span className="tab-icon">Patient</span>
            </div>
            <div
              className={`signup-tab ${activeTab === 'doctor' ? 'active' : ''}`}
              onClick={() => setActiveTab('doctor')}
            >
              <span className="tab-icon">Doctor</span>
              <span>Doctor</span>
            </div>
          </div>
          {renderForm()}
        </section>
      </main>
    </div>
  );
};

export default SignUpPage;
