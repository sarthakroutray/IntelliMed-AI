import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext.jsx';

const Navbar = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    setTimeout(() => {
      navigate('/login', { replace: true });
    }, 0);
  };

  return (
    <nav className="navbar">
      <Link to="/" className="text-3xl font-bold" style={{ background: 'linear-gradient(to right, #4e54c8, #8f94fb)', WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' }}>
        IntelliMed AI
      </Link>
      <div className="nav-links">
        {user ? (
          <>
            <Link to="/dashboard">Dashboard            </Link>
            <button onClick={handleLogout} className="btn">Logout</button>
          </>
        ) : (
          <Link to="/login" className="btn">Login</Link>
        )}
      </div>
    </nav>
  );
};

export default Navbar;
