// Stage 3 — Deterministic arithmetic and clinical rule engine for lab reports.
//
// 100% parity with `backend/lab_pipeline/rule_engine.py`:
// 1. Arithmetic Derived Indices: eGFR (CKD-EPI 2021), Anion Gap, De Ritis,
//    BUN/Cr, Corrected Calcium, A/G Ratio, Non-HDL, Mentzer Index, TSAT, NLR.
// 2. Arithmetic Consistency Validator (OCR Sanity Guard).
// 3. Multi-tier Single-value Flagging & Panic/Critical Thresholds.
// 4. Clinical Pattern Matcher with arithmetic expression support.

import 'dart:math' as math;

import '../api/models.dart' show FlaggedPattern, TriggeringTest;
import 'rule_engine.dart';

/// Representation of a single condition within a clinical pattern rule.
class ClinicalCondition {
  const ClinicalCondition({
    required this.testName,
    this.direction,
    this.operator,
    this.threshold,
    this.low,
    this.high,
    this.ratioWith,
  });

  final String testName;
  final String? direction;
  final String? operator;
  final double? threshold;
  final double? low;
  final double? high;
  final String? ratioWith;

  factory ClinicalCondition.fromJson(Map<String, dynamic> json) =>
      ClinicalCondition(
        testName: (json['test_name'] as String? ?? '').trim(),
        direction: json['direction'] as String?,
        operator: json['operator'] as String?,
        threshold: (json['threshold'] as num?)?.toDouble(),
        low: (json['low'] as num?)?.toDouble(),
        high: (json['high'] as num?)?.toDouble(),
        ratioWith: json['ratio_with'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'test_name': testName,
    if (direction != null) 'direction': direction,
    if (operator != null) 'operator': operator,
    if (threshold != null) 'threshold': threshold,
    if (low != null) 'low': low,
    if (high != null) 'high': high,
    if (ratioWith != null) 'ratio_with': ratioWith,
  };
}

/// A clinically curated pattern rule evaluated across lab report tests.
class ClinicalRule {
  const ClinicalRule({
    required this.patternName,
    required this.surfacedText,
    this.category = 'General',
    this.severity = 'warning',
    this.scope = 'panel',
    this.matchType = 'all',
    this.minCount,
    required this.conditions,
    this.clinicalImplication = '',
    this.differentialDiagnosis = const [],
  });

  final String patternName;
  final String surfacedText;
  final String category;
  final String severity; // critical | warning | info
  final String scope; // document | panel
  final String matchType; // all | any | min_count
  final int? minCount;
  final List<ClinicalCondition> conditions;
  final String clinicalImplication;
  final List<String> differentialDiagnosis;

  factory ClinicalRule.fromJson(Map<String, dynamic> json) {
    final rawConds = json['conditions'] as List? ?? [];
    final conds = rawConds
        .map((c) => ClinicalCondition.fromJson(c as Map<String, dynamic>))
        .toList();
    final rawDiff = json['differential_diagnosis'] as List? ?? [];
    final diff = rawDiff.map((d) => '$d').toList();

    return ClinicalRule(
      patternName: json['pattern_name'] as String? ?? 'Pattern',
      surfacedText: json['surfaced_text'] as String? ?? '',
      category: json['category'] as String? ?? 'General',
      severity: json['severity'] as String? ?? 'warning',
      scope: json['scope'] as String? ?? 'panel',
      matchType: json['match_type'] as String? ?? 'all',
      minCount: json['min_count'] as int?,
      conditions: conds,
      clinicalImplication: json['clinical_implication'] as String? ?? '',
      differentialDiagnosis: diff,
    );
  }
}

/// Standard panic thresholds for emergency medical escalation.
const standardPanicThresholds = <String, ({double? low, double? high})>{
  'Potassium': (low: 2.8, high: 6.2),
  'Sodium': (low: 120.0, high: 160.0),
  'Platelet Count': (low: 20.0, high: 1000.0),
  'Hemoglobin': (low: 7.0, high: 20.0),
  'Hematocrit': (low: 20.0, high: 60.0),
  'White Blood Cell Count': (low: 2.0, high: 30.0),
  'Fasting Blood Glucose': (low: 50.0, high: 400.0),
  'Random Blood Glucose': (low: 50.0, high: 400.0),
  'Calcium': (low: 6.5, high: 13.0),
  'Corrected Calcium': (low: 6.5, high: 13.0),
  'Serum Creatinine': (low: null, high: 5.0),
  'Total Bilirubin': (low: null, high: 15.0),
  'Triglycerides': (low: null, high: 500.0),
};

/// Result of a full Stage 3 on-device annotation pass.
class LabDocumentAnnotationResult {
  const LabDocumentAnnotationResult({
    required this.document,
    required this.patterns,
    required this.warnings,
    required this.hasPanicValues,
  });

