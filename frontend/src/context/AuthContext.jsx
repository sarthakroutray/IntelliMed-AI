import React, { createContext, useState, useContext, useEffect } from 'react';
import { login as apiLogin, register as apiRegister, googleLogin as apiGoogleLogin } from '../services/api.js';
import { jwtDecode } from 'jwt-decode'; // Corrected import

const AuthContext = createContext(null);

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(localStorage.getItem('token'));
  const [loading, setLoading] = useState(true);
  const [darkMode, setDarkMode] = useState(() => {
    // Check localStorage first, then check system preference
    const saved = localStorage.getItem('darkMode');
    if (saved !== null) {
      return saved === 'true';
    }
    // Check system preference
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  });

  // Apply dark mode to document
  useEffect(() => {
    if (darkMode) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
    localStorage.setItem('darkMode', darkMode);
  }, [darkMode]);

  useEffect(() => {
    if (token) {
      try {
        const decoded = jwtDecode(token);
        // Get role from token - if missing, clear token (old token without role)
        if (!decoded.role) {
          console.warn('Token missing role field - clearing old token');
          logout();
          return;
        }
        const role = decoded.role;
        setUser({ email: decoded.sub, role: role });
      } catch (error) {
        console.error("Invalid token", error);
        logout();
      }
    }
    setLoading(false);
  }, [token]);

  const login = async (email, password) => {
    const response = await apiLogin(email, password);
    const { access_token } = response.data;
    setToken(access_token);
    localStorage.setItem('token', access_token);
    const decoded = jwtDecode(access_token);
    const role = decoded.role || 'patient';
    setUser({ email: decoded.sub, role: role });
    return { access_token, role, email: decoded.sub };
  };

  const googleLogin = async (googleToken, role) => {
    const response = await apiGoogleLogin(googleToken, role);
    const { access_token } = response.data;
    setToken(access_token);
    localStorage.setItem('token', access_token);
    const decoded = jwtDecode(access_token);
    const userRole = decoded.role || 'doctor';
    setUser({ email: decoded.sub, role: userRole });
  };

  const register = async (email, password, role, doctorAccessCode) => {
    await apiRegister(email, password, role, doctorAccessCode);
    // Optionally log in the user directly after registration
  };

  const logout = () => {
    localStorage.removeItem('token');
    setToken(null);
    setUser(null);
  };

  const toggleDarkMode = () => {
    setDarkMode(!darkMode);
  };

  return (
    <AuthContext.Provider value={{ user, token, login, logout, register, googleLogin, loading, darkMode, toggleDarkMode }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
