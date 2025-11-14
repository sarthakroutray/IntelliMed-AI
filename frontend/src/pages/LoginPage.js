import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';

const LoginPage = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const { login, googleLogin, user } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    try {
      await login(email, password);
      // Redirect based on role after login
    } catch (err) {
      setError('Failed to log in. Please check your credentials.');
      console.error(err);
    }
  };

  const handleGoogleLogin = useCallback(async (response) => {
    setError('');
    try {
      await googleLogin(response.credential);
      // Redirect based on role after login
    } catch (err) {
      setError('Failed to log in with Google. Please try again.');
      console.error(err);
    }
  }, [googleLogin]);

  // Initialize Google Sign-In when component mounts
  useEffect(() => {
    const initializeGoogleSignIn = () => {
      if (window.google) {
        window.google.accounts.id.initialize({
          client_id: process.env.REACT_APP_GOOGLE_CLIENT_ID,
          callback: handleGoogleLogin,
        });
        window.google.accounts.id.renderButton(
          document.getElementById('google-signin-button'),
          { theme: 'outline', size: 'large', width: '100%' }
        );
      }
    };
    
    // Check if Google API is loaded
    if (document.querySelector('script[src*="accounts.google.com"]')) {
      initializeGoogleSignIn();
    } else {
      // Load Google API script
      const script = document.createElement('script');
      script.src = 'https://accounts.google.com/gsi/client';
      script.async = true;
      script.onload = initializeGoogleSignIn;
      document.body.appendChild(script);
    }
  }, [handleGoogleLogin]);

  // Redirect if user is already logged in
  React.useEffect(() => {
    if (user) {
      if (user.role === 'doctor') {
        navigate('/doctor-dashboard');
      } else {
        navigate('/patient-dashboard');
      }
    }
  }, [user, navigate]);

  return (
    <div style={{ maxWidth: '480px', margin: '8rem auto' }}>
      <div className="card">
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold" style={{ background: 'linear-gradient(to right, #4e54c8, #8f94fb)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>IntelliMed AI</h1>
          <p className="text-gray-600 mt-2">Revolutionizing Medical Data Analysis</p>
        </div>
        <h2 className="text-2xl font-bold text-center mb-6">Secure Login</h2>
        <form onSubmit={handleSubmit}>
          <div className="mb-5">
            <label className="block mb-2 font-semibold">Email Address</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="form-input"
              placeholder="you@example.com"
              required
            />
          </div>
          <div className="mb-8">
            <label className="block mb-2 font-semibold">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="form-input"
              placeholder="••••••••"
              required
            />
          </div>
          {error && <p className="text-red-500 text-center text-sm mb-4">{error}</p>}
          <button type="submit" className="btn w-full">Login</button>
        </form>

        <div className="my-6 flex items-center">
          <div style={{ flex: 1, height: '1px', backgroundColor: '#ddd' }}></div>
          <span style={{ padding: '0 10px', color: '#888' }}>OR</span>
          <div style={{ flex: 1, height: '1px', backgroundColor: '#ddd' }}></div>
        </div>

        <div id="google-signin-button" style={{ display: 'flex', justifyContent: 'center' }}></div>
      </div>
    </div>
  );
};

export default LoginPage;
