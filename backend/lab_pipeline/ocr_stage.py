"""
Stage 1 — OCR / text extraction for the lab report understanding pipeline.

Extraction engine: OpenDataLoader (opendataloader-pdf) in JSON mode. Every
element in the output carries a bounding box and page number, which are
preserved and passed through Stage 2 so downstream flags can be traced back
to their exact source location on the page.

- Digital (text-layer) PDFs: native OpenDataLoader extraction.
- Scanned / image-based PDFs: hybrid mode (opendataloader-pdf[hybrid]) with
  hybrid_mode="full", which is this package version's equivalent of
  --force-ocr (all pages are routed through the hybrid OCR backend). Requires
  a running `opendataloader-pdf-hybrid` server (see LAB_OPENDATALOADER_* envs).
- Images (jpg/png/...) and any PDF where extraction yields too little text
  and hybrid is unavailable: fall back to the existing EasyOCR pipeline in
  services.py. That path produces text only, so bounding boxes are null and
  a warning is recorded — auditability degrades explicitly, never silently.

This stage does NO semantic interpretation. Its only job is faithful
extraction with structure preserved. Handwritten documents are NOT supported
by this pipeline (OpenDataLoader cannot reliably read handwriting) — they
must go through the existing v1 prescription path, never through here.
"""

import asyncio
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory

try:
    import opendataloader_pdf
    HAS_OPENDATALOADER = True
except ImportError:
    HAS_OPENDATALOADER = False

# The existing v1 OCR pipeline (services.py) is reused for image uploads and
# last-resort fallback. Imported lazily inside the fallback path so this
# module (and the pure Stage 3 rule engine) stay light in minimal contexts.


MIN_MEANINGFUL_TEXT_CHARS = int(os.getenv('LAB_MIN_EXTRACT_TEXT_CHARS', '40'))

LAB_OPENDATALOADER_HYBRID = os.getenv('LAB_OPENDATALOADER_HYBRID', 'off')
LAB_OPENDATALOADER_HYBRID_MODE = os.getenv('LAB_OPENDATALOADER_HYBRID_MODE', 'full')
LAB_OPENDATALOADER_HYBRID_URL = os.getenv('LAB_OPENDATALOADER_HYBRID_URL', '').strip()
LAB_OPENDATALOADER_HYBRID_TIMEOUT = os.getenv('LAB_OPENDATALOADER_HYBRID_TIMEOUT', '30000').strip()
LAB_OPENDATALOADER_USE_STRUCT_TREE = os.getenv('LAB_OPENDATALOADER_USE_STRUCT_TREE', 'true').lower() == 'true'

IMAGE_SUFFIXES = {'.png', '.jpg', '.jpeg', '.bmp', '.tiff', '.tif'}
SUPPORTED_SUFFIXES = IMAGE_SUFFIXES | {'.pdf'}

# Marker returned by the sync extractor when the EasyOCR fallback (an async
# service) must run on the event loop thread.
OCR_FALLBACK_MARKER = '__needs_ocr_fallback__'


def _is_pdf(file_path: str) -> bool:
    return file_path.lower().endswith('.pdf')


def _is_supported(file_path: str) -> bool:
    return Path(file_path).suffix.lower() in SUPPORTED_SUFFIXES


def _hybrid_configured() -> bool:
    return bool(LAB_OPENDATALOADER_HYBRID and LAB_OPENDATALOADER_HYBRID.lower() != 'off')


def _odl_convert(file_path: str, output_dir: Path, hybrid: bool) -> None:
    """Run one OpenDataLoader conversion producing JSON output."""
    convert_kwargs = {
        'input_path': [str(file_path)],
        'output_dir': str(output_dir),
        'format': 'json',
        'table_method': 'cluster',
        'reading_order': 'xycut',
        'use_struct_tree': LAB_OPENDATALOADER_USE_STRUCT_TREE,
        'quiet': True,
    }
    if hybrid:
        # hybrid_mode="full" == force-OCR equivalent: every page goes through
        # the hybrid OCR backend instead of only triaged pages.
        convert_kwargs['hybrid'] = LAB_OPENDATALOADER_HYBRID
        convert_kwargs['hybrid_mode'] = LAB_OPENDATALOADER_HYBRID_MODE
        convert_kwargs['hybrid_fallback'] = True
        if LAB_OPENDATALOADER_HYBRID_URL:
            convert_kwargs['hybrid_url'] = LAB_OPENDATALOADER_HYBRID_URL
        if LAB_OPENDATALOADER_HYBRID_TIMEOUT.isdigit():
            convert_kwargs['hybrid_timeout'] = LAB_OPENDATALOADER_HYBRID_TIMEOUT

    opendataloader_pdf.convert(**convert_kwargs)


def _find_json_output(output_dir: Path) -> Path | None:
    candidates = [p for p in output_dir.rglob('*') if p.is_file() and p.suffix.lower() == '.json']
    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_size, reverse=True)
    return candidates[0]


def _flatten_element(node: dict, elements: list) -> None:
    """Recursively collect every node that carries text content."""
    content = node.get('content')
    if content is not None:
        elements.append({
            'type': node.get('type'),
            'text': str(content),
            'bbox': node.get('bounding box'),
            'page': node.get('page number'),
        })
    for kid in node.get('kids') or []:
        if isinstance(kid, dict):
            _flatten_element(kid, elements)


