"""Payload schema + validation for the v2 structured-ingest route.

Kept free of database/storage imports so it can be unit-tested without a
generated Prisma client or network access.
"""

from typing import Any, Optional

from pydantic import BaseModel, Field


class StructuredIngestRequest(BaseModel):
    """Structured result produced on-device by the app (never raw documents)."""

    kind: str = Field(description='lab_report | prescription | xray')
    engine: Optional[str] = Field(default=None, description='on-device engine id')
    latency_ms: Optional[int] = None
    normalized: dict[str, Any] = Field(description='schema-correct normalized output')
    summary_context: Optional[dict[str, Any]] = Field(default=None, description='on-device T5 summary context')
    ocr_excerpt: Optional[str] = None
    source: str = Field(default='app', description='originating client tag')


_REQUIRED_LAB_TEST_KEYS = {
    'test_name', 'raw_test_name', 'value', 'unit',
    'range_low', 'range_high', 'range_raw', 'flag_in_source',
    'ocr_confidence', 'source_bbox',
}


def validate_ingest_payload(payload: StructuredIngestRequest) -> list[str]:
    """Reject payloads that violate the agreed schemas or carry Stage 3 flags."""
    problems: list[str] = []
    if payload.source != 'app':
        problems.append('source must be "app" for this route')
    normalized = payload.normalized or {}
    if payload.kind == 'xray':
        if normalized.get('document_type') != 'xray':
            problems.append('xray normalized.document_type must be "xray"')
        if not normalized.get('top_pattern'):
            problems.append('xray normalized.top_pattern is required')
    elif payload.kind == 'lab_report':
        if normalized.get('document_type') != 'lab_report':
            problems.append('lab_report normalized.document_type must be "lab_report"')
        for key in ('patient_context', 'panels'):
            if key not in normalized:
                problems.append(f'missing normalized key: {key}')
        for panel in normalized.get('panels') or []:
            for test in panel.get('tests') or []:
                missing = _REQUIRED_LAB_TEST_KEYS - set(test)
                if missing:
                    problems.append(f'test {test.get("raw_test_name")!r} missing keys: {sorted(missing)}')
                if test.get('abnormal') is not None or test.get('direction') is not None:
                    problems.append(
                        f'test {test.get("raw_test_name")!r} carries Stage 3 fields '
                        '(abnormal/direction) — normalization output must never contain flags'
                    )
    elif payload.kind == 'prescription':
        if normalized.get('document_type') != 'prescription':
            problems.append('prescription normalized.document_type must be "prescription"')
        for panel in normalized.get('panels') or []:
            for item in panel.get('items') or []:
                if not item.get('medication'):
                    problems.append(f'prescription item missing medication name: {item}')
    else:
        problems.append(f'unknown kind: {payload.kind!r} (expected lab_report | prescription | xray)')
    return problems
