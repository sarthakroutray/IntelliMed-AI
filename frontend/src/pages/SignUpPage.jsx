import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { Alert, Spinner } from '../components/ui.jsx';
import { ui } from '../styles/ui.js';

const BrandMark = ({ className = 'size-9' }) => (
  <svg className={className} fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M39.5563 34.1455V13.8546C39.5563 15.708 36.8773 17.3437 32.7927 18.3189C30.2914 18.916 27.263 19.2655 24 19.2655C20.737 19.2655 17.7086 18.916 15.2073 18.3189C11.1227 17.3437 8.44365 15.708 8.44365 13.8546V34.1455C8.44365 35.9988 11.1227 37.6346 15.2073 38.6098C17.7086 39.2069 20.737 39.5564 24 39.5564C27.263 39.5564 30.2914 39.2069 32.7927 38.6098C36.8773 37.6346 39.5563 35.9988 39.5563 34.1455Z" fill="currentColor"/>
    <path clipRule="evenodd" d="M10.4485 13.8519C10.4749 13.9271 10.6203 14.246 11.379 14.7361C12.298 15.3298 13.7492 15.9145 15.6717 16.3735C18.0007 16.9296 20.8712 17.2655 24 17.2655C27.1288 17.2655 29.9993 16.9296 32.3283 16.3735C34.2508 15.9145 35.702 15.3298 36.621 14.7361C37.3796 14.246 37.5251 13.9271 37.5515 13.8519C37.5287 13.7876 37.4333 13.5973 37.0635 13.2931C36.5266 12.8516 35.6288 12.3647 34.343 11.9175C31.79 11.0295 28.1333 10.4437 24 10.4437C19.8667 10.4437 16.2099 11.0295 13.657 11.9175C12.3712 12.3647 11.4734 12.8516 10.9365 13.2931C10.5667 13.5973 10.4713 13.7876 10.4485 13.8519ZM37.5563 18.7877C36.3176 19.3925 34.8502 19.8839 33.2571 20.2642C30.5836 20.9025 27.3973 21.2655 24 21.2655C20.6027 21.2655 17.4164 20.9025 14.7429 20.2642C13.1498 19.8839 11.6824 19.3925 10.4436 18.7877V34.1275C10.4515 34.1545 10.5427 34.4867 11.379 35.027C12.298 35.6207 13.7492 36.2054 15.6717 36.6644C18.0007 37.2205 20.8712 37.5564 24 37.5564C27.1288 37.5564 29.9993 37.2205 32.3283 36.6644C34.2508 36.2054 35.702 35.6207 36.621 35.027C37.4573 34.4867 37.5485 34.1546 37.5563 34.1275V18.7877ZM41.5563 13.8546V34.1455C41.5563 36.1078 40.158 37.5042 38.7915 38.3869C37.3498 39.3182 35.4192 40.0389 33.2571 40.5551C30.5836 41.1934 27.3973 41.5564 24 41.5564C20.6027 41.5564 17.4164 41.1934 14.7429 40.5551C12.5808 40.0389 10.6502 39.3182 9.20848 38.3869C7.84205 37.5042 6.44365 36.1078 6.44365 34.1455L6.44365 13.8546C6.44365 12.2684 7.37223 11.0454 8.39581 10.2036C9.43325 9.3505 10.8137 8.67141 12.343 8.13948C15.4203 7.06909 19.5418 6.44366 24 6.44366C28.4582 6.44366 32.5797 7.06909 35.657 8.13948C37.1863 8.67141 38.5667 9.3505 39.6042 10.2036C40.6278 11.0454 41.5563 12.2684 41.5563 13.8546Z" fill="currentColor" fillRule="evenodd"/>
  </svg>
);

