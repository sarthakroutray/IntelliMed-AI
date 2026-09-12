// Lab test-name normalisation — a faithful port of the backend map and lookup
// in `backend/lab_pipeline/slm_stage.py` (TEST_NAME_MAP, _normalize_lookup_key,
// normalize_test_name).
//
// The map is frozen to match the Python source exactly; a parity test asserts
// the two maps are identical so drift cannot be silent (see
// mobile/test/fixtures/lab/test_name_map.json).

/// Abbreviation -> full clinical name. Ported verbatim from
/// `slm_stage.py::TEST_NAME_MAP` — keep both copies in lockstep.
const testNameMap = <String, String>{
  'hb': 'Hemoglobin',
  'hgb': 'Hemoglobin',
  'wbc': 'White Blood Cell Count',
  'tlc': 'White Blood Cell Count',
  'rbc': 'Red Blood Cell Count',
  'plt': 'Platelet Count',
  'plt count': 'Platelet Count',
  'hct': 'Hematocrit',
  'pcv': 'Hematocrit',
  'mcv': 'Mean Corpuscular Volume',
  'mch': 'Mean Corpuscular Hemoglobin',
  'mchc': 'Mean Corpuscular Hemoglobin Concentration',
  'rdw': 'Red Cell Distribution Width',
  'esr': 'Erythrocyte Sedimentation Rate',
  'crp': 'C-Reactive Protein',
  'neut': 'Neutrophils',
  'neuts': 'Neutrophils',
  'lymph': 'Lymphocytes',
  'lymp': 'Lymphocytes',
  'eos': 'Eosinophils',
  'baso': 'Basophils',
  'fbs': 'Fasting Blood Glucose',
  'fbg': 'Fasting Blood Glucose',
  'ppbs': 'Postprandial Blood Glucose',
  'ppbg': 'Postprandial Blood Glucose',
  'hba1c': 'Glycated Hemoglobin (HbA1c)',
  'bun': 'Blood Urea Nitrogen',
  'sgot': 'Aspartate Aminotransferase (AST)',
  'ast': 'Aspartate Aminotransferase (AST)',
  'sgpt': 'Alanine Aminotransferase (ALT)',
  'alt': 'Alanine Aminotransferase (ALT)',
  'alp': 'Alkaline Phosphatase',
  'tsh': 'Thyroid Stimulating Hormone',
  't3': 'Triiodothyronine (T3)',
  't4': 'Thyroxine (T4)',
  'hdl': 'HDL Cholesterol',
  'ldl': 'LDL Cholesterol',
  'vldl': 'VLDL Cholesterol',
  'tg': 'Triglycerides',
  'na': 'Sodium',
  'na+': 'Sodium',
  'sodium na': 'Sodium',
  'k': 'Potassium',
  'k+': 'Potassium',
  'cl': 'Chloride',
  'cl-': 'Chloride',
  'ca': 'Calcium',
  'creatinine': 'Serum Creatinine',
  'creat': 'Serum Creatinine',
  's creatinine': 'Serum Creatinine',
  's. creatinine': 'Serum Creatinine',
  'cholesterol total': 'Total Cholesterol',
  'total cholesterol': 'Total Cholesterol',
  'cholesterol, total': 'Total Cholesterol',
  'urea': 'Blood Urea',
  'uric acid': 'Uric Acid',
};

/// Mirrors `_normalize_lookup_key`: lowercase, every non `[a-z0-9 ]` char
/// becomes a space, then trim.
String normalizeLookupKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();

/// Mirrors `normalize_test_name`: a direct lookup, then a last-token fallback
/// so prefixes like "S. Creatinine (Serum)" still resolve. Returns null when
/// the name is unknown (callers decide the fallback text).
String? normalizeTestNameOrNull(String rawName) {
  final key = normalizeLookupKey(rawName);
  if (key.isEmpty) return null;
  final direct = testNameMap[key];
  if (direct != null) return direct;
  for (final token in key.split(RegExp(r'\s+')).reversed) {
    final hit = testNameMap[token];
    if (hit != null) return hit;
  }
  return null;
}
