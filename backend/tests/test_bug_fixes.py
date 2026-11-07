import os
import sys
from pathlib import Path

# Ensure backend root is on sys.path
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

os.environ.setdefault("SECRET_KEY", "test-secret-key-for-unit-tests-0123456789")

import asyncio
from datetime import date, datetime
import pytest
from fastapi_cache import FastAPICache
from fastapi_cache.backends.inmemory import InMemoryBackend
from request_cache import clear_cache_namespace, clear_cache_key
from api.v2.lab_refs import has_stored_file, file_ref_name
from services import _run_regex_medical_extraction, _FREQUENCY_PATTERNS, _ROUTE_PATTERNS, FREQUENCY_TERMS, ROUTE_TERMS
from schemas import DocumentInfo, UserCreate, Role


def test_cache_invalidation_with_prefix():
    """Verify that clear_cache_namespace and clear_cache_key properly clear prefixed entries."""
    async def _run():
        backend = InMemoryBackend()
        FastAPICache.init(backend, prefix="intellimed-cache")
    
        # Store keys with the prefix (as FastAPICache does)
        await backend.set("intellimed-cache:patient-docs:user:1", "data1", 100)
        await backend.set("intellimed-cache:patient-docs:user:2", "data2", 100)
        await backend.set("intellimed-cache:profile:user:1", "profile1", 100)
        
        # Verify entries exist
        assert "intellimed-cache:patient-docs:user:1" in backend._store
        assert "intellimed-cache:profile:user:1" in backend._store
        
        # Clear namespace
        await clear_cache_namespace("patient-docs")
        assert "intellimed-cache:patient-docs:user:1" not in backend._store
        assert "intellimed-cache:patient-docs:user:2" not in backend._store
        assert "intellimed-cache:profile:user:1" in backend._store
        
        # Clear specific key
        await clear_cache_key("profile", "user:1")
        assert "intellimed-cache:profile:user:1" not in backend._store

        # Clear nonexistent key does not raise KeyError
        await clear_cache_key("nonexistent-namespace", "user:999")

        # Clear key stored without prefix still works
        await backend.set("profile:user:2", "profile2", 100)
        assert "profile:user:2" in backend._store
        await clear_cache_key("profile", "user:2")
        assert "profile:user:2" not in backend._store

    asyncio.run(_run())


def test_app_structured_pseudo_paths():
    """Verify that app-structured pseudo paths are recognized and handled without error."""
    assert not has_stored_file("app-structured/lab_report")
    assert not has_stored_file("app-structured/xray")
    assert not has_stored_file("app-structured/prescription")
    assert not has_stored_file("")
    assert not has_stored_file(None)
    assert has_stored_file("patients/12/lab-reports/report.pdf")
    assert has_stored_file("https://supabase.co/storage/v1/object/public/medical-documents/report.pdf")

    assert file_ref_name("app-structured/lab_report") == "On-device structured result"
    assert file_ref_name("patients/12/report.pdf") == "report.pdf"
    assert file_ref_name(None) == "N/A"


def test_document_info_optional_fields():
    """Verify DocumentInfo accepts None or omitted upload_timestamp and ai_analysis."""
    doc = DocumentInfo(id=1, filename="test.pdf")
    assert doc.id == 1
    assert doc.upload_timestamp is None
    assert doc.ai_analysis is None


def test_nlp_regex_word_boundaries_no_false_positives():
    """Verify that words like 'food', 'good', 'period' do not trigger false-positive 'od' frequency."""
    text = "Patient took medication with food in the morning. Good blood pressure."
    result = _run_regex_medical_extraction(text)
    
    # None of the medications should have false 'od' frequency from 'food' or 'good'
    for rx in result.get("prescriptions", []):
        freq = rx.get("frequency")
        if freq:
            assert freq != "od", f"False positive 'od' matched from text: {text}"


def test_nlp_regex_real_frequency_matches():
    """Verify that actual prescription frequencies with word boundaries are correctly matched."""
    text = "Tab Amoxicillin 500mg po bid for 7 days"
    result = _run_regex_medical_extraction(text)
    assert len(result.get("medications", [])) > 0
    amox_rx = next((rx for rx in result["prescriptions"] if "amoxicillin" in rx.get("medication", "").lower()), None)
    assert amox_rx is not None
    assert amox_rx.get("dosage") == "500mg"
    assert amox_rx.get("frequency") == "bid"
    assert amox_rx.get("route") == "po"
    assert "7" in amox_rx.get("duration", "")


def test_date_conversion_for_prisma():
    """Verify date object conversion to datetime for Prisma compatibility."""
    birth_date = date(1995, 8, 20)
    assert isinstance(birth_date, date) and not isinstance(birth_date, datetime)
    converted = datetime.combine(birth_date, datetime.min.time())
    assert isinstance(converted, datetime)
    assert converted.year == 1995
    assert converted.month == 8
    assert converted.day == 20
    assert converted.strftime("%Y-%m-%d") == "1995-08-20"