  final LabDocument document;
  final List<FlaggedPattern> patterns;
  final List<String> warnings;
  final bool hasPanicValues;
}

// -----------------------------------------------------------------------------
// 1. ARITHMETIC DERIVED INDICES CALCULATOR
// -----------------------------------------------------------------------------

LabDocument calculateDerivedIndices(LabDocument document) {
  final patientContext = document.patientContext;
  final num? ageNum = patientContext?.age;
  final age = ageNum?.toDouble();
  final sex = (patientContext?.sex ?? '').trim().toLowerCase();

  // Index existing tests by lowercase canonical name
  final testLookup = <String, LabTest>{};
  for (final panel in document.panels) {
    for (final test in panel.tests) {
      if (test.value != null) {
        testLookup[test.testName.trim().toLowerCase()] = test;
      }
    }
  }

  double? val(String canonical) => testLookup[canonical.toLowerCase()]?.value;
  Map<String, dynamic>? bbox(String canonical) =>
      testLookup[canonical.toLowerCase()]?.sourceBbox;

  final derived = <LabTest>[];

  // 1. eGFR via CKD-EPI 2021 (race-free)
  final creat = val('serum creatinine');
  if (creat != null && creat > 0 && age != null && age >= 18) {
    final isFemale = sex == 'f' || sex == 'female' || sex == 'woman';
    final kappa = isFemale ? 0.7 : 0.9;
    final alpha = isFemale ? -0.241 : -0.302;
    final genderMult = isFemale ? 1.012 : 1.000;
    final scrK = creat / kappa;

    final egfr =
        142.0 *
        math.pow(math.min(scrK, 1.0), alpha) *
        math.pow(math.max(scrK, 1.0), -1.200) *
        math.pow(0.9938, age) *
        genderMult;
    final roundedEgfr = (egfr * 10).round() / 10.0;

    derived.add(
      LabTest(
        testName: 'Estimated Glomerular Filtration Rate',
        rawTestName: 'eGFR (CKD-EPI 2021)',
        value: roundedEgfr,
        unit: 'mL/min/1.73m2',
        rangeLow: 90.0,
        rangeHigh: null,
        rangeRaw: '>= 90',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('serum creatinine'),
      ),
    );
  }

  // 2. Serum Anion Gap = Na - (Cl + HCO3)
  final na = val('sodium');
  final cl = val('chloride');
  final hco3 = val('bicarbonate');
  if (na != null && cl != null && hco3 != null) {
    final agap = ((na - (cl + hco3)) * 10).round() / 10.0;
    derived.add(
      LabTest(
        testName: 'Serum Anion Gap',
        rawTestName: 'Anion Gap',
        value: agap,
        unit: 'mEq/L',
        rangeLow: 4.0,
        rangeHigh: 12.0,
        rangeRaw: '4.0 - 12.0',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('sodium') ?? bbox('bicarbonate'),
      ),
    );
  }

  // 3. De Ritis Ratio (AST / ALT)
  final ast = val('aspartate aminotransferase (ast)');
  final alt = val('alanine aminotransferase (alt)');
  if (ast != null && alt != null && alt > 0) {
    final deRitis = ((ast / alt) * 100).round() / 100.0;
    derived.add(
      LabTest(
        testName: 'AST/ALT (De Ritis) Ratio',
        rawTestName: 'AST/ALT Ratio',
        value: deRitis,
        unit: 'ratio',
        rangeLow: 0.8,
        rangeHigh: 1.5,
        rangeRaw: '0.8 - 1.5',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('aspartate aminotransferase (ast)'),
      ),
    );
  }

  // 4. BUN / Creatinine Ratio
  var bun = val('blood urea nitrogen');
  if (bun == null) {
    final urea = val('blood urea');
    if (urea != null) bun = urea / 2.14;
  }
  if (bun != null && creat != null && creat > 0) {
    final bunCr = ((bun / creat) * 10).round() / 10.0;
    derived.add(
      LabTest(
        testName: 'BUN/Creatinine Ratio',
        rawTestName: 'BUN/Creatinine Ratio',
        value: bunCr,
        unit: 'ratio',
        rangeLow: 10.0,
        rangeHigh: 20.0,
        rangeRaw: '10.0 - 20.0',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('serum creatinine'),
      ),
    );
  }

  // 5. Corrected Calcium = Total Calcium + 0.8 * (4.0 - Albumin)
  final ca = val('calcium');
  final alb = val('serum albumin');
  if (ca != null && alb != null) {
    final corrCa = ((ca + 0.8 * (4.0 - alb)) * 100).round() / 100.0;
    derived.add(
      LabTest(
        testName: 'Corrected Calcium',
        rawTestName: 'Corrected Calcium (Albumin-adjusted)',
        value: corrCa,
        unit: 'mg/dL',
        rangeLow: 8.5,
        rangeHigh: 10.5,
        rangeRaw: '8.5 - 10.5',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('calcium'),
      ),
    );
  }

  // 6. Albumin-Globulin Ratio = Albumin / Globulin
  var glob = val('serum globulin');
  if (glob == null) {
    final tp = val('total protein');
    if (tp != null && alb != null && tp > alb) glob = tp - alb;
  }
  if (alb != null && glob != null && glob > 0) {
    final agRatio = ((alb / glob) * 100).round() / 100.0;
    derived.add(
      LabTest(
        testName: 'Albumin-Globulin Ratio',
        rawTestName: 'A/G Ratio',
        value: agRatio,
        unit: 'ratio',
        rangeLow: 1.0,
        rangeHigh: 2.2,
        rangeRaw: '1.0 - 2.2',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('serum albumin'),
      ),
    );
  }

  // 7. Non-HDL Cholesterol = Total Cholesterol - HDL
  final tc = val('total cholesterol');
  final hdl = val('hdl cholesterol');
  if (tc != null && hdl != null && tc >= hdl) {
    final nonHdl = ((tc - hdl) * 10).round() / 10.0;
    derived.add(
      LabTest(
        testName: 'Non-HDL Cholesterol',
        rawTestName: 'Non-HDL Cholesterol',
        value: nonHdl,
        unit: 'mg/dL',
        rangeLow: null,
        rangeHigh: 130.0,
        rangeRaw: '< 130',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('total cholesterol'),
      ),
    );
  }

  // 8. Mentzer Index = MCV / RBC
  final mcv = val('mean corpuscular volume');
  final rbc = val('red blood cell count');
  if (mcv != null && rbc != null && rbc > 0) {
    final mentzer = ((mcv / rbc) * 100).round() / 100.0;
    derived.add(
      LabTest(
        testName: 'Mentzer Index',
        rawTestName: 'Mentzer Index (MCV/RBC)',
        value: mentzer,
        unit: 'ratio',
        rangeLow: null,
        rangeHigh: 13.0,
        rangeRaw: '< 13.0 (Thalassemia) | > 13.0 (Iron Def)',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('mean corpuscular volume'),
      ),
    );
  }

  // 9. Transferrin Saturation = (Iron / TIBC) * 100
  final fe = val('serum iron');
  final tibc = val('total iron binding capacity');
  if (fe != null && tibc != null && tibc > 0) {
    final tsat = (((fe / tibc) * 100.0) * 10).round() / 10.0;
    derived.add(
      LabTest(
        testName: 'Transferrin Saturation',
        rawTestName: 'Transferrin Saturation (TSAT)',
        value: tsat,
        unit: '%',
        rangeLow: 20.0,
        rangeHigh: 50.0,
        rangeRaw: '20.0 - 50.0',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('serum iron'),
      ),
    );
  }

  // 10. Neutrophil-to-Lymphocyte Ratio (NLR)
  final neut = val('neutrophils');
  final lymph = val('lymphocytes');
  if (neut != null && lymph != null && lymph > 0) {
    final nlr = ((neut / lymph) * 100).round() / 100.0;
    derived.add(
      LabTest(
        testName: 'Neutrophil-to-Lymphocyte Ratio',
        rawTestName: 'NLR',
        value: nlr,
        unit: 'ratio',
        rangeLow: 1.0,
        rangeHigh: 3.0,
        rangeRaw: '1.0 - 3.0',
        flagInSource: null,
        ocrConfidence: 'high',
        sourceBbox: bbox('neutrophils'),
      ),
    );
  }

  if (derived.isEmpty) return document;

  final panels = [...document.panels];
  final idx = panels.indexWhere(
    (p) => p.panelName == 'Calculated / Derived Indices',
  );
  if (idx >= 0) {
    final existing = panels[idx].tests.map((t) => t.testName).toSet();
    final toAdd = derived.where((d) => !existing.contains(d.testName));
    panels[idx] = LabPanel(
      panelName: 'Calculated / Derived Indices',
      tests: [...panels[idx].tests, ...toAdd],
    );
  } else {
    panels.add(
      LabPanel(panelName: 'Calculated / Derived Indices', tests: derived),
    );
  }

  return LabDocument(
    documentType: document.documentType,
    patientContext: document.patientContext,
    labName: document.labName,
    panels: panels,
  );
}

// -----------------------------------------------------------------------------
// 2. ARITHMETIC CONSISTENCY & OCR SANITY CHECKER
// -----------------------------------------------------------------------------

List<String> verifyArithmeticConsistency(LabDocument document) {
  final warnings = <String>[];
  final testLookup = <String, double>{};

  for (final panel in document.panels) {
    for (final test in panel.tests) {
      if (test.value != null) {
        testLookup[test.testName.trim().toLowerCase()] = test.value!;
      }
    }
  }

  // 1. Bilirubin sum: Total ≈ Direct + Indirect
  final tb = testLookup['total bilirubin'];
  final db = testLookup['direct bilirubin'];
  final ib = testLookup['indirect bilirubin'];
  if (tb != null && db != null && ib != null && tb > 0) {
    final expected = db + ib;
    final diff = (tb - expected).abs();
    if (diff > 0.4 && (diff / tb) > 0.25) {
      warnings.add(
        'Bilirubin arithmetic mismatch: Total ($tb) differs significantly from Direct ($db) + Indirect ($ib) = ${((expected * 100).round() / 100.0)}',
      );
    }
  }

  // 2. Friedewald LDL check
  final tc = testLookup['total cholesterol'];
  final hdl = testLookup['hdl cholesterol'];
  final ldl = testLookup['ldl cholesterol'];
  final tg = testLookup['triglycerides'];
  if (tc != null && hdl != null && ldl != null && tg != null && tg < 400) {
    final calcLdl = tc - hdl - (tg / 5.0);
    final diff = (ldl - calcLdl).abs();
    if (diff > 30.0) {
      warnings.add(
        'Lipid profile arithmetic mismatch: Reported LDL ($ldl) differs from Friedewald calculated LDL (${((calcLdl * 10).round() / 10.0)})',
      );
    }
  }

  // 3. MCHC check
  final hb = testLookup['hemoglobin'];
  final hct = testLookup['hematocrit'];
  final mchc = testLookup['mean corpuscular hemoglobin concentration'];
  if (hb != null && hct != null && mchc != null && hct > 0) {
    final calcMchc = (hb * 100.0) / hct;
    final diff = (mchc - calcMchc).abs();
    if (diff > 4.0) {
      warnings.add(
        'CBC indices arithmetic mismatch: Reported MCHC ($mchc) differs from (Hb*100)/Hct (${((calcMchc * 10).round() / 10.0)})',
      );
    }
  }

  return warnings;
}

// -----------------------------------------------------------------------------
// 3. MULTI-TIER FLAGGING & PANIC DETECTION
// -----------------------------------------------------------------------------

/// Annotate each test with abnormal, direction, severity, and panic flags.
/// Returns a map representation compatible with wire schema and ResultEnvelope.
Map<String, dynamic> flagSingleValues(LabDocument document) {
  final panelsJson = <Map<String, dynamic>>[];

  for (final panel in document.panels) {
    final testsJson = <Map<String, dynamic>>[];
    for (final test in panel.tests) {
      final val = test.value;
      final low = test.rangeLow;
      final high = test.rangeHigh;
      final tMap = test.toJson();

      if (val == null || (low == null && high == null)) {
        tMap['abnormal'] = null;
        tMap['direction'] = null;
        tMap['severity'] = null;
        tMap['is_panic_value'] = false;
        testsJson.add(tMap);
        continue;
      }

      final panic = standardPanicThresholds[test.testName];
      var isPanic = false;
      if (panic?.low != null && val <= panic!.low!) {
        isPanic = true;
      } else if (panic?.high != null && val >= panic!.high!) {
        isPanic = true;
      }
      tMap['is_panic_value'] = isPanic;

      if (low != null && val < low) {
        tMap['abnormal'] = true;
        tMap['direction'] = 'low';
        if (isPanic) {
          tMap['severity'] = 'critical';
        } else if (low > 0 && (low - val) / low > 0.35) {
          tMap['severity'] = 'severe';
        } else if (low > 0 && (low - val) / low > 0.15) {
          tMap['severity'] = 'moderate';
        } else {
          tMap['severity'] = 'mild';
        }
      } else if (high != null && val > high) {
        tMap['abnormal'] = true;
        tMap['direction'] = 'high';
        if (isPanic) {
          tMap['severity'] = 'critical';
        } else if (high > 0 && (val - high) / high > 0.50) {
          tMap['severity'] = 'severe';
        } else if (high > 0 && (val - high) / high > 0.20) {
          tMap['severity'] = 'moderate';
        } else {
          tMap['severity'] = 'mild';
        }
      } else {
        tMap['abnormal'] = false;
        tMap['direction'] = null;
        tMap['severity'] = 'normal';
      }

      testsJson.add(tMap);
    }
    panelsJson.add({'panel_name': panel.panelName, 'tests': testsJson});
  }

  return {
    'document_type': document.documentType,
    'patient_context': document.patientContext?.toJson(),
    'lab_name': document.labName,
    'panels': panelsJson,
  };
}

// -----------------------------------------------------------------------------
// 4. CLINICAL PATTERN MATCHER
// -----------------------------------------------------------------------------

bool _testMatchesCondition(
  Map<String, dynamic> test,
  ClinicalCondition cond,
  Map<String, Map<String, dynamic>> allTests,
) {
  final wanted = cond.testName.trim().toLowerCase();
  final norm = (test['test_name'] as String? ?? '').trim().toLowerCase();
  final raw = (test['raw_test_name'] as String? ?? '').trim().toLowerCase();
  if (wanted != norm && wanted != raw) return false;

  // Direction check
  if (cond.direction != null) {
    if (test['abnormal'] != true || test['direction'] != cond.direction) {
      return false;
    }
  }

  // Arithmetic operator check
  final op = cond.operator;
  final valNum = test['value'] as num?;
  if (op != null && valNum != null) {
    final val = valNum.toDouble();
    if (op == '>' && cond.threshold != null && !(val > cond.threshold!)) {
      return false;
    }
    if (op == '>=' && cond.threshold != null && !(val >= cond.threshold!)) {
      return false;
    }
    if (op == '<' && cond.threshold != null && !(val < cond.threshold!)) {
      return false;
    }
    if (op == '<=' && cond.threshold != null && !(val <= cond.threshold!)) {
      return false;
    }
    if (op == 'between') {
      if (cond.low != null && val < cond.low!) return false;
      if (cond.high != null && val > cond.high!) return false;
    }
    if (op == 'ratio_gt' || op == 'ratio_lt') {
      final otherName = (cond.ratioWith ?? '').trim().toLowerCase();
      final otherTest = allTests[otherName];
      final otherVal = (otherTest?['value'] as num?)?.toDouble();
      if (otherVal == null || otherVal == 0) return false;
      final ratio = val / otherVal;
      if (op == 'ratio_gt' && cond.threshold != null && !(ratio > cond.threshold!)) {
        return false;
      }
      if (op == 'ratio_lt' && cond.threshold != null && !(ratio < cond.threshold!)) {
        return false;
      }
    }
  }

  return true;
}

List<FlaggedPattern> detectClinicalPatterns(
  Map<String, dynamic> flaggedDoc,
  List<ClinicalRule> rules,
) {
  final flaggedPatterns = <FlaggedPattern>[];
  final seen = <String>{};

  // Document-wide test maps
  final allTestsMap = <String, Map<String, dynamic>>{};
  final allTestsList = <Map<String, dynamic>>[];

  final panels = flaggedDoc['panels'] as List? ?? [];
  for (final panel in panels) {
    if (panel is! Map) continue;
    final tests = panel['tests'] as List? ?? [];
    for (final test in tests) {
      if (test is! Map<String, dynamic>) continue;
      final name = (test['test_name'] ?? test['raw_test_name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (name.isNotEmpty) allTestsMap[name] = test;
      allTestsList.add(test);
    }
  }

  for (final rule in rules) {
    final isDocScope = rule.scope == 'document';
    final matchType = rule.matchType;
    final minCount =
        rule.minCount ?? (matchType == 'any' ? 1 : rule.conditions.length);

    final evaluationContexts = <({String name, List<Map<String, dynamic>> tests})>[];
    if (isDocScope) {
      evaluationContexts.add((name: 'Document (Cross-Panel)', tests: allTestsList));
    } else {
      for (final panel in panels) {
        if (panel is! Map) continue;
        final pName = panel['panel_name'] as String? ?? 'Ungrouped';
        final pTests = (panel['tests'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        evaluationContexts.add((name: pName, tests: pTests));
      }
    }

    for (final ctx in evaluationContexts) {
      final triggering = <Map<String, dynamic>>[];
      final usedIndices = <int>{};
      var satisfied = 0;

      for (final cond in rule.conditions) {
        final condName = cond.testName.trim().toLowerCase();
        Map<String, dynamic>? matched;

        // Check if an already-matched test of the same name satisfies condition
        for (final t in triggering) {
          final tName = (t['test_name'] ?? t['raw_test_name'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (tName == condName && _testMatchesCondition(t, cond, allTestsMap)) {
            matched = t;
            break;
          }
        }

        // Otherwise search pool
        if (matched == null) {
          for (var i = 0; i < ctx.tests.length; i++) {
            if (!usedIndices.contains(i)) {
              final candidate = ctx.tests[i];
              if (_testMatchesCondition(candidate, cond, allTestsMap)) {
                matched = candidate;
                usedIndices.add(i);
                break;
              }
            }
          }
        }

        if (matched != null) {
          satisfied++;
          if (!triggering.contains(matched)) {
            triggering.add(matched);
          }
        }
      }

      var isMatch = false;
      if (matchType == 'all' && satisfied == rule.conditions.length) {
        isMatch = true;
      } else if (matchType == 'any' && satisfied >= 1) {
        isMatch = true;
      } else if (matchType == 'min_count' && satisfied >= minCount) {
        isMatch = true;
      }

      if (isMatch && triggering.isNotEmpty) {
        final trigKey = triggering
            .map((t) => '${t['test_name']}:${t['direction']}:${t['value']}')
            .join('|');
        final key = '${rule.patternName}::$trigKey';
        if (!seen.add(key)) continue;

        flaggedPatterns.add(
          FlaggedPattern(
            patternName: rule.patternName,
            surfacedText: rule.surfacedText,
            matchType: rule.matchType,
            panelName: ctx.name,
            triggeringTests: triggering.map(TriggeringTest.fromJson).toList(),
          ),
        );
      }
    }
  }

  return flaggedPatterns;
}

// -----------------------------------------------------------------------------
// 5. EMBEDDED STANDARD CLINICAL RULES (Always available offline)
// -----------------------------------------------------------------------------

final defaultClinicalRules = <ClinicalRule>[
  ClinicalRule(
    patternName: 'microcytic_hypochromic_anemia',
    category: 'Hematology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Hemoglobin', direction: 'low'),
      ClinicalCondition(testName: 'Mean Corpuscular Volume', operator: '<', threshold: 80.0),
      ClinicalCondition(testName: 'Mean Corpuscular Hemoglobin', operator: '<', threshold: 27.0),
    ],
    surfacedText: 'Microcytic hypochromic red cell indices consistent with iron deficiency or thalassemia trait',
    clinicalImplication: 'Low MCV (<80 fL) and low MCH (<27 pg) with anemia suggest impaired heme or globin synthesis.',
    differentialDiagnosis: const ['Iron Deficiency Anemia', 'Thalassemia Minor/Trait', 'Anemia of Chronic Disease'],
  ),
  ClinicalRule(
    patternName: 'severe_anemia_critical',
    category: 'Hematology',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Hemoglobin', operator: '<', threshold: 7.0),
    ],
    surfacedText: 'CRITICAL: Severe anemia (Hb < 7.0 g/dL) — urgent clinical evaluation required',
    clinicalImplication: 'Hemoglobin below 7.0 g/dL carries significant hemodynamic compromise risk.',
    differentialDiagnosis: const ['Severe Acute Hemorrhage', 'Decompensated Hemolysis', 'Aplastic Crisis'],
  ),
  ClinicalRule(
    patternName: 'critical_hyperkalemia',
    category: 'Electrolytes',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Potassium', operator: '>', threshold: 6.0),
    ],
    surfacedText: 'CRITICAL: Severe hyperkalemia (K+ > 6.0 mEq/L) — immediate cardiac arrhythmia risk',
    clinicalImplication: 'Potassium >6.0 mEq/L poses imminent threat of lethal cardiac dysrhythmias.',
    differentialDiagnosis: const ['Renal Failure', 'Potassium-Sparing Diuretics', 'Rhabdomyolysis'],
  ),
  ClinicalRule(
    patternName: 'critical_hypokalemia',
    category: 'Electrolytes',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Potassium', operator: '<', threshold: 2.8),
    ],
    surfacedText: 'CRITICAL: Severe hypokalemia (K+ < 2.8 mEq/L) — risk of cardiac dysrhythmia and muscle paralysis',
    clinicalImplication: 'Serum potassium <2.8 mEq/L precipitates cardiac arrhythmias and muscle weakness.',
    differentialDiagnosis: const ['GI Losses', 'Loop/Thiazide Diuretics', 'Hyperaldosteronism'],
  ),
  ClinicalRule(
    patternName: 'critical_thrombocytopenia',
    category: 'Hematology',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Platelet Count', operator: '<', threshold: 20.0),
    ],
    surfacedText: 'CRITICAL: Severe thrombocytopenia (Platelets < 20,000 /uL) — high risk of spontaneous hemorrhage',
    clinicalImplication: 'Platelet counts below 20,000 /uL markedly elevate risk of spontaneous bleeding.',
    differentialDiagnosis: const ['ITP', 'TTP', 'Aplastic Anemia', 'DIC'],
  ),
  ClinicalRule(
    patternName: 'high_anion_gap_metabolic_acidosis',
    category: 'Electrolytes',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Serum Anion Gap', operator: '>', threshold: 14.0),
      ClinicalCondition(testName: 'Bicarbonate', operator: '<', threshold: 22.0),
    ],
    surfacedText: 'CRITICAL: High anion gap metabolic acidosis (Anion Gap > 14 mEq/L with low bicarbonate)',
    clinicalImplication: 'Unmeasured organic anions accumulated in serum (ketoacidosis, lactic acidosis, uremia, toxic ingestion).',
    differentialDiagnosis: const ['Diabetic Ketoacidosis (DKA)', 'Lactic Acidosis', 'Uremic Acidosis', 'Toxic Alcohols'],
  ),
  ClinicalRule(
    patternName: 'prerenal_azotemia_pattern',
    category: 'Nephrology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Blood Urea Nitrogen', direction: 'high'),
      ClinicalCondition(testName: 'Serum Creatinine', direction: 'high'),
      ClinicalCondition(testName: 'Blood Urea Nitrogen', operator: 'ratio_gt', ratioWith: 'Serum Creatinine', threshold: 20.0),
    ],
    surfacedText: 'Elevated BUN-to-creatinine ratio (>20:1) suggestive of prerenal azotemia or hypoperfusion',
    clinicalImplication: 'Disproportionate BUN elevation relative to creatinine reflects enhanced tubular urea reabsorption.',
    differentialDiagnosis: const ['Dehydration', 'Congestive Heart Failure', 'Upper GI Bleed'],
  ),
  ClinicalRule(
    patternName: 'alcoholic_liver_pattern',
    category: 'Hepatology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Aspartate Aminotransferase (AST)', direction: 'high'),
      ClinicalCondition(testName: 'Alanine Aminotransferase (ALT)', direction: 'high'),
      ClinicalCondition(testName: 'Aspartate Aminotransferase (AST)', operator: 'ratio_gt', ratioWith: 'Alanine Aminotransferase (ALT)', threshold: 2.0),
    ],
    surfacedText: 'AST-to-ALT ratio (De Ritis ratio) > 2.0 consistent with alcoholic hepatitis or advanced cirrhosis',
    clinicalImplication: 'AST/ALT ratio exceeding 2.0 is highly characteristic of alcoholic liver disease.',
    differentialDiagnosis: const ['Alcoholic Hepatitis', 'Established Cirrhosis', "Wilson's Disease"],
  ),
  ClinicalRule(
    patternName: 'acute_hepatocellular_injury',
    category: 'Hepatology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Alanine Aminotransferase (ALT)', operator: '>', threshold: 120.0),
      ClinicalCondition(testName: 'Aspartate Aminotransferase (AST)', operator: '>', threshold: 100.0),
    ],
    surfacedText: 'Marked transaminase elevation indicating acute hepatocellular injury',
    clinicalImplication: 'Co-elevation of ALT and AST greater than 3-fold above normal signifies active hepatocyte cytolysis.',
    differentialDiagnosis: const ['Viral Hepatitis', 'Drug-Induced Liver Injury', 'Ischemic Hepatitis'],
  ),
  ClinicalRule(
    patternName: 'critical_hyperglycemia_dka_risk',
    category: 'Endocrinology',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Random Blood Glucose', operator: '>', threshold: 300.0),
    ],
    surfacedText: 'CRITICAL: Severe hyperglycemia (Glucose > 300 mg/dL) — urgent risk of ketoacidosis or hyperosmolar coma',
    clinicalImplication: 'Profound hyperglycemia requires urgent medical assessment for DKA or HHS.',
    differentialDiagnosis: const ['DKA', 'HHS', 'Medication Non-Adherence'],
  ),
  ClinicalRule(
    patternName: 'critical_hypoglycemia',
    category: 'Endocrinology',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Random Blood Glucose', operator: '<', threshold: 50.0),
    ],
    surfacedText: 'CRITICAL: Severe hypoglycemia (Glucose < 50 mg/dL) — emergency glucose administration required',
    clinicalImplication: 'Blood glucose <50 mg/dL causes neuroglycopenic symptoms and seizure risk.',
    differentialDiagnosis: const ['Insulin Excess', 'Sepsis', 'Adrenal Insufficiency'],
  ),
  ClinicalRule(
    patternName: 'severe_hypertriglyceridemia_pancreatitis_risk',
    category: 'Cardiology',
    severity: 'critical',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Triglycerides', operator: '>', threshold: 500.0),
    ],
    surfacedText: 'CRITICAL: Severe hypertriglyceridemia (Triglycerides > 500 mg/dL) — substantial risk of acute pancreatitis',
    clinicalImplication: 'Triglycerides >500 mg/dL increase risk of chylomicronemia and acute pancreatitis.',
    differentialDiagnosis: const ['Familial Chylomicronemia', 'Secondary Hypertriglyceridemia'],
  ),
  ClinicalRule(
    patternName: 'primary_hypothyroidism',
    category: 'Endocrinology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Thyroid Stimulating Hormone', operator: '>', threshold: 5.0),
      ClinicalCondition(testName: 'Free Thyroxine (FT4)', direction: 'low'),
    ],
    surfacedText: 'Overt primary hypothyroidism with elevated TSH and subnormal free T4',
    clinicalImplication: 'Elevated TSH with low FT4 confirms failure of thyroid hormone production.',
    differentialDiagnosis: const ["Hashimoto's Thyroiditis", 'Post-Radioiodine Ablation', 'Iodine Deficiency'],
  ),
  ClinicalRule(
    patternName: 'primary_hyperthyroidism',
    category: 'Endocrinology',
    severity: 'warning',
    scope: 'document',
    matchType: 'all',
    conditions: const [
      ClinicalCondition(testName: 'Thyroid Stimulating Hormone', operator: '<', threshold: 0.1),
      ClinicalCondition(testName: 'Free Thyroxine (FT4)', direction: 'high'),
    ],
    surfacedText: 'Overt primary hyperthyroidism (thyrotoxicosis) with suppressed TSH and elevated free T4',
    clinicalImplication: 'Suppressed TSH with elevated free T4 indicates autonomous thyroid hormone excess.',
    differentialDiagnosis: const ["Graves' Disease", 'Toxic Multinodular Goiter', 'Toxic Adenoma'],
  ),
];

