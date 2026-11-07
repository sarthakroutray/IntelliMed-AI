import React, { useState } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import Icon from '../components/Icon';
import LinkPatient from '../components/LinkPatient';

// Import pages
import DoctorOverview from './DoctorOverview';
import DoctorPatients from './DoctorPatients';
import AllDocuments from './AllDocuments';
import AIAnalysis from './AIAnalysis';

const NAV_ITEMS = [
  { tab: 'overview', label: 'Dashboard', icon: 'dashboard', path: '/dashboard/overview' },
  { tab: 'patients', label: 'Patients', icon: 'group', path: '/dashboard/patients' },
  { tab: 'documents', label: 'Documents', icon: 'folder_open', path: '/dashboard/documents' },
  { tab: 'ai-analysis', label: 'AI Analysis', icon: 'auto_awesome', path: '/dashboard/ai-analysis' },
];

const navButtonClass = (active) =>
  `flex items-center gap-3 px-4 py-2.5 border-l-2 transition-colors text-left ${
    active
      ? 'border-primary bg-primary/5 text-ink font-semibold'
      : 'border-transparent text-muted hover:bg-surface-2 hover:text-ink font-medium'
  }`;

const BrandMark = ({ className = 'size-8' }) => (
  <svg className={className} fill="none" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M39.5563 34.1455V13.8546C39.5563 15.708 36.8773 17.3437 32.7927 18.3189C30.2914 18.916 27.263 19.2655 24 19.2655C20.737 19.2655 17.7086 18.916 15.2073 18.3189C11.1227 17.3437 8.44365 15.708 8.44365 13.8546V34.1455C8.44365 35.9988 11.1227 37.6346 15.2073 38.6098C17.7086 39.2069 20.737 39.5564 24 39.5564C27.263 39.5564 30.2914 39.2069 32.7927 38.6098C36.8773 37.6346 39.5563 35.9988 39.5563 34.1455Z" fill="currentColor"/>
    <path clipRule="evenodd" d="M10.4485 13.8519C10.4749 13.9271 10.6203 14.246 11.379 14.7361C12.298 15.3298 13.7492 15.9145 15.6717 16.3735C18.0007 16.9296 20.8712 17.2655 24 17.2655C27.1288 17.2655 29.9993 16.9296 32.3283 16.3735C34.2508 15.9145 35.702 15.3298 36.621 14.7361C37.3796 14.246 37.5251 13.9271 37.5515 13.8519C37.5287 13.7876 37.4333 13.5973 37.0635 13.2931C36.5266 12.8516 35.6288 12.3647 34.343 11.9175C31.79 11.0295 28.1333 10.4437 24 10.4437C19.8667 10.4437 16.2099 11.0295 13.657 11.9175C12.3712 12.3647 11.4734 12.8516 10.9365 13.2931C10.5667 13.5973 10.4713 13.7876 10.4485 13.8519ZM37.5563 18.7877C36.3176 19.3925 34.8502 19.8839 33.2571 20.2642C30.5836 20.9025 27.3973 21.2655 24 21.2655C20.6027 21.2655 17.4164 20.9025 14.7429 20.2642C13.1498 19.8839 11.6824 19.3925 10.4436 18.7877V34.1275C10.4515 34.1545 10.5427 34.4867 11.379 35.027C12.298 35.6207 13.7492 36.2054 15.6717 36.6644C18.0007 37.2205 20.8712 37.5564 24 37.5564C27.1288 37.5564 29.9993 37.2205 32.3283 36.6644C34.2508 36.2054 35.702 35.6207 36.621 35.027C37.4573 34.4867 37.5485 34.1546 37.5563 34.1275V18.7877ZM41.5563 13.8546V34.1455C41.5563 36.1078 40.158 37.5042 38.7915 38.3869C37.3498 39.3182 35.4192 40.0389 33.2571 40.5551C30.5836 41.1934 27.3973 41.5564 24 41.5564C20.6027 41.5564 17.4164 41.1934 14.7429 40.5551C12.5808 40.0389 10.6502 39.3182 9.20848 38.3869C7.84205 37.5042 6.44365 36.1078 6.44365 34.1455L6.44365 13.8546C6.44365 12.2684 7.37223 11.0454 8.39581 10.2036C9.43325 9.3505 10.8137 8.67141 12.343 8.13948C15.4203 7.06909 19.5418 6.44366 24 6.44366C28.4582 6.44366 32.5797 7.06909 35.657 8.13948C37.1863 8.67141 38.5667 9.3505 39.6042 10.2036C40.6278 11.0454 41.5563 12.2684 41.5563 13.8546Z" fill="currentColor" fillRule="evenodd"/>
  </svg>
);

