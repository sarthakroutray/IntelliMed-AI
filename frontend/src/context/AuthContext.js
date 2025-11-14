import React, { createContext, useState, useContext, useEffect } from 'react';
import { login as apiLogin, register as apiRegister, googleLogin as apiGoogleLogin } from '../services/api';
import { jwtDecode } from 'jwt-decode'; // Corrected import

const AuthContext = createContext(null);

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(localStorage.getItem('token'));

  useEffect(() => {
    if (token) {
      try {
        const decoded = jwtDecode(token);
        // In a real app, you would fetch the user profile from the backend
        // to get the role and other details.
        // For the prototype, we'll infer the role for the hardcoded admin.
        const role = decoded.sub === 'admin@intellimed.ai' ? 'doctor' : 'patient';
        setUser({ email: decoded.sub, role: role });
      } catch (error) {
        console.error("Invalid token", error);
        logout();
      }
    }
  }, [token]);

  const login = async (email, password) => {
    const response = await apiLogin(email, password);
    const { access_token } = response.data;
    setToken(access_token);
    localStorage.setItem('token', access_token);
    const decoded = jwtDecode(access_token);
    const role = decoded.sub === 'admin@intellimed.ai' ? 'doctor' : 'patient';
    setUser({ email: decoded.sub, role: role });
  };

  const googleLogin = async (googleToken) => {
    const response = await apiGoogleLogin(googleToken);
    const { access_token } = response.data;
    setToken(access_token);
    localStorage.setItem('token', access_token);
    const decoded = jwtDecode(access_token);
    // Google login users are assigned doctor role by default
    setUser({ email: decoded.sub, role: 'doctor' });
  };

  const register = async (email, password, role) => {
    await apiRegister(email, password, role);
    // Optionally log in the user directly after registration
  };

  const logout = () => {
    setUser(null);
    setToken(null);
    localStorage.removeItem('token');
  };

  return (
    <AuthContext.Provider value={{ user, token, login, logout, register, googleLogin }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
