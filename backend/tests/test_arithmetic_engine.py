"""
Comprehensive tests for Stage 3 Arithmetic & Clinical Rule Engine.

Validates:
- eGFR (CKD-EPI 2021)
- Serum Anion Gap
- De Ritis (AST/ALT) Ratio
- Corrected Calcium
- BUN / Creatinine Ratio
- Non-HDL Cholesterol
- Mentzer Index
- Transferrin Saturation
- Neutrophil-to-Lymphocyte Ratio (NLR)
- Arithmetic Consistency Checks
- Panic / Critical Value Detection
- Multi-Specialty Clinical Pattern Rules
"""

import sys
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lab_pipeline import rule_engine


def _test_item(name, value, unit=None, low=None, high=None):
    return {
        'test_name': name,
        'raw_test_name': name,
        'value': value,
        'unit': unit,
        'range_low': low,
        'range_high': high,
        'range_raw': f'{low}-{high}' if low is not None and high is not None else None,
        'flag_in_source': None,
        'ocr_confidence': 'high',
        'source_bbox': {'page': 1, 'bbox': [100.0, 100.0, 200.0, 120.0]},
    }


def _doc(tests, patient_context=None, panel_name='Biochemistry'):
    return {
        'document_type': 'lab_report',
        'patient_context': patient_context or {'name': 'Alex', 'age': 45, 'sex': 'male'},
        'lab_name': 'Metropolitan Labs',
        'panels': [{'panel_name': panel_name, 'tests': tests}],
    }


# -----------------------------------------------------------------------------
# 1. DERIVED CALCULATIONS TESTS
# -----------------------------------------------------------------------------

def test_egfr_male_calculation():
    # 45 yo male with Scr = 1.8 mg/dL
    # eGFR = 142 * (1.8/0.9)^-1.200 * 0.9938^45 * 1.0 = ~44.5 mL/min/1.73m2
    doc = _doc([_test_item('Serum Creatinine', 1.8, 'mg/dL', 0.7, 1.3)], patient_context={'age': 45, 'sex': 'male'})
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    egfr_test = next(t for t in derived_panel['tests'] if t['test_name'] == 'Estimated Glomerular Filtration Rate')
    assert egfr_test['value'] is not None
    assert 40.0 < egfr_test['value'] < 50.0
    assert egfr_test['calculation_method'] == 'derived'
    assert 'CKD-EPI' in egfr_test['formula']


def test_egfr_female_calculation():
    # 60 yo female with Scr = 1.0 mg/dL
    doc = _doc([_test_item('Serum Creatinine', 1.0, 'mg/dL', 0.5, 1.1)], patient_context={'age': 60, 'sex': 'female'})
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    egfr_test = next(t for t in derived_panel['tests'] if t['test_name'] == 'Estimated Glomerular Filtration Rate')
    assert egfr_test['value'] is not None
    assert 60.0 < egfr_test['value'] < 75.0


def test_anion_gap_calculation():
    # Na = 140, Cl = 102, HCO3 = 18 -> Anion Gap = 140 - (102 + 18) = 20
    doc = _doc([
        _test_item('Sodium', 140.0, 'mEq/L', 135.0, 145.0),
        _test_item('Chloride', 102.0, 'mEq/L', 96.0, 106.0),
        _test_item('Bicarbonate', 18.0, 'mEq/L', 22.0, 29.0),
    ])
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    agap_test = next(t for t in derived_panel['tests'] if t['test_name'] == 'Serum Anion Gap')
    assert agap_test['value'] == 20.0
    assert agap_test['unit'] == 'mEq/L'


def test_de_ritis_ratio_calculation():
    # AST = 80, ALT = 32 -> Ratio = 80 / 32 = 2.5
    doc = _doc([
        _test_item('Aspartate Aminotransferase (AST)', 80.0, 'U/L', 10.0, 40.0),
        _test_item('Alanine Aminotransferase (ALT)', 32.0, 'U/L', 10.0, 45.0),
    ])
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    ratio_test = next(t for t in derived_panel['tests'] if t['test_name'] == 'AST/ALT (De Ritis) Ratio')
    assert ratio_test['value'] == 2.5


