// On-device document-type detection.
//
// Why this exists: the X-ray classifier is a *pneumonia* classifier over
// [Normal, Bacterial Pneumonia, Viral Pneumonia]. It has no "not a chest
// X-ray" class, so it will confidently label a prescription photo as
// pneumonia. The backend guards against exactly this
// (backend/api/patient_router.py):
//
//     is_meaningful_xray = (not is_prescription and not has_medications and
//                           cv_result.confidence > 0.6 and ...)
//
// This module reproduces that guard on-device, using OCR text as the primary
// signal and the classifier only as a tie-breaker for sparse images.
//
// The strongest discriminator is text density: a chest X-ray carries almost no
// machine-readable text (maybe "PORTABLE", a name and a date), whereas a lab
// report or prescription is text-dense with units, ranges and dosing.
//
// Output is a *suggestion*: the UI always shows what was detected and why, and
// the user can override it.

import 'schemas.dart';

/// The three document kinds the app can normalize.
enum DocumentType { labReport, prescription, xray }

/// What the user asked for: automatic detection, or an explicit type.
///
/// Kept separate from [DocumentType] because "Auto" is a choice about *how* to
/// decide, not a fourth document kind.
enum CaptureMode { auto, labReport, prescription, xray }

extension CaptureModeX on CaptureMode {
  String get label => switch (this) {
    CaptureMode.auto => 'Auto',
    CaptureMode.labReport => 'Lab',
    CaptureMode.prescription => 'Rx',
    CaptureMode.xray => 'X-ray',
  };

  /// The type this mode pins, or null for [CaptureMode.auto].
  DocumentType? get pinned => switch (this) {
    CaptureMode.auto => null,
    CaptureMode.labReport => DocumentType.labReport,
    CaptureMode.prescription => DocumentType.prescription,
    CaptureMode.xray => DocumentType.xray,
  };
}

extension DocumentTypeWire on DocumentType {
  /// The value used in envelopes and on the wire (`document_type`).
  String get wireName => switch (this) {
    DocumentType.labReport => 'lab_report',
    DocumentType.prescription => 'prescription',
    DocumentType.xray => 'xray',
  };

  String get label => switch (this) {
    DocumentType.labReport => 'Lab report',
    DocumentType.prescription => 'Prescription',
    DocumentType.xray => 'X-ray',
  };

  /// Short label for the type selector.
  String get shortLabel => switch (this) {
    DocumentType.labReport => 'Lab',
    DocumentType.prescription => 'Rx',
    DocumentType.xray => 'X-ray',
  };

  static DocumentType? fromWire(String? value) {
    switch (value) {
      case 'lab_report':
        return DocumentType.labReport;
      case 'prescription':
        return DocumentType.prescription;
      case 'xray':
        return DocumentType.xray;
      default:
        return null;
    }
  }
}

/// Text-derived evidence, kept separate from the decision so it can be shown
/// to the user and asserted in tests.
class TextSignals {
  const TextSignals({
    required this.labScore,
    required this.prescriptionScore,
    required this.wordCount,
    required this.labMatches,
    required this.prescriptionMatches,
  });

  final double labScore;
  final double prescriptionScore;
  final int wordCount;

  /// Which markers fired, for transparency in the UI.
  final Set<String> labMatches;
  final Set<String> prescriptionMatches;

  /// X-rays carry very little text; text-dense documents never are.
  bool get isSparse => wordCount <= sparseWordLimit;

  bool get hasLabEvidence => labScore >= decisiveScore;
  bool get hasPrescriptionEvidence => prescriptionScore >= decisiveScore;

  /// Text alone settles it — no need to pay for a classifier run.
  bool get isDecisive => hasLabEvidence || hasPrescriptionEvidence;
}

/// Below this word count an image is treated as a candidate radiograph.
const sparseWordLimit = 15;

/// Evidence needed before the text decides the type on its own.
const decisiveScore = 2.0;

/// Minimum classifier confidence to accept an X-ray call, matching the
/// backend's 0.6 threshold.
const xrayConfidenceThreshold = 0.60;

