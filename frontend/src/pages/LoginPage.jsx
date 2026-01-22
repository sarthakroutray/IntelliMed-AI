import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

const LoginPage = () => {
  const [selectedRole, setSelectedRole] = useState('patient');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const { googleLogin } = useAuth();
  const navigate = useNavigate();

  const handleGoogleLogin = useCallback(
    (response) => {
      setLoading(true);
      setError('');
      googleLogin(response.credential, selectedRole)
        .then(() => {
          navigate('/dashboard');
        })
        .catch((err) => {
          const errorMessage = err.response?.data?.detail || 'Google login failed. Please try again.';
          
          // If account exists with different role, provide helpful message
          if (err.response?.status === 403 && errorMessage.includes('registered as')) {
            const oppositeRole = selectedRole === 'patient' ? 'doctor' : 'patient';
            setError(`${errorMessage} Try logging in as a ${oppositeRole} instead.`);
          } else {
            setError(errorMessage);
          }
        })
        .finally(() => {
          setLoading(false);
        });
    },
    [googleLogin, navigate, selectedRole]
  );

  useEffect(() => {
    const initializeGoogleSignIn = () => {
      if (window.google && document.getElementById('googleSignInDiv')) {
        // Clear previous button
        const signInDiv = document.getElementById('googleSignInDiv');
        signInDiv.innerHTML = '';
        
        window.google.accounts.id.initialize({
          client_id: import.meta.env.VITE_GOOGLE_CLIENT_ID,
          callback: handleGoogleLogin,
        });
        window.google.accounts.id.renderButton(
          signInDiv,
          { 
            theme: 'outline', 
            size: 'large', 
            text: 'signin_with',
            width: '100%',
            logo_alignment: 'left'
          }
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

  return (
    <div className="relative flex min-h-screen w-full flex-col justify-center bg-[#EBF2FE] dark:bg-slate-900 py-6 sm:py-12">
      {/* Abstract Background Pattern */}
      <div className="absolute inset-0 bg-[url('https://www.transparenttextures.com/patterns/cubes.png')] opacity-[0.03] dark:opacity-[0.05]"></div>
      <div className="absolute -top-24 -left-24 w-96 h-96 bg-primary/20 rounded-full blur-3xl pointer-events-none"></div>
      <div className="absolute -bottom-24 -right-24 w-96 h-96 bg-primary/10 rounded-full blur-3xl pointer-events-none"></div>
      
      <div className="relative w-full max-w-md mx-auto px-4">
        {/* Login Card */}
        <div className="group/design-root relative overflow-hidden rounded-2xl bg-white dark:bg-[#1A202C] shadow-2xl ring-1 ring-gray-900/5 dark:ring-white/10">
          {/* Decorative Top Bar */}
          <div className="h-2 w-full bg-primary"></div>
          
          <div className="p-8 sm:p-10 flex flex-col items-center">
            {/* Branding (Logo) */}
            <div className="mb-6 flex items-center justify-center gap-3">
              <div className="flex items-center justify-center size-10 text-primary bg-primary/10 rounded-lg">
                <svg className="size-6" fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
                  <path d="M39.5563 34.1455V13.8546C39.5563 15.708 36.8773 17.3437 32.7927 18.3189C30.2914 18.916 27.263 19.2655 24 19.2655C20.737 19.2655 17.7086 18.916 15.2073 18.3189C11.1227 17.3437 8.44365 15.708 8.44365 13.8546V34.1455C8.44365 35.9988 11.1227 37.6346 15.2073 38.6098C17.7086 39.2069 20.737 39.5564 24 39.5564C27.263 39.5564 30.2914 39.2069 32.7927 38.6098C36.8773 37.6346 39.5563 35.9988 39.5563 34.1455Z" fill="currentColor"/>
                  <path clipRule="evenodd" d="M10.4485 13.8519C10.4749 13.9271 10.6203 14.246 11.379 14.7361C12.298 15.3298 13.7492 15.9145 15.6717 16.3735C18.0007 16.9296 20.8712 17.2655 24 17.2655C27.1288 17.2655 29.9993 16.9296 32.3283 16.3735C34.2508 15.9145 35.702 15.3298 36.621 14.7361C37.3796 14.246 37.5251 13.9271 37.5515 13.8519C37.5287 13.7876 37.4333 13.5973 37.0635 13.2931C36.5266 12.8516 35.6288 12.3647 34.343 11.9175C31.79 11.0295 28.1333 10.4437 24 10.4437C19.8667 10.4437 16.2099 11.0295 13.657 11.9175C12.3712 12.3647 11.4734 12.8516 10.9365 13.2931C10.5667 13.5973 10.4713 13.7876 10.4485 13.8519ZM37.5563 18.7877C36.3176 19.3925 34.8502 19.8839 33.2571 20.2642C30.5836 20.9025 27.3973 21.2655 24 21.2655C20.6027 21.2655 17.4164 20.9025 14.7429 20.2642C13.1498 19.8839 11.6824 19.3925 10.4436 18.7877V34.1275C10.4515 34.1545 10.5427 34.4867 11.379 35.027C12.298 35.6207 13.7492 36.2054 15.6717 36.6644C18.0007 37.2205 20.8712 37.5564 24 37.5564C27.1288 37.5564 29.9993 37.2205 32.3283 36.6644C34.2508 36.2054 35.702 35.6207 36.621 35.027C37.4573 34.4867 37.5485 34.1546 37.5563 34.1275V18.7877ZM41.5563 13.8546V34.1455C41.5563 36.1078 40.158 37.5042 38.7915 38.3869C37.3498 39.3182 35.4192 40.0389 33.2571 40.5551C30.5836 41.1934 27.3973 41.5564 24 41.5564C20.6027 41.5564 17.4164 41.1934 14.7429 40.5551C12.5808 40.0389 10.6502 39.3182 9.20848 38.3869C7.84205 37.5042 6.44365 36.1078 6.44365 34.1455L6.44365 13.8546C6.44365 12.2684 7.37223 11.0454 8.39581 10.2036C9.43325 9.3505 10.8137 8.67141 12.343 8.13948C15.4203 7.06909 19.5418 6.44366 24 6.44366C28.4582 6.44366 32.5797 7.06909 35.657 8.13948C37.1863 8.67141 38.5667 9.3505 39.6042 10.2036C40.6278 11.0454 41.5563 12.2684 41.5563 13.8546Z" fill="currentColor" fillRule="evenodd"/>
                </svg>
              </div>
              <h2 className="text-2xl font-extrabold tracking-tight text-[#111318] dark:text-white">IntelliMed-AI</h2>
            </div>
            
            {/* Headlines */}
            <div className="text-center w-full mb-8">
              <h1 className="text-[#111318] dark:text-white tracking-tight text-[28px] font-bold leading-tight pb-3">
                Welcome Back
              </h1>
              <p className="text-[#616f89] dark:text-gray-400 text-sm font-normal leading-normal px-4">
                Sign in to your account
              </p>
            </div>

            {/* Role Selection Tabs */}
            <div className="w-full flex gap-2 mb-6 p-1 bg-slate-100 dark:bg-slate-800 rounded-lg">
              <button
                type="button"
                onClick={() => setSelectedRole('patient')}
                className={`flex-1 py-2.5 px-4 rounded-md text-sm font-bold transition-all ${
                  selectedRole === 'patient'
                    ? 'bg-white dark:bg-slate-700 text-primary shadow-sm'
                    : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white'
                }`}
              >
                Patient
              </button>
              <button
                type="button"
                onClick={() => setSelectedRole('doctor')}
                className={`flex-1 py-2.5 px-4 rounded-md text-sm font-bold transition-all ${
                  selectedRole === 'doctor'
                    ? 'bg-white dark:bg-slate-700 text-primary shadow-sm'
                    : 'text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white'
                }`}
              >
                Doctor
              </button>
            </div>
            
            {/* Error Message */}
            {error && (
              <div className="w-full mb-4 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
                <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
              </div>
            )}
            <div className="w-full flex justify-center mb-6">
              <div id="googleSignInDiv" className="w-full"></div>
            </div>
            
            {/* Divider */}
            <div className="relative w-full text-center text-sm text-[#616f89] dark:text-gray-500 mb-6 before:absolute before:inset-0 before:top-1/2 before:z-0 before:h-px before:w-full before:bg-[#e2e8f0] dark:before:bg-slate-700">
              <span className="relative z-10 bg-white dark:bg-[#1A202C] px-2 font-medium">or</span>
            </div>
            
            {/* Secondary Actions */}
            <div className="text-center space-y-4 w-full">
              <p className="text-[#616f89] dark:text-gray-400 text-sm font-normal">
                New to IntelliMed? <Link to="/register" className="text-primary font-bold hover:underline">Create an account</Link>
              </p>
              <div className="pt-2">
                <a className="text-[#616f89] dark:text-gray-400 text-xs font-medium hover:text-primary transition-colors" href="mailto:support@intellimed.ai">Contact Support</a>
              </div>
            </div>
            
            {/* HIPAA Trust Badge */}
            <div className="mt-8 w-full">
              <div className="flex flex-col items-center justify-center p-3 rounded-lg bg-[#f0f9ff] dark:bg-primary/10 border border-primary/10 text-center">
                <div className="flex items-center gap-2 mb-1 text-primary">
                  <span className="material-symbols-outlined text-lg">verified_user</span>
                  <span className="text-xs font-bold uppercase tracking-wider">HIPAA Compliant</span>
                </div>
                <p className="text-[11px] text-[#475569] dark:text-gray-400 leading-tight max-w-[280px]">
                  Your data is encrypted and protected in a secure PHI environment.
                </p>
              </div>
              <div className="mt-3 text-center">
                <a className="text-[11px] text-[#94a3b8] dark:text-gray-500 hover:text-primary transition-colors underline decoration-dotted" href="https://intellimed.ai/privacy" target="_blank" rel="noopener noreferrer">Privacy Policy &amp; Terms</a>
              </div>
            </div>
          </div>
        </div>
        
        {/* Simple Footer outside card */}
        <div className="mt-8 text-center">
          <p className="text-[#94a3b8] dark:text-gray-500 text-xs">
            © 2024 IntelliMed-AI. All rights reserved.
          </p>
        </div>
      </div>
    </div>
  );
};

export default LoginPage;
