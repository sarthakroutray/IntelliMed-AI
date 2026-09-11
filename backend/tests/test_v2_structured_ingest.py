"""Tests for the v2 structured-ingest payload schema (app sync contract).

Loads api/v2/ingest_schema.py directly by path so the test needs no
generated Prisma client, database, or network access.
Run with: cd backend && python -m pytest tests/test_v2_structured_ingest.py -v
"""

import importlib.util
import sys
from pathlib import Path

_SCHEMA_PATH = Path(__file__).parent.parent / 'api' / 'v2' / 'ingest_schema.py'
_spec = importlib.util.spec_from_file_location('v2_ingest_schema', _SCHEMA_PATH)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
sys.modules['v2_ingest_schema'] = _module
_spec.loader.exec_module(_module)

StructuredIngestRequest = _module.StructuredIngestRequest
validate_ingest_payload = _module.validate_ingest_payload


def _lab_payload(**overrides):
    base = {
        'kind': 'lab_report',
        'engine': 'deterministic-v1',
        'latency_ms': 120,
        'normalized': {
            'document_type': 'lab_report',
            'patient_context': {'name': None, 'age': None, 'sex': None, 'report_date': None},
            'lab_name': None,
            'panels': [
                {
                    'panel_name': 'Ungrouped',
                    'tests': [
                        {
                            'test_name': 'Hemoglobin',
                            'raw_test_name': 'Hb',
                            'value': 11.2,
                            'unit': 'g/dL',
                            'range_low': 13.0,
                            'range_high': 17.0,
                            'range_raw': '13.0-17.0',
                            'flag_in_source': None,
                            'ocr_confidence': 'high',
                            'source_bbox': None,
                        }
                    ],
                }
            ],
        },
        'source': 'app',
    }
    base.update(overrides)
    return StructuredIngestRequest(**base)


def test_valid_lab_payload_passes():
    assert validate_ingest_payload(_lab_payload()) == []


def test_wrong_source_rejected():
    problems = validate_ingest_payload(_lab_payload(source='web'))
    assert any('source must be "app"' in p for p in problems)


def test_stage3_fields_rejected():
    payload = _lab_payload()
    payload.normalized['panels'][0]['tests'][0]['abnormal'] = True
    payload.normalized['panels'][0]['tests'][0]['direction'] = 'low'
    problems = validate_ingest_payload(payload)
    assert any('Stage 3 fields' in p for p in problems)


def test_xray_requires_top_pattern():
    payload = StructuredIngestRequest(
        kind='xray',
        normalized={'document_type': 'xray'},
        source='app',
    )
    problems = validate_ingest_payload(payload)
    assert any('top_pattern' in p for p in problems)


def test_prescription_requires_medication_name():
    payload = StructuredIngestRequest(
        kind='prescription',
        normalized={
            'document_type': 'prescription',
            'patient_context': {},
            'panels': [{'panel_name': 'Prescribed items', 'items': [{'dosage': '500 mg'}]}],
        },
        source='app',
    )
    problems = validate_ingest_payload(payload)
    assert any('medication name' in p for p in problems)


def test_payload_with_summary_context_accepted():
    payload = _lab_payload(
        summary_context={
            'document_type': 'summary_context',
            'medical_summary': 'CBC within normal limits.',
            'key_findings': [],
        }
    )
    assert validate_ingest_payload(payload) == []
    assert payload.summary_context is not None
    assert payload.summary_context['medical_summary'] == 'CBC within normal limits.'