// --- marker tables ---------------------------------------------------------

/// Prescription-form markers (weight 2): dosage-form abbreviations and
/// dispensing vocabulary.
final _rxStrong = <String, RegExp>{
  'Rx symbol': RegExp(r'(?:^|\s)r[x×](?:\.|\s|$)', caseSensitive: false),
  'Tab.': RegExp(r'\btab(?:let)?s?\.?\b', caseSensitive: false),
  'Cap.': RegExp(r'\bcap(?:sule)?s?\.?\b', caseSensitive: false),
  'Syrup': RegExp(r'\b(?:syp|susp|syrup|suspension)\b\.?', caseSensitive: false),
  'Injection': RegExp(r'\b(?:inj|injection)s?\.?\b', caseSensitive: false),
  'Sig.': RegExp(r'\bsig\.?\b', caseSensitive: false),
  'Dispense': RegExp(r'\bdispense\b', caseSensitive: false),
  'Refill': RegExp(r'\brefill\b', caseSensitive: false),
  'Prescription': RegExp(r'\bprescription\b', caseSensitive: false),
  'Dosage': RegExp(r'\bdosage\b', caseSensitive: false),
  'Doctor signature': RegExp(
    r'\b(?:m\.?\s?b\.?\s?b\.?\s?s|m\.?d\.?|reg(?:d)?\.?\s*no)\b',
    caseSensitive: false,
  ),
};

/// Dosing-frequency markers (weight 2).
final _rxFrequency = <String, RegExp>{
  'BD/OD/TDS': RegExp(
    r'\b(?:bd|od|tds|qid|hs|sos|prn|stat|q\.?d\.?|b\.?i\.?d)\b',
    caseSensitive: false,
  ),
  'Dosing instruction': RegExp(
    r'\b(?:once|twice|thrice|three times|four times)\s+(?:a\s+)?daily\b',
    caseSensitive: false,
  ),
  'Meal timing': RegExp(
    r'\b(?:before|after)\s+(?:food|meals?)\b|\bat bedtime\b',
    caseSensitive: false,
  ),
  'Course duration': RegExp(
    r'\bfor\s+\d+\s+(?:days?|weeks?)\b|\bx\s?\d+\s+days?\b',
    caseSensitive: false,
  ),
  'Take': RegExp(r'\btake\s+\d', caseSensitive: false),
};

/// A strength dose like "500 mg" or "5 ml" (weight 1).
///
/// Deliberately excludes a trailing `/` so lab units (`mg/dL`, `g/dL`) do not
/// count as prescription doses.
final _rxDose = RegExp(
  r'\b\d+(?:\.\d+)?\s*(?:mg|mcg|ml|gm|g|iu|units?)\b(?!\s*/)',
  caseSensitive: false,
);

/// Lab unit markers (weight 1). These are what distinguish "5 mg/dL" (a
/// measurement) from "500 mg" (a dose).
final _labUnits = RegExp(
  r'(?:g|mg|µg|ug|ng|pg)\s*/\s*(?:dl|dL|l|L|ml)\b'
  r'|(?:mmol|µmol|umol|mEq|meq|IU|iu|U|u)\s*/\s*[lL]\b'
  r'|\bcells?\s*/\s*(?:cumm|cmm|µl|ul)\b'
  r'|/\s*cumm\b'
  r'|\b10\s*\^?\s*\d+\s*/\s*[lL]\b',
  caseSensitive: false,
);

/// Lab vocabulary (weight 1 each) that a prescription would not contain.
final _labVocabulary = <String, RegExp>{
  'Reference range': RegExp(
    r'\b(?:reference|ref\.?)\s*(?:range|value|interval)?\b',
    caseSensitive: false,
  ),
  'Normal range': RegExp(r'\bnormal\s+(?:range|values?)\b', caseSensitive: false),
  'Specimen': RegExp(
    r'\b(?:specimen|serum|plasma|whole blood|edta|fasting|random)\b',
    caseSensitive: false,
  ),
  'Lab identifiers': RegExp(
    r'\b(?:lab\s*no|sample\s*(?:id|no)|barcode|collected|reported|registered)\b',
    caseSensitive: false,
  ),
  'Method': RegExp(
    r'\b(?:method|analyzer|photometry|immunoassay|chemiluminescence)\b',
    caseSensitive: false,
  ),
};

