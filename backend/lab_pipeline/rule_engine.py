"""
Stage 3 — Deterministic arithmetic and clinical rule engine for lab reports.

Pure functions only: no model calls, no network, no side effects. Takes the
Stage 2 lab report JSON and returns the fully annotated version with:

1. Arithmetic Derived Indices (3a-derived):
   - Computes clinically standard derived metrics when components exist:
     eGFR (CKD-EPI 2021), Serum Anion Gap, De Ritis (AST/ALT) Ratio,
     BUN/Creatinine Ratio, Corrected Calcium (for hypoalbuminemia),
     Albumin-Globulin Ratio, Non-HDL Cholesterol, Mentzer Index,
     Transferrin Saturation, and Neutrophil-to-Lymphocyte Ratio (NLR).
   - Stamped with calculation_method='derived', formula description, and input tests.

2. Arithmetic Consistency Validator (3a-consistency):
   - Validates arithmetic relationships (e.g. Total Bilirubin vs Direct+Indirect,
     Friedewald LDL check, MCHC check) to detect potential OCR misreads.

3. Multi-tier Single-value Flagging & Panic/Critical Detection (3b-single):
   - Evaluates value against range_low/range_high.
   - Severity classification: normal, mild, moderate, severe, critical.
   - Emergency panic thresholds (e.g. Potassium < 2.8 or > 6.2 mEq/L,
     Platelets < 20,000 /uL, Hemoglobin < 7.0 g/dL, Glucose < 50 or > 400 mg/dL).
   - Optional standard reference range fallback when printed ranges are missing.

4. Comprehensive Clinical Pattern Matching (3c-patterns):
   - Evaluates multi-test combination rules with arithmetic expressions
     (>, <, >=, <=, between, ratios) across 9 clinical specialties.
   - Supports both panel-scoped and document-scoped (cross-panel) matching.
   - Traceable to triggering values and source_bbox.
"""

import copy
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

RULES_DIR = Path(__file__).parent / 'rules'
DEFAULT_RULES_PATH = RULES_DIR / 'clinical_rules.json'
LEGACY_RULES_PATH = Path(__file__).parent / 'rules.json'
DEFAULT_RANGES_PATH = RULES_DIR / 'reference_ranges.json'
DEFAULT_CONVERSIONS_PATH = RULES_DIR / 'unit_conversions.json'


# -----------------------------------------------------------------------------
# RULE TABLE LOADING & VALIDATION
# -----------------------------------------------------------------------------

def load_rule_table(path=None) -> dict:
    """Load and validate the external clinical rule table.

    Returns {"rules": [...], "review_status": str, "source": str}.
    Raises ValueError on structurally invalid rules.
    """
    if path:
        rules_path = Path(path)
    elif DEFAULT_RULES_PATH.exists():
        rules_path = DEFAULT_RULES_PATH
    else:
        rules_path = LEGACY_RULES_PATH

    with open(rules_path, 'r', encoding='utf-8') as f:
        table = json.load(f)

    if isinstance(table, list):
        table = {'rules': table, '_review_status': 'UNKNOWN — rule table has no review status'}

    rules = table.get('rules')
    if not isinstance(rules, list):
        raise ValueError(f'Rule table {rules_path} must contain a "rules" list')

    validated = []
    for rule in rules:
        validated.append(_validate_rule(rule, rules_path))

    return {
        'rules': validated,
        'review_status': table.get('_review_status', 'UNKNOWN'),
        'source': str(rules_path),
    }


def _validate_rule(rule: dict, rules_path: Path) -> dict:
    if not isinstance(rule, dict):
        raise ValueError(f'Rule table {rules_path}: each rule must be an object')
    if not rule.get('pattern_name') or not isinstance(rule['pattern_name'], str):
        raise ValueError(f'Rule table {rules_path}: rule missing string "pattern_name"')

    conditions = rule.get('conditions')
    if not isinstance(conditions, list) or not conditions:
        raise ValueError(f'Rule table {rules_path}: rule "{rule["pattern_name"]}" needs a non-empty conditions list')

    for cond in conditions:
        if not isinstance(cond, dict) or not cond.get('test_name'):
            raise ValueError(
                f'Rule table {rules_path}: rule "{rule["pattern_name"]}" has a condition without "test_name"'
            )
        direction = cond.get('direction')
        if direction is not None and direction not in ('high', 'low'):
            raise ValueError(
                f'Rule table {rules_path}: rule "{rule["pattern_name"]}" condition direction must be "high" or "low"'
            )

    match_type = rule.get('match_type', 'all')
    if match_type not in ('all', 'any', 'min_count'):
        raise ValueError(
            f'Rule table {rules_path}: rule "{rule["pattern_name"]}" match_type must be "all", "any", or "min_count"'
        )

    if not rule.get('surfaced_text') or not isinstance(rule['surfaced_text'], str):
        raise ValueError(f'Rule table {rules_path}: rule "{rule["pattern_name"]}" missing "surfaced_text"')

    return rule


