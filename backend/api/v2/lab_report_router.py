"""
API v2 — Lab report understanding endpoints.

POST /lab-reports/upload   upload + full pipeline (Stages 1-3), stored with source tag
GET  /lab-reports          patient's own lab reports
GET  /lab-reports/patient/{patient_id}   doctor's view for a linked patient
GET  /lab-reports/{id}     full annotated structure (flagged_patterns included)

Every read returns the structured context object with source traceability
(bbox + triggering values).
"""

import os
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status

from api.v2.ingest_schema import StructuredIngestRequest, validate_ingest_payload

from auth import get_current_user
from prisma_db import get_db
from prisma_client import Prisma
from prisma_client.fields import Json
from schemas import User
from request_cache import doctor_has_patient_access
import supabase_storage

from lab_pipeline import ocr_stage, run_lab_report_pipeline

router = APIRouter()

MAX_UPLOAD_SIZE_MB = int(os.getenv('MAX_UPLOAD_SIZE_MB', '10'))
VALID_SOURCES = ('web', 'app')


def _file_name_of(file_path: str) -> str:
    try:
        return Path(supabase_storage.to_storage_path(file_path)).name
    except Exception:
        return 'unknown'


@router.post('/lab-reports/upload-structured', status_code=status.HTTP_201_CREATED)
async def upload_structured_result(
    payload: StructuredIngestRequest,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Store an app-produced structured result (on-device inference output).

    This route accepts JSON only — never raw documents. The app tags every
    payload `source: "app"`. Lab reports are re-annotated with the Stage 3
    rule engine server-side so flagging stays deterministic and traceable;
    xray/prescription payloads are stored as received for doctor review.
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Only patients can submit structured results',
        )

    problems = validate_ingest_payload(payload)
    if problems:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={'message': 'Structured result failed schema validation', 'problems': problems},
        )

    from lab_pipeline import rule_engine

    if payload.kind == 'lab_report':
        rule_table = rule_engine.load_rule_table()
        annotated = rule_engine.annotate(payload.normalized, rule_table['rules'])
        result = {
            'pipeline': 'lab-report-understanding/v2',
            'stage2': payload.normalized,
            'stage2_engine': payload.engine or 'app-on-device',
            'stage3': annotated,
            'warnings': [],
            'rules_review_status': rule_table['review_status'],
            'ocr_excerpt': payload.ocr_excerpt,
            'latency_ms': payload.latency_ms,
        }
        if payload.summary_context:
            result['summary_context'] = payload.summary_context
    else:
        result = {
            'pipeline': f'{payload.kind}/app-on-device/v1',
            'normalized': payload.normalized,
            'engine': payload.engine or 'app-on-device',
            'warnings': [],
            'ocr_excerpt': payload.ocr_excerpt,
            'latency_ms': payload.latency_ms,
        }
        if payload.summary_context:
            result['summary_context'] = payload.summary_context

    if payload.kind == 'lab_report':
        db_report = await db.labreport.create(
            data={
                'patient_id': current_user.id,
                'file_path': f'app-structured/{payload.kind}',
                'source': 'app',
                'result_json': Json(result),
            }
        )
        return {
            'message': 'Structured lab report stored',
            'id': db_report.id,
            'source': db_report.source,
            'upload_timestamp': db_report.upload_timestamp,
            'result': result,
        }

    db_document = await db.medicaldocument.create(
        data={
            'patient_id': current_user.id,
            'file_path': f'app-structured/{payload.kind}',
            'source': 'app',
            'ai_analysis_json': Json(result),
        }
    )
    return {
        'message': f'Structured {payload.kind} context stored',
        'id': db_document.id,
        'source': db_document.source,
        'upload_timestamp': db_document.upload_timestamp,
        'result': result,
    }


