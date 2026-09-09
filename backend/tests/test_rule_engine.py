"""Tests for the Stage 3 rule engine (lab_pipeline.rule_engine).

The engine is pure: tests need no database, network, or models.
Run with: cd backend && python -m pytest tests/test_rule_engine.py -v
"""

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from lab_pipeline import rule_engine


def _test(name, value, low, high, bbox=None, raw=None, unit='mg/dL'):
    return {
        'test_name': name,
        'raw_test_name': raw or name,
        'value': value,
        'unit': unit,
        'range_low': low,
        'range_high': high,
        'range_raw': f'{low} - {high}' if low is not None and high is not None else None,
        'flag_in_source': None,
        'ocr_confidence': 'high',
        'source_bbox': bbox,
    }


def _doc(panels):
    return {'document_type': 'lab_report', 'patient_context': {}, 'lab_name': None, 'panels': panels}


def _panel(name, tests):
    return {'panel_name': name, 'tests': tests}


# --- 3a: single-value flagging -------------------------------------------

def test_high_value_flagged_high():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 18.0, 13.0, 17.0)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is True
    assert test['direction'] == 'high'


def test_low_value_flagged_low():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 11.2, 13.0, 17.0)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is True
    assert test['direction'] == 'low'


def test_value_within_range_is_normal():
    doc = _doc([_panel('CBC', [_test('WBC', 7.5, 4.0, 11.0)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is False
    assert test['direction'] is None


def test_boundary_values_are_normal():
    doc = _doc([_panel('CBC', [_test('WBC', 4.0, 4.0, 11.0), _test('WBC', 11.0, 4.0, 11.0)])])
    out = rule_engine.flag_single_values(doc)
    assert all(t['abnormal'] is False for t in out['panels'][0]['tests'])


def test_missing_range_yields_null():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 11.2, None, None)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is None
    assert test['direction'] is None


def test_missing_value_yields_null():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', None, 13.0, 17.0)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is None


def test_non_numeric_value_yields_null():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 'trace', 13.0, 17.0)])])
    out = rule_engine.flag_single_values(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is None


def test_flagging_does_not_mutate_input():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 18.0, 13.0, 17.0)])])
    original = copy.deepcopy(doc)
    rule_engine.flag_single_values(doc)
    assert 'abnormal' not in doc['panels'][0]['tests'][0]
    assert doc == original


# --- 3b: combination patterns --------------------------------------------

HEM_LOW = _test('Hemoglobin', 11.2, 13.0, 17.0, bbox={'page': 1, 'bbox': [10, 20, 30, 40]})
HCT_LOW = _test('Hematocrit', 30.0, 40.0, 50.0, bbox={'page': 1, 'bbox': [50, 20, 70, 40]})
WBC_NORMAL = _test('White Blood Cell Count', 7.5, 4.0, 11.0)


def _rule_table():
    return rule_engine.load_rule_table()


def _placeholder_rules():
    return [
        {
            'pattern_name': 'example_combined_low',
            'conditions': [
                {'test_name': 'Hemoglobin', 'direction': 'low'},
                {'test_name': 'Hematocrit', 'direction': 'low'},
            ],
            'match_type': 'all',
            'surfaced_text': 'Pattern consistent with example combined low — recommend clinical review',
        }
    ]


def test_pattern_triggers_when_all_conditions_met():
    doc = _doc([_panel('CBC', [HEM_LOW, HCT_LOW])])
    flagged = rule_engine.flag_single_values(doc)
    out = rule_engine.detect_patterns(flagged, _placeholder_rules())

    assert len(out['flagged_patterns']) == 1
    pattern = out['flagged_patterns'][0]
    assert pattern['pattern_name'] == 'example_combined_low'
    assert 'recommend clinical review' in pattern['surfaced_text']

    triggered = pattern['triggering_tests']
    assert {(t['test_name'], t['direction']) for t in triggered} == {
        ('Hemoglobin', 'low'),
        ('Hematocrit', 'low'),
    }
    for t in triggered:
        assert t['source_bbox'] is not None