def load_reference_ranges(path=None) -> dict:
    """Load standard reference ranges and panic thresholds."""
    ranges_path = Path(path) if path else DEFAULT_RANGES_PATH
    if not ranges_path.exists():
        return {}
    with open(ranges_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data.get('ranges', {})


def load_unit_conversions(path=None) -> dict:
    """Load unit conversion factors."""
    conv_path = Path(path) if path else DEFAULT_CONVERSIONS_PATH
    if not conv_path.exists():
        return {}
    with open(conv_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return data.get('conversions', {})


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


# -----------------------------------------------------------------------------
# 1. ARITHMETIC DERIVED INDICES CALCULATOR (Stage 3a-derived)
# -----------------------------------------------------------------------------

def calculate_derived_indices(document: dict) -> dict:
    """Compute clinically standard derived indices when component tests are present.

    Computes:
    - eGFR (CKD-EPI 2021) from Creatinine, Age, Sex
    - Serum Anion Gap from Na, Cl, HCO3
    - De Ritis Ratio from AST, ALT
    - BUN/Creatinine Ratio from BUN, Creatinine
    - Corrected Calcium from Total Calcium, Albumin
    - Albumin-Globulin Ratio from Albumin, Globulin / Total Protein
    - Non-HDL Cholesterol from Total Cholesterol, HDL
    - Mentzer Index from MCV, RBC
    - Transferrin Saturation from Iron, TIBC
    - Neutrophil-to-Lymphocyte Ratio (NLR) from Neutrophils, Lymphocytes

    Derived tests are appended into a 'Calculated / Derived Indices' panel
    with full provenance (calculation_method='derived', formula, input_tests).
    """
    doc = copy.deepcopy(document)
    patient_ctx = doc.get('patient_context') or {}
    age = patient_ctx.get('age')
    sex = str(patient_ctx.get('sex') or '').strip().lower()

    # Index all existing tests by lowercase canonical name
    test_lookup: Dict[str, dict] = {}
    for panel in doc.get('panels') or []:
        for test in panel.get('tests') or []:
            name = (test.get('test_name') or test.get('raw_test_name') or '').strip().lower()
            if name and test.get('value') is not None and _is_number(test.get('value')):
                test_lookup[name] = test

    def get_val(canonical_name: str) -> Optional[float]:
        t = test_lookup.get(canonical_name.lower())
        return float(t['value']) if t and _is_number(t.get('value')) else None

    def get_bbox(canonical_name: str) -> Optional[dict]:
        t = test_lookup.get(canonical_name.lower())
        return t.get('source_bbox') if t else None

    derived_tests = []

    # 1. eGFR via CKD-EPI 2021 (race-free)
    creat = get_val('serum creatinine')
    if creat is not None and creat > 0 and age is not None and _is_number(age) and age >= 18:
        is_female = sex in ('f', 'female', 'woman')
        kappa = 0.7 if is_female else 0.9
        alpha = -0.241 if is_female else -0.302
        gender_mult = 1.012 if is_female else 1.000
        scr_k = creat / kappa
        egfr = 142.0 * (min(scr_k, 1.0) ** alpha) * (max(scr_k, 1.0) ** -1.200) * (0.9938 ** float(age)) * gender_mult
        egfr = round(egfr, 1)

        derived_tests.append({
            'test_name': 'Estimated Glomerular Filtration Rate',
            'raw_test_name': 'eGFR (CKD-EPI 2021)',
            'value': egfr,
            'unit': 'mL/min/1.73m2',
            'range_low': 90.0,
            'range_high': None,
            'range_raw': '>= 90',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('serum creatinine'),
            'calculation_method': 'derived',
            'formula': 'CKD-EPI (2021 race-free equation)',
            'input_tests': ['Serum Creatinine'],
        })

    # 2. Serum Anion Gap = Na - (Cl + HCO3)
    na = get_val('sodium')
    cl = get_val('chloride')
    hco3 = get_val('bicarbonate')
    if na is not None and cl is not None and hco3 is not None:
        agap = round(na - (cl + hco3), 1)
        derived_tests.append({
            'test_name': 'Serum Anion Gap',
            'raw_test_name': 'Anion Gap',
            'value': agap,
            'unit': 'mEq/L',
            'range_low': 4.0,
            'range_high': 12.0,
            'range_raw': '4.0 - 12.0',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('sodium') or get_bbox('bicarbonate'),
            'calculation_method': 'derived',
            'formula': 'Sodium - (Chloride + Bicarbonate)',
            'input_tests': ['Sodium', 'Chloride', 'Bicarbonate'],
        })

    # 3. De Ritis Ratio (AST / ALT)
    ast = get_val('aspartate aminotransferase (ast)')
    alt = get_val('alanine aminotransferase (alt)')
    if ast is not None and alt is not None and alt > 0:
        de_ritis = round(ast / alt, 2)
        derived_tests.append({
            'test_name': 'AST/ALT (De Ritis) Ratio',
            'raw_test_name': 'AST/ALT Ratio',
            'value': de_ritis,
            'unit': 'ratio',
            'range_low': 0.8,
            'range_high': 1.5,
            'range_raw': '0.8 - 1.5',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('aspartate aminotransferase (ast)'),
            'calculation_method': 'derived',
            'formula': 'AST / ALT',
            'input_tests': ['Aspartate Aminotransferase (AST)', 'Alanine Aminotransferase (ALT)'],
        })

    # 4. BUN / Creatinine Ratio
    bun = get_val('blood urea nitrogen')
    if bun is None:
        urea = get_val('blood urea')
        if urea is not None:
            bun = urea / 2.14  # standard molecular weight conversion
    if bun is not None and creat is not None and creat > 0:
        bun_cr = round(bun / creat, 1)
        derived_tests.append({
            'test_name': 'BUN/Creatinine Ratio',
            'raw_test_name': 'BUN/Creatinine Ratio',
            'value': bun_cr,
            'unit': 'ratio',
            'range_low': 10.0,
            'range_high': 20.0,
            'range_raw': '10.0 - 20.0',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('serum creatinine'),
            'calculation_method': 'derived',
            'formula': 'BUN / Serum Creatinine',
            'input_tests': ['Blood Urea Nitrogen', 'Serum Creatinine'],
        })

    # 5. Corrected Calcium = Total Calcium + 0.8 * (4.0 - Albumin)
    ca = get_val('calcium')
    alb = get_val('serum albumin')
    if ca is not None and alb is not None:
        corr_ca = round(ca + 0.8 * (4.0 - alb), 2)
        derived_tests.append({
            'test_name': 'Corrected Calcium',
            'raw_test_name': 'Corrected Calcium (Albumin-adjusted)',
            'value': corr_ca,
            'unit': 'mg/dL',
            'range_low': 8.5,
            'range_high': 10.5,
            'range_raw': '8.5 - 10.5',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('calcium'),
            'calculation_method': 'derived',
            'formula': 'Measured Calcium + 0.8 * (4.0 - Serum Albumin)',
            'input_tests': ['Calcium', 'Serum Albumin'],
        })

    # 6. Albumin-Globulin Ratio = Albumin / Globulin
    glob = get_val('serum globulin')
    if glob is None:
        tp = get_val('total protein')
        if tp is not None and alb is not None and tp > alb:
            glob = tp - alb
    if alb is not None and glob is not None and glob > 0:
        ag_ratio = round(alb / glob, 2)
        derived_tests.append({
            'test_name': 'Albumin-Globulin Ratio',
            'raw_test_name': 'A/G Ratio',
            'value': ag_ratio,
            'unit': 'ratio',
            'range_low': 1.0,
            'range_high': 2.2,
            'range_raw': '1.0 - 2.2',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('serum albumin'),
            'calculation_method': 'derived',
            'formula': 'Serum Albumin / Serum Globulin',
            'input_tests': ['Serum Albumin', 'Serum Globulin'],
        })

    # 7. Non-HDL Cholesterol = Total Cholesterol - HDL Cholesterol
    tc = get_val('total cholesterol')
    hdl = get_val('hdl cholesterol')
    if tc is not None and hdl is not None and tc >= hdl:
        non_hdl = round(tc - hdl, 1)
        derived_tests.append({
            'test_name': 'Non-HDL Cholesterol',
            'raw_test_name': 'Non-HDL Cholesterol',
            'value': non_hdl,
            'unit': 'mg/dL',
            'range_low': None,
            'range_high': 130.0,
            'range_raw': '< 130',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('total cholesterol'),
            'calculation_method': 'derived',
            'formula': 'Total Cholesterol - HDL Cholesterol',
            'input_tests': ['Total Cholesterol', 'HDL Cholesterol'],
        })

    # 8. Mentzer Index = MCV / RBC
    mcv = get_val('mean corpuscular volume')
    rbc = get_val('red blood cell count')
    if mcv is not None and rbc is not None and rbc > 0:
        mentzer = round(mcv / rbc, 2)
        derived_tests.append({
            'test_name': 'Mentzer Index',
            'raw_test_name': 'Mentzer Index (MCV/RBC)',
            'value': mentzer,
            'unit': 'ratio',
            'range_low': None,
            'range_high': 13.0,
            'range_raw': '< 13.0 (Thalassemia) | > 13.0 (Iron Def)',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('mean corpuscular volume'),
            'calculation_method': 'derived',
            'formula': 'MCV / RBC Count',
            'input_tests': ['Mean Corpuscular Volume', 'Red Blood Cell Count'],
        })

    # 9. Transferrin Saturation = (Iron / TIBC) * 100
    fe = get_val('serum iron')
    tibc = get_val('total iron binding capacity')
    if fe is not None and tibc is not None and tibc > 0:
        tsat = round((fe / tibc) * 100.0, 1)
        derived_tests.append({
            'test_name': 'Transferrin Saturation',
            'raw_test_name': 'Transferrin Saturation (TSAT)',
            'value': tsat,
            'unit': '%',
            'range_low': 20.0,
            'range_high': 50.0,
            'range_raw': '20.0 - 50.0',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('serum iron'),
            'calculation_method': 'derived',
            'formula': '(Serum Iron / TIBC) * 100',
            'input_tests': ['Serum Iron', 'Total Iron Binding Capacity'],
        })

    # 10. Neutrophil-to-Lymphocyte Ratio (NLR)
    neut = get_val('neutrophils')
    lymph = get_val('lymphocytes')
    if neut is not None and lymph is not None and lymph > 0:
        nlr = round(neut / lymph, 2)
        derived_tests.append({
            'test_name': 'Neutrophil-to-Lymphocyte Ratio',
            'raw_test_name': 'NLR',
            'value': nlr,
            'unit': 'ratio',
            'range_low': 1.0,
            'range_high': 3.0,
            'range_raw': '1.0 - 3.0',
            'flag_in_source': None,
            'ocr_confidence': 'high',
            'source_bbox': get_bbox('neutrophils'),
            'calculation_method': 'derived',
            'formula': 'Neutrophils / Lymphocytes',
            'input_tests': ['Neutrophils', 'Lymphocytes'],
        })

    if not derived_tests:
        return doc

    # Merge or append derived tests into a dedicated panel
    panels = list(doc.get('panels') or [])
    derived_panel = next((p for p in panels if p.get('panel_name') == 'Calculated / Derived Indices'), None)
    if derived_panel is not None:
        existing_names = {t.get('test_name') for t in derived_panel.get('tests', [])}
        for dt in derived_tests:
            if dt['test_name'] not in existing_names:
                derived_panel.setdefault('tests', []).append(dt)
    else:
        panels.append({
            'panel_name': 'Calculated / Derived Indices',
            'tests': derived_tests,
        })

    doc['panels'] = panels
    return doc


# -----------------------------------------------------------------------------
# 2. ARITHMETIC CONSISTENCY & OCR SANITY CHECKER (Stage 3a-consistency)
# -----------------------------------------------------------------------------

def verify_arithmetic_consistency(document: dict) -> List[str]:
    """Check arithmetic consistency across related tests to detect potential OCR errors."""
    warnings: List[str] = []
    test_lookup = {}
    for panel in document.get('panels') or []:
        for test in panel.get('tests') or []:
            name = (test.get('test_name') or test.get('raw_test_name') or '').strip().lower()
            if name and _is_number(test.get('value')):
                test_lookup[name] = float(test['value'])

    # 1. Bilirubin sum: Total ≈ Direct + Indirect
    tb = test_lookup.get('total bilirubin')
    db = test_lookup.get('direct bilirubin')
    ib = test_lookup.get('indirect bilirubin')
    if tb is not None and db is not None and ib is not None and tb > 0:
        expected = db + ib
        diff = abs(tb - expected)
        if diff > 0.4 and (diff / tb) > 0.25:
            warnings.append(
                f'Bilirubin arithmetic mismatch: Total ({tb}) differs significantly from Direct ({db}) + Indirect ({ib}) = {round(expected, 2)}'
            )

    # 2. Friedewald LDL check: Total ≈ HDL + LDL + (Triglycerides / 5)
    tc = test_lookup.get('total cholesterol')
    hdl = test_lookup.get('hdl cholesterol')
    ldl = test_lookup.get('ldl cholesterol')
    tg = test_lookup.get('triglycerides')
    if tc is not None and hdl is not None and ldl is not None and tg is not None and tg < 400:
        calc_ldl = tc - hdl - (tg / 5.0)
        diff = abs(ldl - calc_ldl)
        if diff > 30.0:
            warnings.append(
                f'Lipid profile arithmetic mismatch: Reported LDL ({ldl}) differs from Friedewald calculated LDL ({round(calc_ldl, 1)})'
            )

    # 3. MCHC check: MCHC ≈ (Hemoglobin * 100) / Hematocrit
    hb = test_lookup.get('hemoglobin')
    hct = test_lookup.get('hematocrit')
    mchc = test_lookup.get('mean corpuscular hemoglobin concentration')
    if hb is not None and hct is not None and mchc is not None and hct > 0:
        calc_mchc = (hb * 100.0) / hct
        diff = abs(mchc - calc_mchc)
        if diff > 4.0:
            warnings.append(
                f'CBC indices arithmetic mismatch: Reported MCHC ({mchc}) differs from (Hb*100)/Hct ({round(calc_mchc, 1)})'
            )

    return warnings


# -----------------------------------------------------------------------------
# 3. MULTI-TIER SINGLE-VALUE FLAGGING & PANIC DETECTION (Stage 3b-single)
# -----------------------------------------------------------------------------

def flag_single_values(document: dict, ref_ranges: Optional[dict] = None, use_fallback_ranges: bool = False) -> dict:
    """Compare each test's value against reference ranges.

    Adds:
    - abnormal: True / False / None
    - direction: "high" / "low" / None
    - severity: "critical" | "severe" | "moderate" | "mild" | "normal" | None
    - is_panic_value: True / False
    - range_source: "printed" | "standard_fallback" | None
    """
    doc = copy.deepcopy(document)
    patient_sex = str((doc.get('patient_context') or {}).get('sex') or '').strip().lower()

    if ref_ranges is None:
        panic_ref = load_reference_ranges()
        ref_ranges = panic_ref if use_fallback_ranges else {}
    else:
        panic_ref = ref_ranges

    for panel in doc.get('panels') or []:
        for test in panel.get('tests') or []:
            val = test.get('value')
            low = test.get('range_low')
            high = test.get('range_high')
            test_name = test.get('test_name') or test.get('raw_test_name') or ''

            range_source = 'printed'
            # Fallback to standard reference range if requested and document has none
            if use_fallback_ranges and not (_is_number(low) or _is_number(high)) and test_name in ref_ranges:
                std_ref = ref_ranges[test_name]
                if patient_sex in ('m', 'male') and 'male' in std_ref:
                    low = std_ref['male'].get('low')
                    high = std_ref['male'].get('high')
                elif patient_sex in ('f', 'female') and 'female' in std_ref:
                    low = std_ref['female'].get('low')
                    high = std_ref['female'].get('high')
                elif 'default' in std_ref:
                    low = std_ref['default'].get('low')
                    high = std_ref['default'].get('high')
                if _is_number(low) or _is_number(high):
                    test['range_low'] = low
                    test['range_high'] = high
                    test['range_raw'] = f'{low or ""}-{high or ""}'
                    range_source = 'standard_fallback'

            if not _is_number(val) or not (_is_number(low) or _is_number(high)):
                test['abnormal'] = None
                test['direction'] = None
                test['severity'] = None
                test['is_panic_value'] = False
                continue

            test['range_source'] = range_source
            std_ref = panic_ref.get(test_name, {})
            panic_low = std_ref.get('panic_low')
            panic_high = std_ref.get('panic_high')

            is_panic = False
            if _is_number(panic_low) and val <= panic_low:
                is_panic = True
            elif _is_number(panic_high) and val >= panic_high:
                is_panic = True
            test['is_panic_value'] = is_panic

            if _is_number(low) and val < low:
                test['abnormal'] = True
                test['direction'] = 'low'
                if is_panic:
                    test['severity'] = 'critical'
                elif low > 0 and (low - val) / low > 0.35:
                    test['severity'] = 'severe'
                elif low > 0 and (low - val) / low > 0.15:
                    test['severity'] = 'moderate'
                else:
                    test['severity'] = 'mild'
            elif _is_number(high) and val > high:
                test['abnormal'] = True
                test['direction'] = 'high'
                if is_panic:
                    test['severity'] = 'critical'
                elif high > 0 and (val - high) / high > 0.50:
                    test['severity'] = 'severe'
                elif high > 0 and (val - high) / high > 0.20:
                    test['severity'] = 'moderate'
                else:
                    test['severity'] = 'mild'
            else:
                test['abnormal'] = False
                test['direction'] = None
                test['severity'] = 'normal'

    return doc


# -----------------------------------------------------------------------------
# 4. COMPREHENSIVE CLINICAL PATTERN MATCHER (Stage 3c-patterns)
# -----------------------------------------------------------------------------

def _test_matches_condition(test: dict, condition: dict, all_tests_map: Dict[str, dict]) -> bool:
    """Evaluate whether a single test satisfies a condition."""
    wanted = condition['test_name'].strip().lower()
    raw = (test.get('raw_test_name') or '').strip().lower()
    normalized = (test.get('test_name') or '').strip().lower()
    if wanted not in (normalized, raw):
        return False

    # 1. Direction check
    cond_dir = condition.get('direction')
    if cond_dir:
        if test.get('abnormal') is not True or test.get('direction') != cond_dir:
            return False

    # 2. Arithmetic operator check
    op = condition.get('operator')
    val = test.get('value')
    if op and _is_number(val):
        val = float(val)
        threshold = condition.get('threshold')
        if op == '>' and threshold is not None and not (val > float(threshold)):
            return False
        elif op == '>=' and threshold is not None and not (val >= float(threshold)):
            return False
        elif op == '<' and threshold is not None and not (val < float(threshold)):
            return False
        elif op == '<=' and threshold is not None and not (val <= float(threshold)):
            return False
        elif op == 'between':
            low = condition.get('low')
            high = condition.get('high')
            if low is not None and val < float(low):
                return False
            if high is not None and val > float(high):
                return False
        elif op in ('ratio_gt', 'ratio_lt'):
            other_name = (condition.get('ratio_with') or '').strip().lower()
            other_test = all_tests_map.get(other_name)
            if not other_test or not _is_number(other_test.get('value')) or float(other_test['value']) == 0:
                return False
            ratio = val / float(other_test['value'])
            if op == 'ratio_gt' and threshold is not None and not (ratio > float(threshold)):
                return False
            if op == 'ratio_lt' and threshold is not None and not (ratio < float(threshold)):
                return False

    return True


def _pattern_entry(rule: dict, panel_name: str, triggering: list) -> dict:
    return {
        'pattern_name': rule['pattern_name'],
        'surfaced_text': rule['surfaced_text'],
        'match_type': rule.get('match_type', 'all'),
        'severity': rule.get('severity', 'warning'),
        'category': rule.get('category', 'General'),
        'clinical_implication': rule.get('clinical_implication', ''),
        'differential_diagnosis': rule.get('differential_diagnosis', []),
        'panel_name': panel_name,
        'triggering_tests': [
            {
                'test_name': t.get('test_name'),
                'raw_test_name': t.get('raw_test_name'),
                'value': t.get('value'),
                'unit': t.get('unit'),
                'direction': t.get('direction'),
                'severity': t.get('severity'),
                'source_bbox': t.get('source_bbox'),
            }
            for t in triggering
        ],
    }


def detect_patterns(document: dict, rules: list) -> dict:
    """Match clinical combination rules against the document's tests.

    Supports:
    - scope="panel" (default): conditions evaluated within tests of each panel.
    - scope="document": cross-panel evaluation across all tests in the report.
    - match_type="all" | "any" | "min_count".
    """
    doc = copy.deepcopy(document)
    flagged_patterns = list(doc.get('flagged_patterns') or [])

    seen = {
        (
            p['pattern_name'],
            tuple(sorted((t.get('test_name'), t.get('direction'), t.get('value')) for t in p['triggering_tests'])),
        )
        for p in flagged_patterns
    }

    # Build document-wide test map for ratios and cross-panel rules
    all_tests_map: Dict[str, dict] = {}
    all_tests_list: List[dict] = []
    for panel in doc.get('panels') or []:
        for test in panel.get('tests') or []:
            name = (test.get('test_name') or test.get('raw_test_name') or '').strip().lower()
            if name:
                all_tests_map[name] = test
            all_tests_list.append(test)

    for rule in rules:
        scope = rule.get('scope', 'panel')
        match_type = rule.get('match_type', 'all')
        conditions = rule.get('conditions', [])
        min_count = rule.get('min_count', 1 if match_type == 'any' else len(conditions))

        evaluation_contexts: List[Tuple[str, List[dict]]] = []
        if scope == 'document':
            evaluation_contexts.append(('Document (Cross-Panel)', all_tests_list))
        else:
            for panel in doc.get('panels') or []:
                evaluation_contexts.append((panel.get('panel_name', 'Ungrouped'), panel.get('tests') or []))

        for panel_name, test_pool in evaluation_contexts:
            triggering = []
            used_test_identities = set()
            satisfied_count = 0

            for cond in conditions:
                cond_test_name = cond['test_name'].strip().lower()
                matched = None
                # First check if an already-matched test of the same name satisfies this condition
                for t in triggering:
                    t_name = (t.get('test_name') or t.get('raw_test_name') or '').strip().lower()
                    if t_name == cond_test_name and _test_matches_condition(t, cond, all_tests_map):
                        matched = t
                        break

                # Otherwise search unused tests in pool
                if matched is None:
                    matched = next(
                        (
                            t for idx, t in enumerate(test_pool)
                            if idx not in used_test_identities and _test_matches_condition(t, cond, all_tests_map)
                        ),
                        None,
                    )
                    if matched is not None:
                        idx = test_pool.index(matched)
                        used_test_identities.add(idx)

                if matched is not None:
                    satisfied_count += 1
                    if matched not in triggering:
                        triggering.append(matched)

            is_match = False
            if match_type == 'all' and satisfied_count == len(conditions):
                is_match = True
            elif match_type == 'any' and satisfied_count >= 1:
                is_match = True
            elif match_type == 'min_count' and satisfied_count >= min_count:
                is_match = True

            if not is_match or not triggering:
                continue

            key = (
                rule['pattern_name'],
                tuple(sorted((t.get('test_name'), t.get('direction'), t.get('value')) for t in triggering)),
            )
            if key in seen:
                continue
            seen.add(key)
            flagged_patterns.append(_pattern_entry(rule, panel_name, triggering))

    doc['flagged_patterns'] = flagged_patterns
    return doc


# -----------------------------------------------------------------------------
# 5. ORCHESTRATION / MAIN ENTRY POINTS
# -----------------------------------------------------------------------------

def annotate(document: dict, rules: list, reference_ranges: Optional[dict] = None) -> dict:
    """Full Stage 3 pass:
    1. Compute derived parameters
    2. Check arithmetic consistency
    3. Multi-tier flagging & panic value detection
    4. Clinical pattern matching
    """
    with_derived = calculate_derived_indices(document)
    consistency_warnings = verify_arithmetic_consistency(with_derived)
    flagged = flag_single_values(with_derived, reference_ranges)
    annotated_doc = detect_patterns(flagged, rules)

    if consistency_warnings:
        existing_warnings = list(annotated_doc.get('warnings') or [])
        annotated_doc['warnings'] = existing_warnings + consistency_warnings

    return annotated_doc


def apply_rules(document: dict, rules_path=None) -> dict:
    """Convenience entrypoint: loads the rule table and reference ranges, then annotates."""
    table = load_rule_table(rules_path)
    ref_ranges = load_reference_ranges()
    return annotate(document, table['rules'], ref_ranges)