@router.post('/lab-reports/upload')
async def upload_lab_report(
    file: UploadFile = File(...),
    source: str = Form('web'),
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload a lab report, run Stages 1-3, store the annotated result.

    `source` tags the originating client ("web" | "app"); the Android app
    will reuse this same endpoint with source="app".
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Only patients can upload lab reports',
        )

    if source not in VALID_SOURCES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f'Invalid source. Must be one of: {", ".join(VALID_SOURCES)}',
        )

    if not file.filename:
        raise HTTPException(status_code=400, detail='No file provided')

    suffix = Path(file.filename).suffix.lower()
    if suffix not in ocr_stage.SUPPORTED_SUFFIXES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f'Unsupported lab report file type: {suffix}. Supported: '
                f'{", ".join(sorted(ocr_stage.SUPPORTED_SUFFIXES))}. '
                'Handwritten documents are not supported by this pipeline.'
            ),
        )

    try:
        file_bytes = await file.read()
        max_bytes = MAX_UPLOAD_SIZE_MB * 1024 * 1024
        if len(file_bytes) > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f'File too large. Maximum allowed size is {MAX_UPLOAD_SIZE_MB} MB.',
            )

        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name

        storage_path = f'patients/{current_user.id}/lab-reports/{file.filename}'
        stored_path = supabase_storage.upload_file(
            file_bytes=file_bytes,
            destination_path=storage_path,
            content_type=file.content_type,
        )

        result = await run_lab_report_pipeline(tmp_path)

        db_report = await db.labreport.create(
            data={
                'patient_id': current_user.id,
                'file_path': stored_path,
                'source': source,
                'result_json': Json(result),
            }
        )

        return {
            'message': 'Lab report processed',
            'id': db_report.id,
            'source': db_report.source,
            'upload_timestamp': db_report.upload_timestamp,
            'result': result,
        }
    except HTTPException:
        raise
    except Exception as e:
        print(f'✗ Lab report upload failed: {str(e)}')
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f'Lab report processing failed: {str(e)}',
        )


@router.get('/lab-reports/patient/{patient_id}')
async def get_patient_lab_reports_for_doctor(
    patient_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Doctor view: all lab reports for a linked patient."""
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Only doctors can view patient lab reports',
        )

    has_access = await doctor_has_patient_access(db, current_user.id, patient_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this patient's lab reports",
        )

    reports = await db.labreport.find_many(where={'patient_id': patient_id})
    return [
        {
            'id': report.id,
            'patient_id': report.patient_id,
            'source': report.source,
            'filename': _file_name_of(report.file_path) if report.file_path else 'N/A',
            'file_url': (
                supabase_storage.create_signed_url(supabase_storage.to_storage_path(report.file_path))
                if report.file_path else ''
            ),
            'upload_timestamp': report.upload_timestamp,
            'result': report.result_json,
        }
        for report in reports
    ]


@router.get('/lab-reports')
async def get_own_lab_reports(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Patient view: own lab reports."""
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Only patients can view their lab reports',
        )

    reports = await db.labreport.find_many(where={'patient_id': current_user.id})
    return [
        {
            'id': report.id,
            'source': report.source,
            'filename': _file_name_of(report.file_path) if report.file_path else 'N/A',
            'upload_timestamp': report.upload_timestamp,
            'result': report.result_json,
        }
        for report in reports
    ]


@router.get('/lab-reports/{lab_report_id}')
async def get_lab_report(
    lab_report_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Full annotated lab report structure (flagged_patterns included)."""
    report = await db.labreport.find_unique(where={'id': lab_report_id})
    if not report:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Lab report not found',
        )

    if current_user.role == 'patient':
        if report.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this lab report",
            )
    elif current_user.role == 'doctor':
        has_access = await doctor_has_patient_access(db, current_user.id, report.patient_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this lab report",
            )

    file_url = ''
    if report.file_path:
        file_url = supabase_storage.create_signed_url(supabase_storage.to_storage_path(report.file_path))

    return {
        'id': report.id,
        'patient_id': report.patient_id,
        'source': report.source,
        'filename': _file_name_of(report.file_path) if report.file_path else 'N/A',
        'file_url': file_url,
        'upload_timestamp': report.upload_timestamp,
        'result': report.result_json,
    }