def _extract_tables(node: dict, tables: list) -> None:
    if node.get('type') == 'table':
        rows = []
        for row in node.get('rows') or []:
            cells = []
            for cell in row.get('cells') or []:
                cell_elements = []
                _flatten_element(cell, cell_elements)
                cells.append({
                    'text': ' '.join(el['text'] for el in cell_elements).strip(),
                    'bbox': cell.get('bounding box'),
                    'page': cell.get('page number'),
                    'is_header': bool(cell.get('is_header')),
                    'row': cell.get('row number'),
                    'col': cell.get('column number'),
                })
            rows.append({'row': row.get('row number'), 'cells': cells})
        tables.append({
            'bbox': node.get('bounding box'),
            'page': node.get('page number'),
            'n_rows': node.get('number of rows'),
            'n_cols': node.get('number of columns'),
            'rows': rows,
        })
    for kid in node.get('kids') or []:
        if isinstance(kid, dict):
            _extract_tables(kid, tables)


def _reading_order_text(elements: list) -> str:
    """Join flattened elements in document order (OpenDataLoader already
    emits reading-order-corrected structure via xycut)."""
    return '\n'.join(el['text'] for el in elements if el['text'].strip())


def _build_stage1_output(
    raw: dict | None,
    extraction_engine: str,
    warnings: list,
    fallback_text: str = '',
) -> dict:
    elements = []
    tables = []
    if raw:
        for kid in raw.get('kids') or []:
            if isinstance(kid, dict):
                _flatten_element(kid, elements)
                _extract_tables(kid, tables)
    text = _reading_order_text(elements) if elements else (fallback_text or '')
    if elements and not text.strip():
        warnings.append('OpenDataLoader produced structure but no text content')

    return {
        'stage': 1,
        'extraction_engine': extraction_engine,
        'text': text,
        'elements': elements,
        'tables': tables,
        'raw': raw,
        'warnings': warnings,
    }


def _extract_sync(file_path: str) -> dict:
    """Synchronous extraction; runs in a worker thread.

    Returns a stage 1 dict, or a marker dict signalling that the async
    EasyOCR fallback must run on the event loop thread.
    """
    if not _is_pdf(file_path):
        return {
            'needs_ocr_fallback': True,
            'warnings': ['image input: extracted via EasyOCR fallback — bounding boxes unavailable'],
        }

    warnings = []
    if not HAS_OPENDATALOADER:
        warnings.append('opendataloader-pdf is not installed; using EasyOCR fallback without bounding boxes')
        return {'needs_ocr_fallback': True, 'warnings': warnings}

    raw = None
    with TemporaryDirectory(prefix='lab_ocr_') as tmp_dir:
        output_dir = Path(tmp_dir)

        # Pass 1: native extraction (no OCR backend).
        try:
            _odl_convert(file_path, output_dir, hybrid=False)
            json_file = _find_json_output(output_dir)
            raw = json.loads(json_file.read_text(encoding='utf-8')) if json_file else None
        except Exception as e:
            warnings.append(f'OpenDataLoader native extraction failed: {e}')

        elements = []
        if raw:
            for kid in raw.get('kids') or []:
                if isinstance(kid, dict):
                    _flatten_element(kid, elements)
        native_text = _reading_order_text(elements).strip()

        # Pass 2: scanned / image-based PDF -> hybrid OCR of all pages
        # (force-OCR equivalent), when a hybrid backend is configured.
        if len(native_text) < MIN_MEANINGFUL_TEXT_CHARS and _hybrid_configured():
            print(f'  Stage 1: little native text ({len(native_text)} chars), rerunning with hybrid OCR (mode={LAB_OPENDATALOADER_HYBRID_MODE})')
            try:
                _odl_convert(file_path, output_dir, hybrid=True)
                json_file = _find_json_output(output_dir)
                hybrid_raw = json.loads(json_file.read_text(encoding='utf-8')) if json_file else None
                if hybrid_raw:
                    raw = hybrid_raw
                    warnings.append('extraction used hybrid OCR backend (scanned/image-based document)')
            except Exception as e:
                warnings.append(f'hybrid OCR backend failed: {e}')
        elif len(native_text) < MIN_MEANINGFUL_TEXT_CHARS:
            warnings.append(
                'document appears to be scanned/image-based but no hybrid OCR backend is configured '
                '(set LAB_OPENDATALOADER_HYBRID=docling-fast and run opendataloader-pdf-hybrid)'
            )

        if raw:
            stage1 = _build_stage1_output(raw, 'opendataloader-json', warnings)
            if len(stage1['text'].strip()) >= MIN_MEANINGFUL_TEXT_CHARS:
                return stage1

    # Last resort: the existing EasyOCR pipeline (text only, no bboxes).
    warnings.append(
        'OpenDataLoader output insufficient; falling back to EasyOCR — '
        'bounding boxes unavailable for this document'
    )
    return {'needs_ocr_fallback': True, 'warnings': warnings}


async def run_stage1(file_path: str) -> dict:
    """Extract structured text + bounding boxes from a lab report document."""
    print(f'Stage 1: extracting lab report structure from {file_path}')
    result = await asyncio.to_thread(_extract_sync, file_path)

    if result.get('needs_ocr_fallback'):
        import services
        fallback_text = await services.ocr_service(file_path)
        return _build_stage1_output(
            None,
            'easyocr_fallback',
            result.get('warnings', []),
            fallback_text=fallback_text or '',
        )
    return result