def test_pattern_does_not_trigger_when_condition_missing():
    doc = _doc([_panel('CBC', [HEM_LOW, WBC_NORMAL])])
    flagged = rule_engine.flag_single_values(doc)
    out = rule_engine.detect_patterns(flagged, _placeholder_rules())
    assert out['flagged_patterns'] == []


def test_pattern_conditions_are_panel_scoped():
    doc = _doc([
        _panel('CBC', [HEM_LOW]),
        _panel('Chemistry', [HCT_LOW]),
    ])
    flagged = rule_engine.flag_single_values(doc)
    out = rule_engine.detect_patterns(flagged, _placeholder_rules())
    assert out['flagged_patterns'] == []


def test_pattern_matches_raw_test_name():
    doc = _doc([_panel('CBC', [_test('Hemoglobin', 11.2, 13.0, 17.0, raw='Hb'), HCT_LOW])])
    flagged = rule_engine.flag_single_values(doc)
    out = rule_engine.detect_patterns(flagged, _placeholder_rules())
    assert len(out['flagged_patterns']) == 1


def test_detect_patterns_does_not_mutate_input():
    doc = _doc([_panel('CBC', [HEM_LOW, HCT_LOW])])
    original = copy.deepcopy(doc)
    flagged = rule_engine.flag_single_values(doc)
    rule_engine.detect_patterns(flagged, _placeholder_rules())
    assert doc == original


# --- external rule table ---------------------------------------------------

def test_default_rule_table_loads_and_is_all_placeholder():
    table = _rule_table()
    assert table['rules'], 'rule table must contain rules'
    assert 'CLINICAL REVIEW' in table['review_status'].upper()
    for rule in table['rules']:
        assert rule['_comment'].startswith('PLACEHOLDER')
        assert 'clinical review' in rule['surfaced_text'].lower()


def test_placeholder_rules_fire_against_flagged_document():
    table = _rule_table()
    doc = _doc([_panel('CBC', [HEM_LOW, HCT_LOW])])
    out = rule_engine.apply_rules(doc)
    names = [p['pattern_name'] for p in out['flagged_patterns']]
    assert 'PLACEHOLDER_example_combined_low_pattern' in names


def test_apply_rules_end_to_end():
    doc = _doc([_panel('CBC', [_test('WBC', 15.0, 4.0, 11.0)])])
    out = rule_engine.apply_rules(doc)
    test = out['panels'][0]['tests'][0]
    assert test['abnormal'] is True
    assert test['direction'] == 'high'


# --- validation ------------------------------------------------------------

def test_invalid_match_type_rejected(tmp_path):
    bad = {
        'rules': [{
            'pattern_name': 'bad',
            'conditions': [{'test_name': 'X', 'direction': 'high'}],
            'match_type': 'any',
            'surfaced_text': 'nope',
        }]
    }
    path = tmp_path / 'rules.json'
    path.write_text(__import__('json').dumps(bad))
    with pytest.raises(ValueError):
        rule_engine.load_rule_table(path)


def test_invalid_direction_rejected(tmp_path):
    bad = {
        'rules': [{
            'pattern_name': 'bad',
            'conditions': [{'test_name': 'X', 'direction': 'sideways'}],
            'match_type': 'all',
            'surfaced_text': 'nope',
        }]
    }
    path = tmp_path / 'rules.json'
    path.write_text(__import__('json').dumps(bad))
    with pytest.raises(ValueError):
        rule_engine.load_rule_table(path)


def test_empty_conditions_rejected(tmp_path):
    bad = {'rules': [{'pattern_name': 'bad', 'conditions': [], 'match_type': 'all', 'surfaced_text': 'nope'}]}
    path = tmp_path / 'rules.json'
    path.write_text(__import__('json').dumps(bad))
    with pytest.raises(ValueError):
        rule_engine.load_rule_table(path)