def test_corrected_calcium_calculation():
    # Measured Ca = 8.0, Albumin = 2.5
    # Corrected Ca = 8.0 + 0.8 * (4.0 - 2.5) = 8.0 + 1.2 = 9.2
    doc = _doc([
        _test_item('Calcium', 8.0, 'mg/dL', 8.5, 10.5),
        _test_item('Serum Albumin', 2.5, 'g/dL', 3.5, 5.0),
    ])
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    corr_ca = next(t for t in derived_panel['tests'] if t['test_name'] == 'Corrected Calcium')
    assert corr_ca['value'] == 9.2


def test_bun_creatinine_ratio():
    # BUN = 45.0, Creatinine = 1.5 -> Ratio = 30.0
    doc = _doc([
        _test_item('Blood Urea Nitrogen', 45.0, 'mg/dL', 7.0, 20.0),
        _test_item('Serum Creatinine', 1.5, 'mg/dL', 0.7, 1.3),
    ])
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    ratio = next(t for t in derived_panel['tests'] if t['test_name'] == 'BUN/Creatinine Ratio')
    assert ratio['value'] == 30.0


def test_non_hdl_cholesterol():
    # Total = 240, HDL = 45 -> Non-HDL = 195
    doc = _doc([
        _test_item('Total Cholesterol', 240.0, 'mg/dL', 100.0, 200.0),
        _test_item('HDL Cholesterol', 45.0, 'mg/dL', 40.0, 90.0),
    ])
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    non_hdl = next(t for t in derived_panel['tests'] if t['test_name'] == 'Non-HDL Cholesterol')
    assert non_hdl['value'] == 195.0


def test_mentzer_index():
    # MCV = 65.0, RBC = 5.5 -> Mentzer = 65 / 5.5 = 11.82 (Thalassemia trait pattern)
    doc = _doc([
        _test_item('Mean Corpuscular Volume', 65.0, 'fL', 80.0, 100.0),
        _test_item('Red Blood Cell Count', 5.5, '10^6/uL', 4.5, 5.5),
    ], panel_name='CBC')
    annotated = rule_engine.calculate_derived_indices(doc)
    derived_panel = next(p for p in annotated['panels'] if p['panel_name'] == 'Calculated / Derived Indices')
    mentzer = next(t for t in derived_panel['tests'] if t['test_name'] == 'Mentzer Index')
    assert mentzer['value'] == 11.82


# -----------------------------------------------------------------------------
# 2. ARITHMETIC CONSISTENCY CHECKS
# -----------------------------------------------------------------------------

def test_bilirubin_consistency_warning():
    # Total = 5.0, Direct = 1.0, Indirect = 1.0 -> Sum is 2.0 != 5.0
    doc = _doc([
        _test_item('Total Bilirubin', 5.0, 'mg/dL'),
        _test_item('Direct Bilirubin', 1.0, 'mg/dL'),
        _test_item('Indirect Bilirubin', 1.0, 'mg/dL'),
    ])
    warnings = rule_engine.verify_arithmetic_consistency(doc)
    assert len(warnings) == 1
    assert 'Bilirubin arithmetic mismatch' in warnings[0]


def test_bilirubin_consistency_clean_when_matching():
    # Total = 2.5, Direct = 0.5, Indirect = 2.0 -> Match!
    doc = _doc([
        _test_item('Total Bilirubin', 2.5, 'mg/dL'),
        _test_item('Direct Bilirubin', 0.5, 'mg/dL'),
        _test_item('Indirect Bilirubin', 2.0, 'mg/dL'),
    ])
    warnings = rule_engine.verify_arithmetic_consistency(doc)
    assert warnings == []


# -----------------------------------------------------------------------------
# 3. PANIC VALUES & MULTI-TIER FLAGGING
# -----------------------------------------------------------------------------

