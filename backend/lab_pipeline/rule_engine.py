"""
Stage 3 — Deterministic rule engine for lab report flagging.

Pure functions only: no model calls, no network, no side effects. Takes the
Stage 2 lab report JSON and returns the annotated version with:

- per-test  "abnormal" (true/false/null) and "direction" ("high"/"low"/null)
  from comparing value against range_low/range_high — null whenever range
  data is missing (3a),
- "flagged_patterns" assembled from an external, editable rule table
  (rules.json) — never hardcoded (3b).

This is the ONLY stage allowed to produce flags or patterns. Stages 1 and 2
never emit abnormal flags (enforced by their schemas). Every pattern entry
carries the triggering test values and their source_bbox for traceability.

Rule content is deliberately PLACEHOLDER data — see rules.json.
"""

import copy
import json
from pathlib import Path

DEFAULT_RULES_PATH = Path(__file__).parent / 'rules.json'


def load_rule_table(path=None) -> dict:
    """Load and validate the external rule table.

    Returns {"rules": [...], "review_status": str, "source": str}.
    Raises ValueError on structurally invalid rules.
    """
    rules_path = Path(path) if path else DEFAULT_RULES_PATH
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


def _validate_rule(rule, rules_path) -> dict:
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
        if cond.get('direction') not in ('high', 'low'):
            raise ValueError(
                f'Rule table {rules_path}: rule "{rule["pattern_name"]}" condition direction must be "high" or "low"'
            )
    if rule.get('match_type') != 'all':
        raise ValueError(
            f'Rule table {rules_path}: rule "{rule["pattern_name"]}" match_type must be "all" (only supported mode)'
        )
    if not rule.get('surfaced_text') or not isinstance(rule['surfaced_text'], str):
        raise ValueError(f'Rule table {rules_path}: rule "{rule["pattern_name"]}" missing "surfaced_text"')
    return rule


def _is_number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def flag_single_values(document: dict) -> dict:
    """3a — compare each test's value against its reference range.

    Adds "abnormal" (True/False/None) and "direction" ("high"/"low"/None)
    to every test. Null whenever value or range data is missing.
    """
    doc = copy.deepcopy(document)
    for panel in doc.get('panels') or []:
        for test in panel.get('tests') or []:
            value = test.get('value')
            low = test.get('range_low')
            high = test.get('range_high')

            if not _is_number(value) or not (_is_number(low) or _is_number(high)):
                test['abnormal'] = None
                test['direction'] = None
                continue

            if _is_number(low) and value < low:
                test['abnormal'] = True
                test['direction'] = 'low'
            elif _is_number(high) and value > high:
                test['abnormal'] = True
                test['direction'] = 'high'
            else:
                test['abnormal'] = False
                test['direction'] = None
    return doc


def _test_matches_condition(test: dict, condition: dict) -> bool:
    if test.get('abnormal') is not True or test.get('direction') != condition.get('direction'):
        return False
    wanted = condition['test_name'].strip().lower()
    raw = (test.get('raw_test_name') or '').strip().lower()
    normalized = (test.get('test_name') or '').strip().lower()
    return wanted in (normalized, raw)


def _pattern_entry(rule: dict, panel_name: str, triggering: list) -> dict:
    return {
        'pattern_name': rule['pattern_name'],
        'surfaced_text': rule['surfaced_text'],
        'match_type': rule['match_type'],
        'panel_name': panel_name,
        'triggering_tests': [
            {
                'test_name': t.get('test_name'),
                'raw_test_name': t.get('raw_test_name'),
                'value': t.get('value'),
                'unit': t.get('unit'),
                'direction': t.get('direction'),
                'source_bbox': t.get('source_bbox'),
            }
            for t in triggering
        ],
    }


def detect_patterns(document: dict, rules: list) -> dict:
    """3b — match combination rules against the document's flagged tests.

    Conditions must all be satisfied by tests within the SAME panel (a
    panel is the printed grouping context). Each match records the
    triggering tests with their source_bbox for traceability.
    """
    doc = copy.deepcopy(document)
    flagged_patterns = list(doc.get('flagged_patterns') or [])
    seen = {
        (
            p['pattern_name'],
            tuple(sorted((t.get('test_name'), t.get('direction')) for t in p['triggering_tests'])),
        )
        for p in flagged_patterns
    }

    for panel in doc.get('panels') or []:
        panel_name = panel.get('panel_name')
        tests = panel.get('tests') or []
        for rule in rules:
            triggering = []
            for condition in rule['conditions']:
                matched = next(
                    (t for t in tests if _test_matches_condition(t, condition) and t not in triggering),
                    None,
                )
                if matched is None:
                    triggering = []
                    break
                triggering.append(matched)
            if not triggering:
                continue

            key = (
                rule['pattern_name'],
                tuple(sorted((t.get('test_name'), t.get('direction')) for t in triggering)),
            )
            if key in seen:
                continue
            seen.add(key)
            flagged_patterns.append(_pattern_entry(rule, panel_name, triggering))

    doc['flagged_patterns'] = flagged_patterns
    return doc


def annotate(document: dict, rules: list) -> dict:
    """Full Stage 3 pass: 3a single-value flagging, then 3b patterns."""
    flagged = flag_single_values(document)
    return detect_patterns(flagged, rules)


def apply_rules(document: dict, rules_path=None) -> dict:
    """Convenience: load the external rule table and annotate the document."""
    table = load_rule_table(rules_path)
    return annotate(document, table['rules'])
