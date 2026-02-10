import React, { useState, useEffect, useCallback } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import Icon from '../components/Icon';
import GenerateAccessCode from '../components/GenerateAccessCode';
import { getLinkedDoctors } from '../services/api';

// Import pages
import PatientDashboard from './PatientDashboard';
import Profile from './Profile';
import Settings from './Settings';
import AIAnalysis from './AIAnalysis';

const PatientDashboardLayout = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState('dashboard');
  const [showGenerateCodeModal, setShowGenerateCodeModal] = useState(false);
  const [showMobileMenu, setShowMobileMenu] = useState(false);
  const [linkedDoctors, setLinkedDoctors] = useState([]);
  const [loadingDoctors, setLoadingDoctors] = useState(false);

  const fetchLinkedDoctors = useCallback(async () => {
    if (!user) return;
    try {
      setLoadingDoctors(true);
      const response = await getLinkedDoctors();
      setLinkedDoctors(response.data);
    } catch (err) {
      console.error('Failed to fetch linked doctors:', err);
      setLinkedDoctors([]);
    } finally {
      setLoadingDoctors(false);
    }
  }, [user]);

  useEffect(() => {
    fetchLinkedDoctors();
  }, [fetchLinkedDoctors]);

  const handleNavigate = (path, tab) => {
    setActiveTab(tab);
    navigate(path);
    setShowMobileMenu(false);
  };

  return (
    <div className="flex h-screen w-full flex-row overflow-hidden bg-background-light dark:bg-background-dark font-display">
      {/* Sidebar */}
      <aside className="w-72 shrink-0 border-r border-[#dbdfe6] dark:border-gray-800 bg-white dark:bg-[#1A202C] flex flex-col h-full overflow-y-auto hidden md:flex">
        <div className="p-6 flex flex-col gap-6 flex-1">
          {/* Logo */}
          <div className="flex items-center gap-3 pb-4 border-b border-[#dbdfe6] dark:border-gray-700">
            <div className="size-8 text-primary">
              <svg className="w-full h-full" fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
                <path d="M39.5563 34.1455V13.8546C39.5563 15.708 36.8773 17.3437 32.7927 18.3189C30.2914 18.916 27.263 19.2655 24 19.2655C20.737 19.2655 17.7086 18.916 15.2073 18.3189C11.1227 17.3437 8.44365 15.708 8.44365 13.8546V34.1455C8.44365 35.9988 11.1227 37.6346 15.2073 38.6098C17.7086 39.2069 20.737 39.5564 24 39.5564C27.263 39.5564 30.2914 39.2069 32.7927 38.6098C36.8773 37.6346 39.5563 35.9988 39.5563 34.1455Z" fill="currentColor"/>
                <path clipRule="evenodd" d="M10.4485 13.8519C10.4749 13.9271 10.6203 14.246 11.379 14.7361C12.298 15.3298 13.7492 15.9145 15.6717 16.3735C18.0007 16.9296 20.8712 17.2655 24 17.2655C27.1288 17.2655 29.9993 16.9296 32.3283 16.3735C34.2508 15.9145 35.702 15.3298 36.621 14.7361C37.3796 14.246 37.5251 13.9271 37.5515 13.8519C37.5287 13.7876 37.4333 13.5973 37.0635 13.2931C36.5266 12.8516 35.6288 12.3647 34.343 11.9175C31.79 11.0295 28.1333 10.4437 24 10.4437C19.8667 10.4437 16.2099 11.0295 13.657 11.9175C12.3712 12.3647 11.4734 12.8516 10.9365 13.2931C10.5667 13.5973 10.4713 13.7876 10.4485 13.8519ZM37.5563 18.7877C36.3176 19.3925 34.8502 19.8839 33.2571 20.2642C30.5836 20.9025 27.3973 21.2655 24 21.2655C20.6027 21.2655 17.4164 20.9025 14.7429 20.2642C13.1498 19.8839 11.6824 19.3925 10.4436 18.7877V34.1275C10.4515 34.1545 10.5427 34.4867 11.379 35.027C12.298 35.6207 13.7492 36.2054 15.6717 36.6644C18.0007 37.2205 20.8712 37.5564 24 37.5564C27.1288 37.5564 29.9993 37.2205 32.3283 36.6644C34.2508 36.2054 35.702 35.6207 36.621 35.027C37.4573 34.4867 37.5485 34.1546 37.5563 34.1275V18.7877ZM41.5563 13.8546V34.1455C41.5563 36.1078 40.158 37.5042 38.7915 38.3869C37.3498 39.3182 35.4192 40.0389 33.2571 40.5551C30.5836 41.1934 27.3973 41.5564 24 41.5564C20.6027 41.5564 17.4164 41.1934 14.7429 40.5551C12.5808 40.0389 10.6502 39.3182 9.20848 38.3869C7.84205 37.5042 6.44365 36.1078 6.44365 34.1455L6.44365 13.8546C6.44365 12.2684 7.37223 11.0454 8.39581 10.2036C9.43325 9.3505 10.8137 8.67141 12.343 8.13948C15.4203 7.06909 19.5418 6.44366 24 6.44366C28.4582 6.44366 32.5797 7.06909 35.657 8.13948C37.1863 8.67141 38.5667 9.3505 39.6042 10.2036C40.6278 11.0454 41.5563 12.2684 41.5563 13.8546Z" fill="currentColor" fillRule="evenodd"/>
              </svg>
            </div>
            <h2 className="text-[#111318] dark:text-white text-lg font-bold leading-tight tracking-[-0.015em]">IntelliMed-AI</h2>
          </div>

          {/* Profile */}
          <div className="flex gap-4 items-center">
            <div className="bg-primary flex items-center justify-center rounded-full size-12 relative text-white font-bold text-lg">
              {user?.email?.charAt(0).toUpperCase()}
              <div className="absolute bottom-0 right-0 size-3 bg-green-500 border-2 border-white dark:border-[#1A202C] rounded-full"></div>
            </div>
            <div className="flex flex-col">
              <h1 className="text-base font-bold leading-tight dark:text-white">{user?.email?.split('@')[0]}</h1>
              <p className="text-[#616f89] dark:text-gray-400 text-xs font-medium">ID: {user?.id || 'N/A'}</p>
            </div>
          </div>
          
          {/* Navigation */}
          <div className="flex flex-col gap-1">
            <button 
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'dashboard'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard', 'dashboard')}
            >
              <Icon name="dashboard" />
              <p className={`text-sm ${activeTab === 'dashboard' ? 'font-bold' : 'font-medium'}`}>Dashboard</p>
            </button>

            <button 
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'profile'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/profile', 'profile')}
            >
              <Icon name="person" />
              <p className={`text-sm ${activeTab === 'profile' ? 'font-bold' : 'font-medium'}`}>Profile</p>
            </button>

            <button 
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'ai-analysis'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/ai-analysis', 'ai-analysis')}
            >
              <Icon name="auto_awesome" />
              <p className={`text-sm ${activeTab === 'ai-analysis' ? 'font-bold' : 'font-medium'}`}>AI Analysis</p>
            </button>

            <button 
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'settings'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/settings', 'settings')}
            >
              <Icon name="settings" />
              <p className={`text-sm ${activeTab === 'settings' ? 'font-bold' : 'font-medium'}`}>Settings</p>
            </button>
          </div>
          
          <hr className="border-[#dbdfe6] dark:border-gray-700 my-2" />
          
          {/* Connected Doctors */}
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between px-3">
              <h2 className="text-xs font-bold text-[#616f89] dark:text-gray-500 uppercase tracking-wider">Connected Doctors</h2>
              {linkedDoctors.length > 0 && (
                <span className="px-2 py-0.5 bg-primary/10 text-primary text-xs font-bold rounded-full">{linkedDoctors.length}</span>
              )}
            </div>
            
            {loadingDoctors ? (
              <div className="flex items-center justify-center py-4">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-primary"></div>
              </div>
            ) : linkedDoctors.length === 0 ? (
              <div className="px-3 py-2 text-xs text-[#616f89] dark:text-gray-500">
                No doctors connected yet
              </div>
            ) : (
              <div className="flex flex-col gap-2 max-h-48 overflow-y-auto">
                {linkedDoctors.map((doctor) => (
                  <div 
                    key={doctor.id} 
                    className="flex items-center gap-2 px-3 py-2 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-lg transition-colors"
                  >
                    <div className="size-8 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center flex-shrink-0">
                      <Icon name="person" className="text-white text-[16px]" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-bold text-[#111318] dark:text-white truncate">
                        Dr. {doctor.email?.split('@')[0]}
                      </p>
                      <div className="flex items-center gap-1">
                        <div className="size-1.5 rounded-full bg-green-500"></div>
                        <span className="text-xs text-green-600 dark:text-green-400">Active</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
            
            <button 
              onClick={() => setShowGenerateCodeModal(true)}
              className="flex items-center gap-2 px-3 py-2 text-primary hover:text-primary/80 hover:bg-primary/5 rounded-lg text-sm font-medium transition-colors mt-1"
            >
              <Icon name="add_link" className="text-[18px]" />
              Connect with Doctor
            </button>
          </div>
        </div>
        
        <div className="p-6 mt-auto">
          <button onClick={logout} className="flex w-full items-center justify-center gap-2 rounded-lg h-10 px-4 bg-gray-100 dark:bg-gray-800 hover:bg-gray-200 dark:hover:bg-gray-700 text-[#111318] dark:text-white text-sm font-bold transition-colors">
            <Icon name="logout" className="text-[18px]" />
            <span>Logout</span>
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col h-full overflow-y-auto bg-background-light dark:bg-background-dark relative">
        {/* Mobile Header */}
        <div className="md:hidden flex items-center justify-between p-4 bg-white dark:bg-[#1A202C] border-b border-gray-200 dark:border-gray-700 sticky top-0 z-20">
          <div className="flex items-center gap-3">
            <div className="bg-primary flex items-center justify-center rounded-full size-8 text-white font-bold text-sm">
              {user?.email?.charAt(0).toUpperCase()}
            </div>
            <span className="font-bold text-sm truncate">{user?.email?.split('@')[0]}</span>
          </div>
          <button 
            onClick={() => setShowMobileMenu(!showMobileMenu)}
            className="text-gray-500 dark:text-gray-400 p-2"
          >
            <Icon name={showMobileMenu ? 'close' : 'menu'} />
          </button>
        </div>

        {/* Mobile Menu */}
        {showMobileMenu && (
          <div className="md:hidden bg-white dark:bg-[#1A202C] border-b border-gray-200 dark:border-gray-700 p-4 space-y-2 sticky top-16 z-10">
            <button 
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'dashboard'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard', 'dashboard')}
            >
              <Icon name="dashboard" />
              <p className="text-sm font-medium">Dashboard</p>
            </button>

            <button 
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'profile'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/profile', 'profile')}
            >
              <Icon name="person" />
              <p className="text-sm font-medium">Profile</p>
            </button>

            <button 
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'ai-analysis'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/ai-analysis', 'ai-analysis')}
            >
              <Icon name="auto_awesome" />
              <p className="text-sm font-medium">AI Analysis</p>
            </button>

            <button 
              className={`w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left transition-colors ${
                activeTab === 'settings'
                  ? 'bg-primary/10 text-primary'
                  : 'hover:bg-gray-100 dark:hover:bg-gray-800 text-[#616f89] dark:text-gray-400'
              }`}
              onClick={() => handleNavigate('/patient-dashboard/settings', 'settings')}
            >
              <Icon name="settings" />
              <p className="text-sm font-medium">Settings</p>
            </button>

            <hr className="border-gray-200 dark:border-gray-700 my-2" />

            {/* Connected Doctors in Mobile */}
            {linkedDoctors.length > 0 && (
              <>
                <div className="px-3 py-2">
                  <p className="text-xs font-bold text-[#616f89] dark:text-gray-500 uppercase tracking-wider mb-2">
                    Connected Doctors ({linkedDoctors.length})
                  </p>
                  <div className="space-y-2">
                    {linkedDoctors.slice(0, 3).map((doctor) => (
                      <div 
                        key={doctor.id}
                        className="flex items-center gap-2 py-1"
                      >
                        <div className="size-6 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center flex-shrink-0">
                          <Icon name="person" className="text-white text-[12px]" />
                        </div>
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-bold text-[#111318] dark:text-white truncate">
                            Dr. {doctor.email?.split('@')[0]}
                          </p>
                        </div>
                        <div className="size-1.5 rounded-full bg-green-500"></div>
                      </div>
                    ))}
                    {linkedDoctors.length > 3 && (
                      <p className="text-xs text-[#616f89] dark:text-gray-400 pl-8">
                        +{linkedDoctors.length - 3} more
                      </p>
                    )}
                  </div>
                </div>
                <hr className="border-gray-200 dark:border-gray-700 my-2" />
              </>
            )}

            <button 
              onClick={() => {
                setShowGenerateCodeModal(true);
                setShowMobileMenu(false);
              }}
              className="w-full flex items-center gap-2 px-3 py-2 text-primary hover:text-primary/80 hover:bg-primary/5 rounded-lg text-sm font-medium transition-colors"
            >
              <Icon name="add_link" className="text-[18px]" />
              Connect with Doctor
            </button>

            <button 
              onClick={logout}
              className="w-full flex items-center gap-2 px-3 py-2 text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg text-sm font-medium transition-colors"
            >
              <Icon name="logout" className="text-[18px]" />
              Logout
            </button>
          </div>
        )}

        {/* Page Content */}
        <Routes>
          <Route path="/" element={<PatientDashboard />} />
          <Route path="profile" element={<Profile />} />
          <Route path="settings" element={<Settings />} />
          <Route path="ai-analysis" element={<AIAnalysis />} />
        </Routes>
      </main>

      {/* Generate Access Code Modal */}
      {showGenerateCodeModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowGenerateCodeModal(false)}>
          <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xl font-bold text-[#111318] dark:text-white">Connect with Doctor</h3>
              <button onClick={() => setShowGenerateCodeModal(false)} className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors">
                <Icon name="close" className="text-[24px]" />
              </button>
            </div>
            <GenerateAccessCode />
          </div>
        </div>
      )}
    </div>
  );
};

export default PatientDashboardLayout;