const SignUpPage = () => {
  const [activeTab, setActiveTab] = useState('patient');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [doctorAccessCode, setDoctorAccessCode] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const { register, googleLogin } = useAuth();
  const navigate = useNavigate();

  const handleGoogleSignup = useCallback(
    (response) => {
      setLoading(true);
      setError('');
      googleLogin(response.credential, activeTab)
        .then(() => {
          navigate('/dashboard');
        })
        .catch((err) => {
          const errorMessage = err.response?.data?.detail || 'Google signup failed. Please try again.';
          
          // If account exists with different role, provide helpful message
          if (err.response?.status === 403 && errorMessage.includes('registered as')) {
            const oppositeRole = activeTab === 'patient' ? 'doctor' : 'patient';
            setError(`${errorMessage} Already have an account? Try signing in as a ${oppositeRole} or go to the login page.`);
          } else {
            setError(errorMessage);
          }
        })
        .finally(() => {
          setLoading(false);
        });
    },
    [googleLogin, navigate, activeTab]
  );

  useEffect(() => {
    const initializeGoogleSignIn = () => {
      const holder = document.getElementById('googleSignupDiv');
      if (window.google && holder) {
        const width = Math.min(holder.clientWidth || 320, 350);
        holder.innerHTML = '';
        window.google.accounts.id.initialize({
          client_id: import.meta.env.VITE_GOOGLE_CLIENT_ID,
          callback: handleGoogleSignup,
        });
        window.google.accounts.id.renderButton(holder, {
          theme: 'filled_black',
          size: 'large',
          text: 'signup_with',
          shape: 'pill',
          width,
        });
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
  }, [handleGoogleSignup]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    if (password.length < 8) {
      setError('Password must be at least 8 characters long.');
      return;
    }

    setLoading(true);
    try {
      await register(email, password, activeTab, doctorAccessCode);
      navigate('/login');
    } catch (err) {
      setError(err.response?.data?.detail || 'Registration failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen w-full flex bg-canvas">
      {/* Brand panel — deep pine, invariant across light/dark */}
      <aside className="hidden lg:flex lg:w-[44%] xl:w-[46%] flex-col justify-between bg-brand text-brand-ink p-12 xl:p-16">
        <div className="flex items-center gap-3">
          <BrandMark className="size-9 text-brand-ink" />
          <h2 className="font-serif text-xl font-semibold leading-none">
            IntelliMed
            <span className="ledger-label text-brand-ink/60 ml-2 align-middle">AI</span>
          </h2>
        </div>

        <div>
          <p className="ledger-label text-brand-ink/55">Medical records · AI analysis · Doctor review</p>
          <h1 className="font-serif text-[40px] xl:text-[48px] leading-[1.08] font-semibold mt-6">
            Your health history,
            <br />
            in one place.
          </h1>
          <p className="mt-6 text-brand-ink/75 text-[15px] leading-relaxed max-w-[46ch]">
            Create an account to store your medical documents, keep them organized,
            and share them securely with the doctors you choose.
          </p>
        </div>

        <div>
          <ul>
            {[
              ['Security', 'HIPAA-aligned handling, encrypted in transit and at rest.'],
              ['Privacy', 'Documents are shared only with doctors you link to your account.'],
              ['AI use', 'AI output is assistive context for expert review, never a diagnosis.'],
            ].map(([label, text]) => (
              <li key={label} className="border-t border-brand-ink/15 py-4 flex gap-6">
                <span className="ledger-label text-brand-ink/50 w-20 shrink-0 pt-0.5">{label}</span>
                <p className="text-sm text-brand-ink/75 leading-relaxed">{text}</p>
              </li>
            ))}
          </ul>
          <p className="mt-8 text-xs text-brand-ink/45">© 2024 IntelliMed-AI. All rights reserved.</p>
        </div>
      </aside>

      {/* Form column */}
      <main className="flex-1 flex items-center justify-center px-5 py-10 sm:px-10">
        <div className="w-full max-w-[400px] animate-[riseIn_0.25s_ease-out]">
          {/* Compact brand for small screens */}
          <div className="flex items-center gap-3 lg:hidden mb-10">
            <BrandMark className="size-8 text-primary" />
            <h2 className="font-serif text-lg font-semibold text-ink leading-none">
              IntelliMed
              <span className="ledger-label text-muted ml-2 align-middle">AI</span>
            </h2>
          </div>

          <p className="ledger-label text-muted">Create account</p>
          <h1 className="font-serif text-[30px] font-semibold text-ink leading-tight mt-2">
            Create your account
          </h1>
          <p className="text-muted text-[15px] mt-2">
            Join IntelliMed-AI and take control of your health journey.
          </p>

          {/* Role Tabs */}
          <div className="w-full flex gap-2 mt-8 mb-6 p-1 bg-surface-2 rounded">
            {['patient', 'doctor'].map((role) => (
              <button
                key={role}
                type="button"
                onClick={() => setActiveTab(role)}
                className={`flex-1 py-2.5 px-4 rounded text-sm font-semibold capitalize transition-colors ${
                  activeTab === role
                    ? 'bg-surface text-primary border border-line shadow-card'
                    : 'text-muted hover:text-ink border border-transparent'
                }`}
              >
                {role}
              </button>
            ))}
          </div>

          {/* Error Message */}
          {error && (
            <div className="w-full mb-4">
              <Alert type="error">{error}</Alert>
            </div>
          )}
          
          {/* Signup Form */}
          <form onSubmit={handleSubmit} className="w-full flex flex-col gap-4">
            <div>
              <label htmlFor="email" className={`${ui.label}`}>
                Email address
              </label>
              <input
                type="email"
                id="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                required
                disabled={loading}
                className={`${ui.input} disabled:opacity-50 disabled:cursor-not-allowed`}
              />
            </div>
            
            <div>
              <label htmlFor="password" className={`${ui.label}`}>
                Password
              </label>
              <input
                type="password"
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                disabled={loading}
                className={`${ui.input} disabled:opacity-50 disabled:cursor-not-allowed`}
              />
            </div>
            
            <div>
              <label htmlFor="confirmPassword" className={`${ui.label}`}>
                Confirm password
              </label>
              <input
                type="password"
                id="confirmPassword"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="••••••••"
                required
                disabled={loading}
                className={`${ui.input} disabled:opacity-50 disabled:cursor-not-allowed`}
              />
            </div>

            {activeTab === 'doctor' && (
              <div>
                <label htmlFor="doctorAccessCode" className={`${ui.label}`}>
                  Doctor access code
                </label>
                <input
                  type="text"
                  id="doctorAccessCode"
                  value={doctorAccessCode}
                  onChange={(e) => setDoctorAccessCode(e.target.value)}
                  placeholder="Enter your verification code"
                  required
                  disabled={loading}
                  className={`${ui.input} font-mono tracking-wider disabled:opacity-50 disabled:cursor-not-allowed`}
                />
                <p className="mt-1.5 text-xs text-muted">
                  Contact admin for your access code
                </p>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full h-11 mt-2 bg-primary hover:bg-primary-strong text-white font-semibold text-sm rounded border border-primary-strong transition-colors flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <Spinner className="size-5 border-white/30 border-t-white" />
                  <span>Creating account...</span>
                </>
              ) : (
                <>
                  <span>Create account</span>
                  <span className="text-lg leading-none">→</span>
                </>
              )}
            </button>
          </form>

          {/* Divider */}
          <div className="flex items-center w-full my-6">
            <div className="flex-1 border-t border-line"></div>
            <span className="px-4 text-sm text-muted">or</span>
            <div className="flex-1 border-t border-line"></div>
          </div>

          {/* Google Sign In */}
          <div className="w-full flex justify-center">
            <div
              id="googleSignupDiv"
              className="flex justify-center [&>div]:!rounded-full [&>div]:overflow-hidden [&iframe]:!rounded-full [&iframe]:block [&iframe]:!mx-auto"
              style={{ minHeight: 44, colorScheme: 'light' }}
            />
          </div>

          {/* Login Link */}
          <div className="text-center mt-6 w-full">
            <p className="text-muted text-sm">
              Already have an account? <Link to="/login" className="text-primary font-semibold hover:underline">Sign in here</Link>
            </p>
          </div>

          {/* HIPAA Trust Note */}
          <div className="mt-6 w-full border-t border-line pt-5">
            <div className="flex items-start gap-2.5">
              <span className="material-symbols-outlined text-lg text-primary mt-0.5">verified_user</span>
              <div>
                <p className="ledger-label text-ink">HIPAA compliant</p>
                <p className="text-xs text-body leading-relaxed mt-1.5 max-w-[320px]">
                  Your data is encrypted and protected in a secure PHI environment.
                </p>
              </div>
            </div>
          </div>

          <p className="mt-8 text-xs text-subtle lg:hidden text-center">
            © 2024 IntelliMed-AI. All rights reserved.
          </p>
        </div>
      </main>
    </div>
  );
};

export default SignUpPage;
