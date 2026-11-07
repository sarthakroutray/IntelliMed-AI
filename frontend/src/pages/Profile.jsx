import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import api from '../services/api';
import Icon from '../components/Icon';
import { ui } from '../styles/ui.js';
import { Alert, Spinner } from '../components/ui.jsx';

const Profile = () => {
  const { user } = useAuth();
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(true);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    phone: '',
    dateOfBirth: '',
    gender: '',
    address: '',
    emergencyContact: '',
    emergencyPhone: '',
    bloodType: '',
    allergies: '',
    chronicConditions: ''
  });
  const [saveLoading, setSaveLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  useEffect(() => {
    const fetchProfile = async () => {
      try {
        setLoading(true);
        const response = await api.get('/profile');
        const profile = response.data;

        setFormData({
          name: profile.name || '',
          email: profile.email || '',
          phone: profile.phone || '',
          dateOfBirth: profile.date_of_birth ? profile.date_of_birth.split('T')[0] : '',
          gender: profile.gender || '',
          address: profile.address || '',
          emergencyContact: profile.emergency_contact || '',
          emergencyPhone: profile.emergency_phone || '',
          bloodType: profile.blood_type || '',
          allergies: profile.allergies || '',
          chronicConditions: profile.chronic_conditions || ''
        });
      } catch (err) {
        console.error('Failed to fetch profile', err);
        setError('Failed to load profile');
      } finally {
        setLoading(false);
      }
    };

    fetchProfile();
  }, []);

  const handleSave = async () => {
    setSaveLoading(true);
    setError('');
    setSuccess('');

    try {
      const res = await api.put('/profile', {
        name: formData.name,
        email: formData.email || null,
        phone: formData.phone,
        date_of_birth: formData.dateOfBirth || null,
        gender: formData.gender,
        address: formData.address,
        emergency_contact: formData.emergencyContact,
        emergency_phone: formData.emergencyPhone,
        blood_type: formData.bloodType,
        allergies: formData.allergies,
        chronic_conditions: formData.chronicConditions
      });

      setEditing(false);
      setSuccess('Profile updated successfully!');
      if (res?.data?.user) {
        const u = res.data.user;
        setFormData(prev => ({
          ...prev,
          name: u.name || '',
          email: u.email || '',
          dateOfBirth: u.date_of_birth || '',
        }));
      }
      setTimeout(() => setSuccess(''), 3000);
    } catch (err) {
      console.error('Failed to update profile', err);
      setError(err.response?.data?.detail || 'Failed to update profile');
    } finally {
      setSaveLoading(false);
    }
  };

  return (
    <div className={ui.page}>
      {/* Header */}
      <div className={ui.pageHeader}>
        <div>
          <h1 className={ui.pageTitle}>
            My Profile
          </h1>
          <p className={ui.pageSubtitle}>
            Manage your personal information and medical history.
          </p>
        </div>
        {!editing ? (
          <button type="button"
            onClick={() => setEditing(true)}
            className={`${ui.btn} ${ui.btnPrimary}`}
          >
            <Icon name="edit" className="text-[18px]" />
            <span>Edit Profile</span>
          </button>
        ) : (
          <div className="flex gap-2">
            <button type="button"
              onClick={() => {
                setEditing(false);
                setError('');
                setSuccess('');
              }}
              className={`${ui.btn} ${ui.btnSecondary}`}
            >
              Cancel
            </button>
            <button type="button"
              onClick={handleSave}
              disabled={saveLoading}
              className={`${ui.btn} ${ui.btnPrimary}`}
            >
              {saveLoading ? (
                <>
                  <Spinner className="size-4" />
                  <span>Saving...</span>
                </>
              ) : (
                <>
                  <Icon name="save" className="text-[18px]" />
                  <span>Save Changes</span>
                </>
              )}
            </button>
          </div>
        )}
      </div>

      {/* Success/Error Messages */}
      {success && (
        <Alert type="success" onDismiss={() => setSuccess('')}>{success}</Alert>
      )}
      {error && (
        <Alert type="error" onDismiss={() => setError('')}>{error}</Alert>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <Spinner className="size-12" />
        </div>
      ) : (
        <>
      {/* Profile Card */}
      <div className={`${ui.card} overflow-hidden`}>
        {/* Profile Header */}
        <div className="bg-gradient-to-r from-primary to-primary-strong p-8 text-white">
          <div className="flex items-center gap-6">
            <div className="relative">
              <div className="size-24 rounded-full bg-white/20 backdrop-blur-sm flex items-center justify-center text-4xl font-black">
                {formData.name.charAt(0).toUpperCase()}
              </div>
              <div className="absolute bottom-0 right-0 size-8 rounded-full bg-success border-4 border-white flex items-center justify-center">
                <Icon name="check" className="text-white text-[16px]" />
              </div>
            </div>
            <div>
              <h2 className="text-2xl font-black mb-1">{formData.name}</h2>
              <p className="text-white/80 text-sm">Patient ID: #{user?.id}</p>
              <div className="flex items-center gap-2 mt-3">
                <div className="px-3 py-1 rounded-full bg-white/20 backdrop-blur-sm text-xs font-bold">
                  {user?.role?.toUpperCase()}
                </div>
                <div className="px-3 py-1 rounded-full bg-white/20 backdrop-blur-sm text-xs font-bold flex items-center gap-1">
                  <Icon name="verified" className="text-[14px]" />
                  HIPAA Verified
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Profile Form */}
        <div className={ui.cardPad}>
          <div className="space-y-8">
            {/* Personal Information */}
            <div>
              <h3 className={`${ui.sectionTitle} mb-4 flex items-center gap-2`}>
                <Icon name="person" className="text-primary" />
                Personal Information
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className={ui.label}>Full Name</label>
                  <input aria-label="Full Name"
                    type="text"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    disabled={!editing}
                    className={ui.input}
                  />
                </div>
                <div>
                  <label className={ui.label}>Email</label>
                  <input aria-label="Email"
                    type="email"
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    disabled={!editing}
                    className={ui.input}
                  />
                </div>
                <div>
                  <label className={ui.label}>Phone Number</label>
                  <input aria-label="Phone Number"
                    type="tel"
                    value={formData.phone}
                    onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
                    disabled={!editing}
                    placeholder="+1 (555) 000-0000"
                    className={ui.input}
                  />
                </div>
                <div>
                  <label className={ui.label}>Date of Birth</label>
                  <input aria-label="Date of Birth"
                    type="date"
                    value={formData.dateOfBirth}
                    onChange={(e) => setFormData({ ...formData, dateOfBirth: e.target.value })}
                    disabled={!editing}
                    className={ui.input}
                  />
                </div>
                <div>
                  <label className={ui.label}>Gender</label>
                  <select aria-label="Gender"
                    value={formData.gender}
                    onChange={(e) => setFormData({ ...formData, gender: e.target.value })}
                    disabled={!editing}
                    className={ui.input}
                  >
                    <option value="">Select gender</option>
                    <option value="male">Male</option>
                    <option value="female">Female</option>
                    <option value="other">Other</option>
                    <option value="prefer-not-to-say">Prefer not to say</option>
                  </select>
                </div>
                <div className="md:col-span-2">
                  <label className={ui.label}>Address</label>
                  <input aria-label="Address"
                    type="text"
                    value={formData.address}
                    onChange={(e) => setFormData({ ...formData, address: e.target.value })}
                    disabled={!editing}
                    placeholder="123 Main St, City, State, ZIP"
                    className={ui.input}
                  />
                </div>
              </div>
            </div>

            {/* Emergency Contact */}
            <div>
              <h3 className={`${ui.sectionTitle} mb-4 flex items-center gap-2`}>
                <Icon name="emergency" className="text-primary" />
                Emergency Contact
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className={ui.label}>Contact Name</label>
                  <input aria-label="Emergency Contact Name"
                    type="text"
                    value={formData.emergencyContact}
                    onChange={(e) => setFormData({ ...formData, emergencyContact: e.target.value })}
                    disabled={!editing}
                    placeholder="Full name"
                    className={ui.input}
                  />
                </div>
                <div>
                  <label className={ui.label}>Contact Phone</label>
                  <input aria-label="Emergency Contact Phone"
                    type="tel"
                    value={formData.emergencyPhone}
                    onChange={(e) => setFormData({ ...formData, emergencyPhone: e.target.value })}
                    disabled={!editing}
                    placeholder="+1 (555) 000-0000"
                    className={ui.input}
                  />
                </div>
              </div>
            </div>

            {/* Medical Information */}
            <div>
              <h3 className={`${ui.sectionTitle} mb-4 flex items-center gap-2`}>
                <Icon name="medication" className="text-primary" />
                Medical Information
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className={ui.label}>Blood Type</label>
                  <select aria-label="Blood Type"
                    value={formData.bloodType}
                    onChange={(e) => setFormData({ ...formData, bloodType: e.target.value })}
                    disabled={!editing}
                    className={ui.input}
                  >
                    <option value="">Select blood type</option>
                    <option value="A+">A+</option>
                    <option value="A-">A-</option>
                    <option value="B+">B+</option>
                    <option value="B-">B-</option>
                    <option value="AB+">AB+</option>
                    <option value="AB-">AB-</option>
                    <option value="O+">O+</option>
                    <option value="O-">O-</option>
                  </select>
                </div>
                <div>
                  <label className={ui.label}>Known Allergies</label>
                  <input aria-label="Known Allergies"
                    type="text"
                    value={formData.allergies}
                    onChange={(e) => setFormData({ ...formData, allergies: e.target.value })}
                    disabled={!editing}
                    placeholder="e.g., Penicillin, Peanuts"
                    className={ui.input}
                  />
                </div>
                <div className="md:col-span-2">
                  <label className={ui.label}>Chronic Conditions</label>
                  <textarea aria-label="Chronic Conditions"
                    value={formData.chronicConditions}
                    onChange={(e) => setFormData({ ...formData, chronicConditions: e.target.value })}
                    disabled={!editing}
                    placeholder="List any chronic conditions or ongoing treatments"
                    rows="3"
                    className={`${ui.input} resize-none`}
                  ></textarea>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Security Info */}
      <Alert type="info">
        <span className="font-bold">Your Data is Secure</span> — All profile information is encrypted and stored securely in compliance with HIPAA regulations.
      </Alert>
        </>
      )}
    </div>
  );
};

export default Profile;