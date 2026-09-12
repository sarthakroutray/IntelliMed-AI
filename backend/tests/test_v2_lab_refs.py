"""Tests for the pure lab-report file-reference helpers.

These cover the bug that made opening an app-produced lab report return a 500:
the read route asked storage to sign a URL for the "app-structured/<kind>"
pseudo-path, which has no object behind it.

Loads api/v2/lab_refs.py directly by path, so it needs no generated Prisma
client, database, or Supabase credentials.
Run with: cd backend && python -m pytest tests/test_v2_lab_refs.py -v
"""

import importlib.util
from pathlib import Path

_PATH = Path(__file__).parent.parent / 'api' / 'v2' / 'lab_refs.py'
_spec = importlib.util.spec_from_file_location('v2_lab_refs', _PATH)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

has_stored_file = _module.has_stored_file
file_ref_name = _module.file_ref_name


def test_app_structured_pseudo_path_has_no_file():
    assert has_stored_file('app-structured/lab_report') is False
    assert has_stored_file('app-structured/prescription') is False


def test_app_structured_name_is_friendly():
    assert file_ref_name('app-structured/lab_report') == 'On-device structured result'


def test_real_storage_paths_count_as_files():
    assert has_stored_file('patients/42/lab-reports/cbc.pdf') is True
    assert file_ref_name('patients/42/lab-reports/cbc.pdf') == 'cbc.pdf'


def test_signed_url_names_the_object():
    url = (
        'https://x.supabase.co/storage/v1/object/sign/medical-documents/'
        'patients/42/lab-reports/cbc.pdf?token=abc'
    )
    assert has_stored_file(url) is True
    assert file_ref_name(url) == 'cbc.pdf'


def test_missing_paths_are_safe():
    assert has_stored_file(None) is False
    assert has_stored_file('') is False
    assert file_ref_name(None) == 'N/A'
    assert file_ref_name('') == 'N/A'
