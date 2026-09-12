"""Tests for the Stage 2 flat-text recovery pass (server side).

Mirrors mobile/lib/lab/extract.dart::mergeLabDocuments: when table detection is
slightly wrong, a flat-text parse must not be able to extract fewer values than
it did before. `lab_pipeline` is stdlib-only here, so no DB/network/models.

Run with: cd backend && python -m pytest tests/test_stage2_recovery.py -v
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lab_pipeline import slm_stage  # noqa: E402


def _stage1(text, tables=None):
    return {
        'extraction_engine': 'opendataloader-json' if tables else 'easyocr_fallback',
        'text': text,
        'elements': [],
        'tables': tables or [],
        'warnings': [],
    }


def _bogus_table():
    """A table whose single cell parses to nothing — the failure mode."""
    return {
        'bbox': [0, 0, 1, 1],
        'page': 1,
        'n_rows': 1,
        'n_cols': 1,
        'rows': [
            {
                'row': 1,
                'cells': [
                    {'text': 'Garbage', 'is_header': False, 'row': 1, 'col': 1},
                ],
            }
        ],
    }


def _good_table():
    return {
        'bbox': [0, 0, 1, 1],
        'page': 1,
        'n_rows': 1,
        'n_cols': 4,
        'rows': [
            {
                'row': 1,
                'cells': [
                    {'text': 'Hemoglobin', 'is_header': False},
                    {'text': '11.2', 'is_header': False},
                    {'text': 'g/dL', 'is_header': False},
                    {'text': '13.0-17.0', 'is_header': False},
                ],
            }
        ],
    }


def _count(document):
    return sum(len(p.get('tests') or []) for p in (document.get('panels') or []))


def _names(document):
    return {
        t['test_name']
        for panel in document.get('panels') or []
        for t in panel.get('tests') or []
    }


def test_recovery_finds_rows_a_bad_table_drops():
    stage1 = _stage1(
        'Hemoglobin 11.2 g/dL 13.0-17.0\n'
        'WBC 7.5 4.0-11.0\n'
        'Platelet Count 250 150-450',
        tables=[_bogus_table()],
    )

    # The bare reference engine trusts the table and extracts nothing.
    assert _count(slm_stage._build_document(stage1)) == 0

    recovered = slm_stage._build_document_with_recovery(stage1)
    assert {'Hemoglobin', 'White Blood Cell Count', 'Platelet Count'} <= _names(recovered)


def test_recovery_does_not_duplicate_a_structural_row():
    stage1 = _stage1('Hemoglobin 11.2 g/dL 13.0-17.0', tables=[_good_table()])
    document = slm_stage._build_document_with_recovery(stage1)
    assert _count(document) == 1


def test_recovery_is_additive_only_when_there_are_no_tables():
    stage1 = _stage1('Hemoglobin 11.2 g/dL 13.0-17.0')
    assert slm_stage._build_document_with_recovery(stage1) == slm_stage._build_document(stage1)
