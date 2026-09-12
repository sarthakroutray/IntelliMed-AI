// Typed access to the backend for patient screens.
//
// Only endpoints that already exist are used; the app never relies on a
// backend change. Report traffic is /api/v2, everything else is the frozen
// /api/v1 surface.

import 'api_client.dart';
import 'models.dart';

class PatientRepository {
  PatientRepository(this.client);

  final ApiClient client;

  /// Parses a JSON array defensively — this backend returns bare dicts and
  /// occasionally a single object where a list is expected.
  List<T> _parseList<T>(
    dynamic decoded,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry('$k', v)))
        .map(fromJson)
        .toList();
  }

  // -------------------------------------------------------------------
  // Lab reports (v2) — the only place structured results are listed
  // -------------------------------------------------------------------

  Future<List<LabReport>> listLabReports() async {
    final decoded = await client.getJson('/api/v2/lab-reports');
    return _parseList(decoded, LabReport.fromJson);
  }

  Future<LabReport> getLabReport(int id) async {
    final decoded = await client.getJson('/api/v2/lab-reports/$id');
    return LabReport.fromJson(_asMap(decoded));
  }

  /// Delete one of this patient's own lab reports (row + stored file) on the
  /// server. Ownership is enforced server-side, so a stale id returns 404.
  Future<void> deleteLabReport(int id) async {
    await client.deleteJson('/api/v2/lab-reports/$id');
  }

  /// Upload a raw file to the full server-side lab pipeline
  /// (POST /api/v2/lab-reports/upload, Stages 1-3). This is the verification
  /// path used by the developer diff screen to compare the on-device engine
  /// against the reference; normal captures stay on-device. Returns the raw
  /// server envelope (`{message, id, result: {stage1, stage2, stage3, ...}}`).
  Future<Map<String, dynamic>> uploadLabReport({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final decoded = await client.postMultipart(
      '/api/v2/lab-reports/upload',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      fields: const {'source': 'app'},
    );
    return _asMap(decoded);
  }

  // -------------------------------------------------------------------
  // Documents (v1) — raw files + server-side AI analysis
  // -------------------------------------------------------------------

  Future<List<DocumentSummary>> listDocuments() async {
    final decoded = await client.getJson('/api/v1/patient/documents');
    return _parseList(decoded, DocumentSummary.fromJson);
  }

  Future<DocumentDetail> getDocument(int id) async {
    final decoded = await client.getJson('/api/v1/documents/$id');
    return DocumentDetail.fromJson(_asMap(decoded));
  }

  /// Uploads a raw document. User-initiated only — this sends PHI off-device.
  /// Runs OCR/CV/NLP/T5 inline on the server, so it uses the heavy timeout.
  Future<DocumentSummary> uploadDocument({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final decoded = await client.postMultipart(
      '/api/v1/patient/upload/',
      field: 'file',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
    return DocumentSummary.fromJson(_asMap(decoded));
  }

  /// Re-runs server-side analysis. Heavy, and the response shape is not
  /// modelled — callers re-fetch the detail afterwards.
  Future<void> analyzeDocument(int id) async {
    await client.postJson('/api/v1/documents/$id/analyze', null);
  }

  Future<void> deleteDocument(int id) async {
    await client.deleteJson('/api/v1/patient/documents/$id');
  }

  // -------------------------------------------------------------------
  // Profile
  // -------------------------------------------------------------------

  Future<Profile> getProfile() async {
    final decoded = await client.getJson('/api/v1/profile');
    return Profile.fromJson(_asMap(decoded));
  }

  /// Only non-null values are sent; the backend ignores absent keys.
  Future<void> updateProfile(Map<String, dynamic> changes) async {
    await client.putJson('/api/v1/profile', changes);
  }

  // -------------------------------------------------------------------
  // Doctors & linking
  // -------------------------------------------------------------------

  Future<List<LinkedDoctor>> listLinkedDoctors() async {
    final decoded = await client.getJson('/api/v1/patient/linked-doctors');
    return _parseList(decoded, LinkedDoctor.fromJson);
  }

  /// Returns the 6-character code a doctor enters to link to this patient.
  Future<String> generateAccessCode() async {
    final decoded = await client.postJson(
      '/api/v1/patient/generate-access-code',
      null,
    );
    final code = _asMap(decoded)['access_code'];
    if (code is! String || code.isEmpty) {
      throw ApiException(
        ApiErrorKind.server,
        'The server did not return an access code.',
      );
    }
    return code;
  }

  // -------------------------------------------------------------------
  // Sharing (per document)
  // -------------------------------------------------------------------

  Future<List<SharedDoctor>> listSharedDoctors(int documentId) async {
    final decoded = await client.getJson(
      '/api/v1/patient/documents/$documentId/shared-doctors',
    );
    return _parseList(decoded, SharedDoctor.fromJson);
  }

  Future<void> shareDocument(int documentId, int doctorId) async {
    await client.postJson(
      '/api/v1/patient/documents/$documentId/share/$doctorId',
      null,
    );
  }

  Future<void> unshareDocument(int documentId, int doctorId) async {
    await client.deleteJson(
      '/api/v1/patient/documents/$documentId/share/$doctorId',
    );
  }

  Map<String, dynamic> _asMap(dynamic decoded) {
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry('$k', v));
    }
    throw ApiException(
      ApiErrorKind.server,
      'The server returned an unexpected response.',
    );
  }
}
