export async function getPatientDocumentById(id) {
  return Promise.resolve({
    id,
    filename: 'placeholder.pdf',
    patient_name: 'Test Patient',
    upload_timestamp: Date.now(),
    pageviews: 0,
    shared_with: [],
    ai_analysis: null,
  });
}

export async function getDocumentsByPatient(patientId) {
  return Promise.resolve({ data: [] });
}

export async function shareDocumentWithDoctor(docId, doctorId) {
  return Promise.resolve({ success: true });
}