/// A printed numeric range like "13.0 - 17.0" (weight 1).
final _labRange = RegExp(r'\d+(?:\.\d+)?\s*[-–—]\s*\d+(?:\.\d+)?');

/// Dates, which must not be mistaken for a printed reference range.
///
/// Only `-` and `/` separate the parts, and a 4-digit year is required, so a
/// real range is never eaten: "13.0-17.0" uses dots and "150-450" has no third
/// component, whereas "12-04-2024" is stripped.
final _dateRe = RegExp(
  r'\b(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\b',
);

/// Clinical analyte names (weight 2 each). Sourced from the normalizer's map so
/// detection and normalization agree on vocabulary.
final _labAnalytes = <String, RegExp>{
  for (final entry in testNameMap.entries)
    entry.value: RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
  'Haemoglobin': RegExp(r'\bha?emoglobin\b', caseSensitive: false),
  'Platelet': RegExp(r'\bplatelets?\b', caseSensitive: false),
  'Creatinine': RegExp(r'\bcreatinine\b', caseSensitive: false),
  'Cholesterol': RegExp(r'\bcholesterol\b', caseSensitive: false),
  'Bilirubin': RegExp(r'\bbilirubin\b', caseSensitive: false),
  'Thyroid': RegExp(r'\bthyroid\b', caseSensitive: false),
};

/// Analyse OCR text for type evidence.
TextSignals analyseText(String text) {
  final labMatches = <String>{};
  final rxMatches = <String>{};
  var labScore = 0.0;
  var rxScore = 0.0;

  if (text.trim().isEmpty) {
    return const TextSignals(
      labScore: 0,
      prescriptionScore: 0,
      wordCount: 0,
      labMatches: {},
      prescriptionMatches: {},
    );
  }

  // Score against the text with dates removed: every medical document carries
  // dates, and a bare "12-04-2024" otherwise reads as a reference range.
  final cleaned = text.replaceAll(_dateRe, ' ');

  _rxStrong.forEach((name, pattern) {
    if (pattern.hasMatch(cleaned)) {
      rxScore += 2;
      rxMatches.add(name);
    }
  });
  _rxFrequency.forEach((name, pattern) {
    if (pattern.hasMatch(cleaned)) {
      rxScore += 2;
      rxMatches.add(name);
    }
  });
  if (_rxDose.hasMatch(cleaned)) {
    rxScore += 1;
    rxMatches.add('Dose strength');
  }

  _labAnalytes.forEach((name, pattern) {
    if (pattern.hasMatch(cleaned)) {
      labScore += 2;
      labMatches.add(name);
    }
  });
  _labVocabulary.forEach((name, pattern) {
    if (pattern.hasMatch(cleaned)) {
      labScore += 1;
      labMatches.add(name);
    }
  });
  if (_labUnits.hasMatch(cleaned)) {
    labScore += 1;
    labMatches.add('Measurement unit');
  }
  if (_labRange.hasMatch(cleaned)) {
    labScore += 1;
    labMatches.add('Printed range');
  }

  final wordCount = text
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .length;

  return TextSignals(
    labScore: labScore,
    prescriptionScore: rxScore,
    wordCount: wordCount,
    labMatches: labMatches,
    prescriptionMatches: rxMatches,
  );
}

/// The outcome of detection, including why — shown in the UI.
class TypeDetection {
  const TypeDetection({
    required this.type,
    required this.confidence,
    required this.reasons,
    this.usedClassifier = false,
    this.autoDetected = true,
  });

  final DocumentType type;

  /// 0..1. Anything below [decisiveScore] worth of evidence lands here.
  final double confidence;

  /// Human-readable evidence, e.g. "Dose strength", "Printed range".
  final List<String> reasons;