// -----------------------------------------------------------------------------
// 6. ON-DEVICE FULL STAGE 3 PIPELINE
// -----------------------------------------------------------------------------

/// Execute the complete Stage 3 pipeline on-device.
/// Takes a Stage 2 LabDocument and returns the annotated document,
/// list of clinical patterns, and any arithmetic consistency warnings.
LabDocumentAnnotationResult annotateLabDocument(
  LabDocument document, {
  List<ClinicalRule>? rules,
}) {
  final withDerived = calculateDerivedIndices(document);
  final warnings = verifyArithmeticConsistency(withDerived);
  final flaggedMap = flagSingleValues(withDerived);
  final activeRules = rules ?? defaultClinicalRules;
  final patterns = detectClinicalPatterns(flaggedMap, activeRules);

  // Reconstruct typed LabDocument from flaggedMap so abnormal/direction fields are populated
  final annotatedDoc = LabDocument.fromJson(flaggedMap);
  final hasPanic = patterns.any((p) => p.severity == 'critical') ||
      (flaggedMap['panels'] as List? ?? []).any(
        (p) => (p['tests'] as List? ?? []).any((t) => t['is_panic_value'] == true),
      );

  return LabDocumentAnnotationResult(
    document: annotatedDoc,
    patterns: patterns,
    warnings: warnings,
    hasPanicValues: hasPanic,
  );
}
