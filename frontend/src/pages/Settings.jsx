import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import api from '../services/api';
import Icon from '../components/Icon';
import { ui } from '../styles/ui.js';
import { Toast, ConfirmDialog } from '../components/ui.jsx';

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
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deletePending, setDeletePending] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [noticeType, setNoticeType] = useState('success');

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
      setNotice('Settings saved successfully!');
      setNoticeType('success');
    } catch (err) {
      setNotice('Failed to save settings: ' + (err.response?.data?.detail || 'Unknown error'));
      setNoticeType('error');
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteAccount = () => {
    setShowDeleteConfirm(true);
  };

  const confirmDeleteAccount = async () => {
    setDeletePending(true);
    setNotice('');
    try {
      await api.delete('/account');
      setNotice('Account deleted. You will be logged out.');
      setNoticeType('success');
      setTimeout(() => logout(), 800);
    } catch (err) {
      setNotice('Failed to delete account: ' + (err.response?.data?.detail || 'Unknown error'));
      setNoticeType('error');
    } finally {
      setDeletePending(false);
      setShowDeleteConfirm(false);
    }
  };

  const toggleClasses = (active) =>
    `relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${active ? 'bg-primary' : 'bg-surface-2'}`;

  return (
    <div className={ui.page}>
      <Toast message={notice} type={noticeType} onClose={() => setNotice('')} />

      {/* Header */}
      <div>
        <h1 className={ui.pageTitle}>
          Settings
        </h1>
        <p className={ui.pageSubtitle}>
          Manage your account preferences and privacy settings.
        </p>
      </div>

      {/* Appearance */}
      <div className={ui.card}>
        <div className={ui.cardHeader}>
          <h2 className={`${ui.sectionTitle} flex items-center gap-2`}>
            <Icon name="palette" className="text-primary" />
            Appearance
          </h2>
        </div>
        <div className={ui.cardPad}>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-ink">Dark Mode</p>
              <p className="text-sm text-muted mt-1">Use dark theme across the application</p>
            </div>
            <button type="button"
              onClick={() => toggleDarkMode()}
              className={toggleClasses(darkMode)}
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
      <div className={ui.card}>
        <div className={ui.cardHeader}>
          <h2 className={`${ui.sectionTitle} flex items-center gap-2`}>
            <Icon name="notifications" className="text-primary" />
            Notifications
          </h2>
        </div>
        <div className={`${ui.cardPad} space-y-4`}>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-ink">Email Notifications</p>
              <p className="text-sm text-muted mt-1">Receive notifications via email</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, email: !notifications.email })}
              className={toggleClasses(notifications.email)}
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
              <p className="font-medium text-ink">Push Notifications</p>
              <p className="text-sm text-muted mt-1">Receive browser push notifications</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, push: !notifications.push })}
              className={toggleClasses(notifications.push)}
            >
              <span
                className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                  notifications.push ? 'translate-x-6' : 'translate-x-1'
                }`}
              />
            </button>
          </div>

          <hr className="border-line" />

          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-ink">Document Uploads</p>
              <p className="text-sm text-muted mt-1">Notify when a document is uploaded</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, documentUploads: !notifications.documentUploads })}
              className={toggleClasses(notifications.documentUploads)}
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
              <p className="font-medium text-ink">AI Analysis Complete</p>
              <p className="text-sm text-muted mt-1">Notify when AI analysis finishes</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, aiAnalysis: !notifications.aiAnalysis })}
              className={toggleClasses(notifications.aiAnalysis)}
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
              <p className="font-medium text-ink">Doctor Messages</p>
              <p className="text-sm text-muted mt-1">Notify about messages from doctors</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, doctorMessages: !notifications.doctorMessages })}
              className={toggleClasses(notifications.doctorMessages)}
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
              <p className="font-medium text-ink">Security Alerts</p>
              <p className="text-sm text-muted mt-1">Important security notifications</p>
            </div>
            <button type="button"
              onClick={() => setNotifications({ ...notifications, securityAlerts: !notifications.securityAlerts })}
              className={toggleClasses(notifications.securityAlerts)}
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
      <div className={ui.card}>
        <div className={ui.cardHeader}>
          <h2 className={`${ui.sectionTitle} flex items-center gap-2`}>
            <Icon name="shield" className="text-primary" />
            Privacy & Security
          </h2>
        </div>
        <div className={`${ui.cardPad} space-y-4`}>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium text-ink">Share with Doctors</p>
              <p className="text-sm text-muted mt-1">Allow linked doctors to access your documents</p>
            </div>
            <button type="button"
              onClick={() => setPrivacy({ ...privacy, shareWithDoctors: !privacy.shareWithDoctors })}
              className={toggleClasses(privacy.shareWithDoctors)}
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
              <p className="font-medium text-ink">AI Analysis</p>
              <p className="text-sm text-muted mt-1">Allow AI to analyze your medical documents</p>
            </div>
            <button type="button"
              onClick={() => setPrivacy({ ...privacy, allowAIAnalysis: !privacy.allowAIAnalysis })}
              className={toggleClasses(privacy.allowAIAnalysis)}
            >
              <span
                className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                  privacy.allowAIAnalysis ? 'translate-x-6' : 'translate-x-1'
                }`}
              />
            </button>
          </div>

          <div>
            <p className="font-medium text-ink mb-2">Data Retention</p>
            <select aria-label="Data Retention"
              value={privacy.dataRetention}
              onChange={(e) => setPrivacy({ ...privacy, dataRetention: e.target.value })}
              className={ui.input}
            >
              <option value="1-year">1 Year</option>
              <option value="3-years">3 Years</option>
              <option value="5-years">5 Years (Recommended)</option>
              <option value="10-years">10 Years</option>
              <option value="indefinite">Indefinite</option>
            </select>
            <p className="text-sm text-muted mt-2">
              How long to keep your medical records stored
            </p>
          </div>
        </div>
      </div>

      {/* Save Button */}
      <button type="button"
        onClick={handleSaveSettings}
        disabled={saving}
        className={`${ui.btn} ${ui.btnPrimary} w-full md:w-auto`}
      >
        <Icon name="save" className="text-[20px]" />
        <span>{saving ? 'Saving...' : 'Save All Settings'}</span>
      </button>

      {/* Danger Zone */}
      <div className="bg-danger/5 rounded-2xl border border-danger/20 overflow-hidden">
        <div className="px-5 md:px-6 py-4 border-b border-danger/20">
          <h2 className={`${ui.sectionTitle} text-danger flex items-center gap-2`}>
            <Icon name="warning" className="text-danger" />
            Danger Zone
          </h2>
        </div>
        <div className={ui.cardPad}>
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="font-medium text-ink">Delete Account</p>
              <p className="text-sm text-body mt-1">
                Permanently delete your account and all associated data. This action cannot be undone.
              </p>
            </div>
            <button type="button"
              onClick={() => setShowDeleteConfirm(true)}
              className={`${ui.btn} ${ui.btnDanger} ${ui.btnSm} whitespace-nowrap`}
            >
              Delete Account
            </button>
          </div>
        </div>
      </div>

      {/* Delete Confirmation */}
      <ConfirmDialog
        open={showDeleteConfirm}
        title="Delete Account?"
        message="This will permanently delete your account and all your medical records. This action cannot be undone."
        confirmLabel="Delete Forever"
        cancelLabel="Cancel"
        danger
        busy={deletePending}
        onConfirm={confirmDeleteAccount}
        onCancel={() => setShowDeleteConfirm(false)}
      />
    </div>
  );
};

export default Settings;