  /// Whether the X-ray classifier had to run to make the call.
  final bool usedClassifier;

  /// False when the user picked the type explicitly.
  final bool autoDetected;

  /// Copy for the capture status line.
  String get summary {
    if (!autoDetected) return '${type.label} — selected manually.';
    final basis = reasons.isEmpty ? 'document layout' : reasons.take(3).join(', ');
    final pct = (confidence * 100).round();
    return 'Detected ${type.label} ($pct%) from $basis.';
  }

  /// True when the evidence was thin, so the UI can invite a correction.
  bool get isWeak => autoDetected && confidence < 0.6;
}

/// Decide the document type.
///
/// [xrayConfidence] is the classifier's top probability, or null when the
/// classifier has not run. The classifier is only consulted for *sparse* text
/// with no lab/prescription evidence — mirroring the backend guard, because
/// the pneumonia head always returns one of its three labels.
TypeDetection decideType({
  required TextSignals signals,
  double? xrayConfidence,
  bool classifierAvailable = true,
  DocumentType? fallback,
}) {
  // 1. Text evidence wins. Lab and prescription text is unambiguous, and an
  //    X-ray cannot produce a printed reference range or a dosing schedule.
  if (signals.hasPrescriptionEvidence &&
      signals.prescriptionScore > signals.labScore) {
    return TypeDetection(
      type: DocumentType.prescription,
      confidence: _confidenceFor(signals.prescriptionScore),
      reasons: signals.prescriptionMatches.toList()..sort(),
    );
  }
  if (signals.hasLabEvidence && signals.labScore >= signals.prescriptionScore) {
    return TypeDetection(
      type: DocumentType.labReport,
      confidence: _confidenceFor(signals.labScore),
      reasons: signals.labMatches.toList()..sort(),
    );
  }

  // 2. Sparse text (likely a radiograph) — trust the classifier, but only at
  //    or above the backend's threshold. This is the guard that stops a
  //    prescription or lab report being called pneumonia.
  final confident =
      xrayConfidence != null && xrayConfidence >= xrayConfidenceThreshold;
  if (confident && signals.isSparse && !signals.isDecisive) {
    return TypeDetection(
      type: DocumentType.xray,
      confidence: xrayConfidence.clamp(0.0, 1.0),
      reasons: ['sparse text', 'classifier ${(xrayConfidence * 100).round()}%'],
      usedClassifier: true,
    );
  }

  // 3. Otherwise the image is neither a decisive document nor a confident
  //    radiograph. When a classifier result exists but the text is NOT sparse,
  //    it must not be trusted: fall back to text scoring.
  if (signals.labScore > 0 || signals.prescriptionScore > 0) {
    final labWins = signals.labScore >= signals.prescriptionScore;
    final winner = labWins ? DocumentType.labReport : DocumentType.prescription;
    return TypeDetection(
      type: winner,
      confidence: _confidenceFor(
        labWins ? signals.labScore : signals.prescriptionScore,
      ),
      reasons: (labWins ? signals.labMatches : signals.prescriptionMatches)
          .toList()
        ..sort(),
    );
  }

  // 4. No usable evidence at all (near-empty text, no confident classifier).
  //    Prefer the caller's fallback, else the most common lab document.
  return TypeDetection(
    type: fallback ?? DocumentType.labReport,
    confidence: 0.2,
    reasons: const ['no clear markers'],
    usedClassifier: xrayConfidence != null,
  );
}

/// Map a raw score to a 0..1 confidence, capped so nothing claims certainty.
double _confidenceFor(double score) {
  if (score >= 6) return 0.95;
  if (score >= 4) return 0.85;
  if (score >= 3) return 0.75;
  if (score >= 2) return 0.65;
  if (score >= 1) return 0.4;
  return 0.2;
}

/// Whether detection needs the classifier to run for this text.
///
/// Saves a model pass on text-dense documents that already decide themselves.
bool needsClassifier(TextSignals signals) =>
    !signals.isDecisive && signals.isSparse;