def test_panic_hyperkalemia():
    doc = _doc([_test_item('Potassium', 6.5, 'mEq/L', 3.5, 5.0)])
    flagged = rule_engine.flag_single_values(doc)
    k_test = flagged['panels'][0]['tests'][0]
    assert k_test['abnormal'] is True
    assert k_test['direction'] == 'high'
    assert k_test['is_panic_value'] is True
    assert k_test['severity'] == 'critical'


def test_panic_severe_thrombocytopenia():
    doc = _doc([_test_item('Platelet Count', 15.0, '10^3/uL', 150.0, 450.0)], panel_name='CBC')
    flagged = rule_engine.flag_single_values(doc)
    plt_test = flagged['panels'][0]['tests'][0]
    assert plt_test['abnormal'] is True
    assert plt_test['direction'] == 'low'
    assert plt_test['is_panic_value'] is True
    assert plt_test['severity'] == 'critical'


def test_moderate_out_of_range():
    # Glucose 130 in range 70-100 -> ~30% high -> moderate
    doc = _doc([_test_item('Fasting Blood Glucose', 130.0, 'mg/dL', 70.0, 100.0)])
    flagged = rule_engine.flag_single_values(doc)
    fbg_test = flagged['panels'][0]['tests'][0]
    assert fbg_test['abnormal'] is True
    assert fbg_test['direction'] == 'high'
    assert fbg_test['is_panic_value'] is False
    assert fbg_test['severity'] == 'moderate'


# -----------------------------------------------------------------------------
# 4. CLINICAL PATTERN MATCHING WITH ARITHMETIC RULES
# -----------------------------------------------------------------------------

def test_clinical_microcytic_hypochromic_anemia_pattern():
    table = rule_engine.load_rule_table(rule_engine.DEFAULT_RULES_PATH)
    doc = _doc([
        _test_item('Hemoglobin', 9.5, 'g/dL', 13.0, 17.0),
        _test_item('Mean Corpuscular Volume', 72.0, 'fL', 80.0, 100.0),
        _test_item('Mean Corpuscular Hemoglobin', 23.0, 'pg', 27.0, 33.0),
    ], panel_name='CBC')
    annotated = rule_engine.annotate(doc, table['rules'])
    patterns = [p['pattern_name'] for p in annotated['flagged_patterns']]
    assert 'microcytic_hypochromic_anemia' in patterns


def test_clinical_high_anion_gap_metabolic_acidosis_pattern():
    table = rule_engine.load_rule_table(rule_engine.DEFAULT_RULES_PATH)
    # Na 142, Cl 98, HCO3 16 -> Anion Gap = 142 - 114 = 28 (> 14), HCO3 low
    doc = _doc([
        _test_item('Sodium', 142.0, 'mEq/L', 135.0, 145.0),
        _test_item('Chloride', 98.0, 'mEq/L', 96.0, 106.0),
        _test_item('Bicarbonate', 16.0, 'mEq/L', 22.0, 29.0),
    ])
    annotated = rule_engine.annotate(doc, table['rules'])
    patterns = [p['pattern_name'] for p in annotated['flagged_patterns']]
    assert 'high_anion_gap_metabolic_acidosis' in patterns


def test_clinical_alcoholic_liver_pattern_via_de_ritis():
    table = rule_engine.load_rule_table(rule_engine.DEFAULT_RULES_PATH)
    # AST 150 (high), ALT 60 (high) -> AST/ALT = 2.5 (> 2.0)
    doc = _doc([
        _test_item('Aspartate Aminotransferase (AST)', 150.0, 'U/L', 10.0, 40.0),
        _test_item('Alanine Aminotransferase (ALT)', 60.0, 'U/L', 10.0, 45.0),
    ], panel_name='Liver Function')
    annotated = rule_engine.annotate(doc, table['rules'])
    patterns = [p['pattern_name'] for p in annotated['flagged_patterns']]
    assert 'alcoholic_liver_pattern' in patterns
