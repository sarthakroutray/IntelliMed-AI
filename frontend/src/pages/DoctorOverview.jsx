import React, { useState, useEffect } from 'react';
import { useAuth } from '../context/AuthContext';
import { useNavigate } from 'react-router-dom';
import api from '../services/api';
import Icon from '../components/Icon';
import { ui } from '../styles/ui.js';

const DoctorOverview = () => {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [stats, setStats] = useState({
    totalPatients: 0,
    totalDocuments: 0,
    pendingReviews: 0,
    aiAnalysisComplete: 0
  });
  const [recentActivity, setRecentActivity] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchOverviewData = async () => {
      try {
        setLoading(true);
        
        // Fetch patients
        const patientsResponse = await api.get('/doctor/patients');
        const patients = patientsResponse.data;
        
        // Fetch documents for ALL patients in parallel (much faster!)
        const documentPromises = patients.map(patient =>
          api.get(`/doctor/patients/${patient.id}/documents`)
            .then(docsResponse => ({
              patient,
              docs: docsResponse.data,
              success: true
            }))
            .catch(err => {
              console.error(`Failed to fetch documents for patient ${patient.id}`, err);
              return { patient, docs: [], success: false };
            })
        );
        
        const results = await Promise.all(documentPromises);
        
        // Calculate stats
        let totalDocs = 0;
        let aiCompleted = 0;
        const activities = [];
        
        results.forEach(({ patient, docs }) => {
          totalDocs += docs.length;
          
          docs.forEach(doc => {
            if (doc.ai_analysis) aiCompleted++;
            activities.push({
              type: 'upload',
              patientName: patient.email?.split('@')[0],
              documentName: doc.filename,
              timestamp: doc.upload_timestamp,
              hasAI: !!doc.ai_analysis
            });
          });
        });
        
        // Sort activities by most recent
        activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
        
        setStats({
          totalPatients: patients.length,
          totalDocuments: totalDocs,
          pendingReviews: totalDocs - aiCompleted,
          aiAnalysisComplete: aiCompleted
        });
        
        setRecentActivity(activities.slice(0, 10)); // Top 10 most recent
        
      } catch (err) {
        console.error('Failed to fetch overview data', err);
      } finally {
        setLoading(false);
      }
    };

    fetchOverviewData();
  }, []);

  const StatCard = ({ icon, label, value, color, trend }) => (
    <div className={`${ui.card} ${ui.cardPad} hover:shadow-lg transition-shadow`}>
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm font-medium text-muted mb-1">{label}</p>
          <p className="text-3xl font-black text-ink">{value}</p>
          {trend && (
            <p className="text-xs text-success mt-2 flex items-center gap-1">
              <Icon name="trending_up" className="text-[14px]" />
              <span>{trend}</span>
            </p>
          )}
        </div>
        <div className={`size-12 rounded-lg ${color} flex items-center justify-center`}>
          <Icon name={icon} className="text-2xl" />
        </div>
      </div>
    </div>
  );

  return (
    <div className={`${ui.page} overflow-y-auto`}>
      {/* Welcome Header */}
      <div className={ui.pageHeader}>
        <div>
          <h1 className={ui.pageTitle}>
            Welcome back, Dr. {user?.email?.split('@')[0]}
          </h1>
          <p className={ui.pageSubtitle}>
            Here's what's happening with your patients today.
          </p>
        </div>
      </div>

      {loading ? (
        <>
          {/* Skeleton Stats Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className={`${ui.card} ${ui.cardPad} animate-pulse`}>
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="h-4 bg-surface-2 rounded w-24 mb-3"></div>
                    <div className="h-8 bg-surface-2 rounded w-16"></div>
                  </div>
                  <div className="size-12 bg-surface-2 rounded-lg"></div>
                </div>
              </div>
            ))}
          </div>
          
          {/* Skeleton Quick Actions */}
          <div className={`${ui.card} ${ui.cardPad} animate-pulse`}>
            <div className="h-6 bg-surface-2 rounded w-32 mb-4"></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2, 3].map(i => (
                <div key={i} className="h-20 bg-surface-2 rounded-lg"></div>
              ))}
            </div>
          </div>
          
          {/* Skeleton Recent Activity */}
          <div className={`${ui.card} ${ui.cardPad} animate-pulse`}>
            <div className="h-6 bg-surface-2 rounded w-40 mb-4"></div>
            <div className="space-y-4">
              {[1, 2, 3, 4, 5].map(i => (
                <div key={i} className="flex items-center gap-4 p-3 rounded-lg">
                  <div className="size-10 bg-surface-2 rounded-full"></div>
                  <div className="flex-1">
                    <div className="h-4 bg-surface-2 rounded w-3/4 mb-2"></div>
                    <div className="h-3 bg-surface-2 rounded w-1/2"></div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </>
      ) : (
        <>
          {/* Stats Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            <StatCard 
              icon="group" 
              label="Total Patients" 
              value={stats.totalPatients}
              color="bg-primary/10 text-primary"
              trend="+2 this week"
            />
            <StatCard 
              icon="description" 
              label="Total Documents" 
              value={stats.totalDocuments}
              color="bg-info/10 text-info"
            />
            <StatCard 
              icon="auto_awesome" 
              label="AI Analysis Done" 
              value={stats.aiAnalysisComplete}
              color="bg-success/10 text-success"
            />
            <StatCard 
              icon="pending_actions" 
              label="Pending Reviews" 
              value={stats.pendingReviews}
              color="bg-warning/10 text-warning"
            />
          </div>

          {/* Quick Actions */}
          <div className={`${ui.card} ${ui.cardPad}`}>
            <h2 className={`${ui.sectionTitle} mb-4`}>Quick Actions</h2>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <button type="button" 
                onClick={() => navigate('/dashboard/patients')}
                className="flex items-center gap-3 p-4 rounded-lg border-2 border-dashed border-line hover:border-primary hover:bg-primary/5 transition-colors text-left"
              >
                <Icon name="group_add" className="text-primary text-2xl" />
                <div>
                  <p className="font-bold text-ink text-sm">View Patients</p>
                  <p className="text-xs text-muted">Manage patient list</p>
                </div>
              </button>
              <button type="button" 
                onClick={() => navigate('/dashboard/documents')}
                className="flex items-center gap-3 p-4 rounded-lg border-2 border-dashed border-line hover:border-primary hover:bg-primary/5 transition-colors text-left"
              >
                <Icon name="folder_open" className="text-primary text-2xl" />
                <div>
                  <p className="font-bold text-ink text-sm">Browse Documents</p>
                  <p className="text-xs text-muted">View all records</p>
                </div>
              </button>
              <button type="button" 
                onClick={() => navigate('/dashboard/ai-analysis')}
                className="flex items-center gap-3 p-4 rounded-lg border-2 border-dashed border-line hover:border-primary hover:bg-primary/5 transition-colors text-left"
              >
                <Icon name="auto_awesome" className="text-primary text-2xl" />
                <div>
                  <p className="font-bold text-ink text-sm">AI Analysis</p>
                  <p className="text-xs text-muted">Review AI insights</p>
                </div>
              </button>
            </div>
          </div>

          {/* Recent Activity */}
          <div className={`${ui.card} overflow-hidden`}>
            <div className={ui.cardHeader}>
              <h2 className={ui.sectionTitle}>Recent Activity</h2>
            </div>
            <div className="divide-y divide-line">
              {recentActivity.length > 0 ? (
                recentActivity.map((activity, index) => (
                  <div key={index} className="p-4 hover:bg-surface-2/60 transition-colors">
                    <div className="flex items-start gap-4">
                      <div className="size-10 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                        <Icon name="description" className="text-primary text-[20px]" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-ink">
                          <span className="font-bold">{activity.patientName}</span> uploaded <span className="font-bold">{activity.documentName}</span>
                        </p>
                        <p className="text-xs text-muted mt-1">
                          {new Date(activity.timestamp).toLocaleString()}
                        </p>
                      </div>
                      {activity.hasAI && (
                        <div className={`${ui.badge} ${ui.badgeSuccess}`}>
                          <Icon name="auto_awesome" className="text-[14px]" />
                          <span>AI Ready</span>
                        </div>
                      )}
                    </div>
                  </div>
                ))
              ) : (
                <div className="p-8 text-center">
                  <Icon name="history" className="text-subtle text-5xl mx-auto mb-3" />
                  <p className="text-muted">No recent activity</p>
                </div>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
};

export default DoctorOverview;