const DoctorDashboardLayout = () => {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [showLinkModal, setShowLinkModal] = useState(false);
  const [activeTab, setActiveTab] = useState('overview'); // overview, patients, documents, ai-analysis
  const [showMobileMenu, setShowMobileMenu] = useState(false);

  const handleNavigate = (path, tab) => {
    setActiveTab(tab);
    navigate(path);
    setShowMobileMenu(false);
  };

  return (
    <div className="flex h-screen w-full bg-canvas font-sans">
      {/* Sidebar */}
      <aside className="w-64 flex-shrink-0 bg-surface border-r border-line flex flex-col z-20 hidden md:flex">
        {/* Logo */}
        <div className="flex items-center gap-3 px-6 py-5 border-b border-line">
          <BrandMark className="size-8 text-primary" />
          <h2 className="text-ink font-serif text-lg font-semibold leading-none">
            IntelliMed
            <span className="ledger-label text-muted ml-1.5 align-middle">AI</span>
          </h2>
        </div>

        {/* Navigation */}
        <nav className="flex flex-col py-3 flex-1 overflow-y-auto">
          {NAV_ITEMS.map((item) => (
            <button type="button"
              key={item.tab}
              className={navButtonClass(activeTab === item.tab)}
              onClick={() => handleNavigate(item.path, item.tab)}
            >
              <Icon name={item.icon} filled={activeTab === item.tab} className="text-[20px]" />
              <span className="text-sm leading-normal">
                {item.label}
              </span>
            </button>
          ))}
        </nav>

        {/* Bottom Settings */}
        <div className="p-4 border-t border-line">
          <button type="button" onClick={logout} className={`${navButtonClass(false)} w-full`}>
            <Icon name="logout" className="text-[20px]" />
            <span className="text-sm leading-normal">Logout</span>
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0 bg-canvas overflow-hidden">
        {/* Mobile Header */}
        <div className="md:hidden flex items-center justify-between p-4 bg-surface border-b border-line sticky top-0 z-20">
          <h2 className="font-serif text-lg font-semibold text-ink">IntelliMed-AI</h2>
          <button type="button"
            onClick={() => setShowMobileMenu(!showMobileMenu)}
            className="text-muted p-2"
          >
            <Icon name={showMobileMenu ? 'close' : 'menu'} />
          </button>
        </div>

        {/* Mobile Menu */}
        {showMobileMenu && (
          <div className="md:hidden bg-surface border-b border-line py-2 sticky top-16 z-10">
            {NAV_ITEMS.map((item) => (
              <button type="button"
                key={item.tab}
                className={`w-full ${navButtonClass(activeTab === item.tab)}`}
                onClick={() => handleNavigate(item.path, item.tab)}
              >
                <Icon name={item.icon} className="text-[20px]" />
                <span className="text-sm">{item.label}</span>
              </button>
            ))}

            <div className="border-t border-line mt-2">
              <button type="button"
                onClick={() => {
                  setShowLinkModal(true);
                  setShowMobileMenu(false);
                }}
                className="w-full flex items-center gap-2 px-4 py-3 text-primary hover:bg-primary/5 text-sm font-semibold transition-colors"
              >
                <Icon name="add_link" className="text-[18px]" />
                Link patient
              </button>

              <button type="button"
                onClick={logout}
                className="w-full flex items-center gap-2 px-4 py-3 text-danger hover:bg-danger/10 text-sm font-semibold transition-colors"
              >
                <Icon name="logout" className="text-[18px]" />
                Logout
              </button>
            </div>
          </div>
        )}

        {/* Top Header */}
        <header className="hidden md:flex h-14 items-center justify-between px-8 bg-surface border-b border-line sticky top-0 z-10">
          <nav aria-label="Breadcrumb" className="flex items-center gap-2">
            <button type="button"
              className="ledger-label text-muted hover:text-primary transition-colors cursor-pointer"
              onClick={() => handleNavigate('/dashboard/overview', 'overview')}
            >
              Dashboard
            </button>
            <span className="text-subtle text-sm">/</span>
            <span className="ledger-label text-ink">
              {activeTab.replace('-', ' ')}
            </span>
          </nav>

          {/* Right Side Actions */}
          <div className="flex items-center gap-4">
            {/* Link Patient Button (for doctor) */}
            {activeTab === 'patients' && (
              <button type="button"
                onClick={() => setShowLinkModal(true)}
                className="flex items-center gap-2 h-9 px-4 rounded bg-primary hover:bg-primary-strong border border-primary-strong text-white font-semibold text-[13px] transition-colors"
              >
                <Icon name="link" className="text-[18px]" />
                Link patient
              </button>
            )}

            {/* Notifications */}
            <button type="button" aria-label="Notifications"
              className="relative flex items-center justify-center size-9 rounded hover:bg-surface-2 text-muted transition-colors">
              <Icon name="notifications" className="text-[22px]" />
              <span className="absolute top-1.5 right-1.5 size-1.5 rounded-full bg-danger ring-2 ring-surface"></span>
            </button>

            {/* User Profile */}
            <div className="flex items-center gap-3 pl-4 border-l border-line">
              <div className="flex-col items-end hidden sm:flex">
                <span className="text-sm font-semibold text-ink leading-none">
                  Dr. {user?.email?.split('@')[0]}
                </span>
                <span className="ledger-label text-muted mt-1.5">Physician</span>
              </div>
              <div className="relative">
                <div className="bg-primary flex items-center justify-center rounded size-9 text-white font-semibold text-sm">
                  {user?.email?.charAt(0).toUpperCase()}
                </div>
                <span className="absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full bg-success ring-2 ring-surface"></span>
              </div>
            </div>
          </div>
        </header>

        {/* Page Content */}
        <Routes>
          <Route path="/" element={<Navigate to="overview" replace />} />
          <Route path="overview" element={<DoctorOverview />} />
          <Route path="patients" element={<DoctorPatients />} />
          <Route path="documents" element={<AllDocuments />} />
          <Route path="ai-analysis" element={<AIAnalysis />} />
        </Routes>
      </main>

      {/* Link Patient Modal */}
      {showLinkModal && (
        <div className="fixed inset-0 bg-ink/50 backdrop-blur-[2px] flex items-center justify-center z-50 p-4">
          <LinkPatient
            onClose={() => setShowLinkModal(false)}
            onPatientLinked={() => {
              setShowLinkModal(false);
              // Optionally refresh data
            }}
          />
        </div>
      )}
    </div>
  );
};

export default DoctorDashboardLayout;
