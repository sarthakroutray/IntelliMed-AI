import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import api from '../services/api';
import Icon from '../components/Icon';

const Settings = () => {
  const { logout, user, darkMode, toggleDarkMode } = useAuth();
  const [notifications, setNotifications] = useState({
    email: true,
    push: false,
    documentUploads: true,
    aiAnalysis: true,
    doctorMessages: true,
    securityAlerts: true
  });
  const [privacy, setPrivacy] = useState({
    shareWithDoctors: true,
    allowAIAnalysis: true,
    dataRetention: '5-years'
  });
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const fetchSettings = async () => {
      try {
        const response = await api.get('/profile');
        const profile = response.data;
        setNotifications({
          email: profile.email_notifications ?? true,
          push: profile.push_notifications ?? false,
          documentUploads: true,
          aiAnalysis: true,
          doctorMessages: true,
          securityAlerts: true
        });
      } catch (err) {
        console.error('Failed to fetch settings', err);
      } finally {
        setLoading(false);
      }
    };

    fetchSettings();
  }, []);

  const handleSaveSettings = async () => {
    setSaving(true);
    try {
      await api.put('/profile', {
        dark_mode: darkMode,
        email_notifications: notifications.email,
        push_notifications: notifications.push
      });
      alert('Settings saved successfully!');
    } catch (err) {
      alert('Failed to save settings: ' + (err.response?.data?.detail || 'Unknown error'));
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteAccount = () => {
    if (window.confirm('Are you absolutely sure? This action cannot be undone.')) {
      alert('Account deletion requested. You will be logged out.');
      logout();
    }
    setShowDeleteModal(false);
  };

  return (
    <div className="flex-1 overflow-y-auto p-4 md:p-8">
      <div className="max-w-[900px] mx-auto flex flex-col gap-6">
        {/* Header */}
        <div>
          <h1 className="text-3xl font-black text-gray-900 dark:text-white mb-2">
            Settings
          </h1>
          <p className="text-gray-500 dark:text-gray-400">
            Manage your account preferences and privacy settings.
          </p>
        </div>

        {/* Appearance */}
        <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
          <div className="p-6 border-b border-gray-200 dark:border-gray-800">
            <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
              <Icon name="palette" className="text-primary" />
              Appearance
            </h2>
          </div>
          <div className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Dark Mode</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Use dark theme across the application</p>
              </div>
              <button
                onClick={() => toggleDarkMode()}
                className={`flex w-11 items-center rounded-full transition-colors ${
                  darkMode ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    darkMode ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          </div>
        </div>

        {/* Notifications */}
        <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
          <div className="p-6 border-b border-gray-200 dark:border-gray-800">
            <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
              <Icon name="notifications" className="text-primary" />
              Notifications
            </h2>
          </div>
          <div className="p-6 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Email Notifications</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Receive notifications via email</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, email: !notifications.email })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.email ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.email ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Push Notifications</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Receive browser push notifications</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, push: !notifications.push })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.push ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.push ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <hr className="border-gray-200 dark:border-gray-700" />

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Document Uploads</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Notify when a document is uploaded</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, documentUploads: !notifications.documentUploads })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.documentUploads ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.documentUploads ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">AI Analysis Complete</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Notify when AI analysis finishes</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, aiAnalysis: !notifications.aiAnalysis })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.aiAnalysis ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.aiAnalysis ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Doctor Messages</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Notify about messages from doctors</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, doctorMessages: !notifications.doctorMessages })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.doctorMessages ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.doctorMessages ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Security Alerts</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Important security notifications</p>
              </div>
              <button
                onClick={() => setNotifications({ ...notifications, securityAlerts: !notifications.securityAlerts })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  notifications.securityAlerts ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    notifications.securityAlerts ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>
          </div>
        </div>

        {/* Privacy & Security */}
        <div className="bg-white dark:bg-[#1a202c] rounded-xl border border-gray-200 dark:border-gray-800 overflow-hidden">
          <div className="p-6 border-b border-gray-200 dark:border-gray-800">
            <h2 className="text-lg font-bold text-gray-900 dark:text-white flex items-center gap-2">
              <Icon name="shield" className="text-primary" />
              Privacy & Security
            </h2>
          </div>
          <div className="p-6 space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">Share with Doctors</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Allow linked doctors to access your documents</p>
              </div>
              <button
                onClick={() => setPrivacy({ ...privacy, shareWithDoctors: !privacy.shareWithDoctors })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  privacy.shareWithDoctors ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    privacy.shareWithDoctors ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="font-medium text-gray-900 dark:text-white">AI Analysis</p>
                <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Allow AI to analyze your medical documents</p>
              </div>
              <button
                onClick={() => setPrivacy({ ...privacy, allowAIAnalysis: !privacy.allowAIAnalysis })}
                className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  privacy.allowAIAnalysis ? 'bg-primary' : 'bg-gray-300 dark:bg-gray-700'
                }`}
              >
                <span
                  className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                    privacy.allowAIAnalysis ? 'translate-x-6' : 'translate-x-1'
                  }`}
                />
              </button>
            </div>

            <div>
              <p className="font-medium text-gray-900 dark:text-white mb-2">Data Retention</p>
              <select
                value={privacy.dataRetention}
                onChange={(e) => setPrivacy({ ...privacy, dataRetention: e.target.value })}
                className="w-full px-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 text-gray-900 dark:text-white focus:border-primary focus:ring-0"
              >
                <option value="1-year">1 Year</option>
                <option value="3-years">3 Years</option>
                <option value="5-years">5 Years (Recommended)</option>
                <option value="10-years">10 Years</option>
                <option value="indefinite">Indefinite</option>
              </select>
              <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
                How long to keep your medical records stored
              </p>
            </div>
          </div>
        </div>

        {/* Save Button */}
        <button
          onClick={handleSaveSettings}
          disabled={saving}
          className="w-full md:w-auto px-6 py-3 rounded-lg bg-primary hover:bg-blue-700 text-white font-bold transition-colors flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Icon name="save" className="text-[20px]" />
          <span>{saving ? 'Saving...' : 'Save All Settings'}</span>
        </button>

        {/* Danger Zone */}
        <div className="bg-red-50 dark:bg-red-900/20 rounded-xl border border-red-200 dark:border-red-800 overflow-hidden">
          <div className="p-6 border-b border-red-200 dark:border-red-800">
            <h2 className="text-lg font-bold text-red-900 dark:text-red-300 flex items-center gap-2">
              <Icon name="warning" className="text-red-600 dark:text-red-400" />
              Danger Zone
            </h2>
          </div>
          <div className="p-6 space-y-4">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="font-medium text-red-900 dark:text-red-300">Delete Account</p>
                <p className="text-sm text-red-700 dark:text-red-400 mt-1">
                  Permanently delete your account and all associated data. This action cannot be undone.
                </p>
              </div>
              <button
                onClick={() => setShowDeleteModal(true)}
                className="px-4 py-2 rounded-lg bg-red-600 hover:bg-red-700 text-white font-bold text-sm transition-colors whitespace-nowrap"
              >
                Delete Account
              </button>
            </div>
          </div>
        </div>

        {/* Delete Confirmation Modal */}
        {showDeleteModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={() => setShowDeleteModal(false)}>
            <div className="bg-white dark:bg-[#1a202c] rounded-xl max-w-md w-full p-6" onClick={(e) => e.stopPropagation()}>
              <div className="flex items-center gap-3 mb-4">
                <div className="size-12 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
                  <Icon name="warning" className="text-red-600 dark:text-red-400 text-2xl" />
                </div>
                <h3 className="text-xl font-bold text-gray-900 dark:text-white">Delete Account?</h3>
              </div>
              <p className="text-gray-600 dark:text-gray-400 mb-6">
                This will permanently delete your account and all your medical records. This action cannot be undone.
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setShowDeleteModal(false)}
                  className="flex-1 px-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300 font-bold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleDeleteAccount}
                  className="flex-1 px-4 py-2.5 rounded-lg bg-red-600 hover:bg-red-700 text-white font-bold transition-colors"
                >
                  Delete Forever
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Settings;
