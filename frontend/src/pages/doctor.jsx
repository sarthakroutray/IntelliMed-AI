import DoctorOverview from './DoctorOverview';
import DoctorPatients from './DoctorPatients';
import DoctorDocuments from './DoctorDocuments';
import DoctorAiAnalysis from './DoctorAiAnalysis';

/**
 * Doctor page — renders the appropriate view based on query params.
 * This file is kept for backward compatibility with routes that point to
 * /doctor/overview, /doctor/patients, etc.
 */
export default function Doctor() {
  const search = new URLSearchParams(window.location.search);
  const view = search.get('view') || 'overview';

  switch (view) {
    case 'overview':
      return <DoctorOverview />;
    case 'patients':
      return <DoctorPatients />;
    case 'documents':
      return <DoctorDocuments />;
    case 'analysis':
      return <DoctorAiAnalysis />;
    default:
      return <DoctorOverview />;
  }
}
