"""
Stage 2 — SLM normalization for lab reports.

Converts Stage 1's extraction output into the fixed lab report schema:

    {
      "document_type": "lab_report",
      "patient_context": {"name","age","sex","report_date"},
      "lab_name": null,
      "panels": [{"panel_name": str, "tests": [{...}]}]
    }

Hard rules enforced everywhere in this module (mirrors the system prompt):
- Never compute abnormal flags from value-vs-range comparison — that lives
  exclusively in Stage 3. Only source-printed flags are captured.
- Never fabricate reference ranges — null when absent.
- Never infer patient identity fields — null when absent.
- Ambiguous rows are reconstructed at ocr_confidence "low", never dropped.

Default engine is a deterministic normalizer (no hallucination risk). An
optional SLM backend can be enabled via env (LAB_SLM_PROVIDER=...) for the
fine-tuned model; its JSON output is validated against the schema and the
pipeline falls back to the deterministic engine if it fails. Fine-tuning
datasets are produced separately by scripts/prepare_slm_finetune_dataset.py
— never inline in the request path.
"""

import json
import os
import re
import urllib.request


LAB_REPORT_SYSTEM_PROMPT = """SYSTEM PROMPT — Lab Report & Prescription Normalization

You are a medical document normalization engine. Your ONLY job is to convert extracted document text/structure into a fixed JSON schema. You do not diagnose, interpret, or make clinical judgments. You do not add information that is not present in the input. You do not guess values you cannot find — you mark them null.

INPUT: Structured text/JSON from an OCR/extraction stage, for a lab report or prescription. The input may have residual noise from table extraction, OCR errors in numbers/units, or inconsistent structure.

OUTPUT: Valid JSON only. No prose, no explanation, no markdown formatting, no code fences. If you cannot produce valid JSON, output {"error": "unparseable", "raw_input_excerpt": "<first 100 chars>"}.

DOCUMENT TYPE DETECTION: Determine LAB_REPORT vs PRESCRIPTION based on structure. Output in "document_type".

NORMALIZATION RULES:
1. Test name normalization: map common abbreviations to full clinical names (Hb/HGB → Hemoglobin, WBC → White Blood Cell Count, etc.). Always preserve original in raw_test_name.
2. Unit normalization: if ambiguous/missing but inferable, fill it in but mark ocr_confidence as "medium", not "high".
3. Never compute abnormal flags yourself by comparing value to range — only populate flag_in_source if the SOURCE document explicitly printed a flag (H, L, Abn, etc.). Downstream rule-engine logic handles range comparison. Do not conflate extraction with interpretation.
4. If a row is ambiguous due to table misalignment, do your best single-row reconstruction and mark ocr_confidence as "low" rather than dropping the row.
5. Never fabricate a reference range if none is present — leave range_low/range_high/range_raw null.
6. If patient identity fields are absent, leave null. Never infer age/sex from test types.
7. Preserve panel structure as printed if panel headers exist. If flat/ungrouped, use a single panel named "Ungrouped".

WHAT YOU MUST NEVER DO:
- Never output a diagnosis, interpretation, or clinical recommendation.
- Never output a flag or pattern determination based on value-vs-range comparison — that is downstream, deterministic logic, not yours.
- Never omit a row because you're unsure — extract with low confidence rather than dropping data silently.
- Never output anything except the JSON object.
"""


# --- Optional SLM backend configuration ---------------------------------
# LAB_SLM_PROVIDER: '' (default, deterministic engine) | 'openai-compatible'
# LAB_SLM_URL:      chat completions endpoint, e.g. http://localhost:1234/v1/chat/completions
# LAB_SLM_MODEL:    model id served by the endpoint
# LAB_SLM_API_KEY:  optional bearer token
LAB_SLM_PROVIDER = os.getenv('LAB_SLM_PROVIDER', '').strip()
LAB_SLM_URL = os.getenv('LAB_SLM_URL', '').strip()
LAB_SLM_MODEL = os.getenv('LAB_SLM_MODEL', '').strip()
LAB_SLM_API_KEY = os.getenv('LAB_SLM_API_KEY', '').strip()


# --- Test name normalization (abbrev -> full clinical name) -------------
TEST_NAME_MAP = {
    'hb': 'Hemoglobin', 'hgb': 'Hemoglobin',
    'wbc': 'White Blood Cell Count', 'tlc': 'White Blood Cell Count',
    'rbc': 'Red Blood Cell Count',
    'plt': 'Platelet Count', 'plt count': 'Platelet Count',
    'hct': 'Hematocrit', 'pcv': 'Hematocrit',
    'mcv': 'Mean Corpuscular Volume',
    'mch': 'Mean Corpuscular Hemoglobin',
    'mchc': 'Mean Corpuscular Hemoglobin Concentration',
    'rdw': 'Red Cell Distribution Width',
    'esr': 'Erythrocyte Sedimentation Rate',
    'crp': 'C-Reactive Protein',
    'neut': 'Neutrophils', 'neuts': 'Neutrophils',
    'lymph': 'Lymphocytes', 'lymp': 'Lymphocytes',
    'eos': 'Eosinophils', 'baso': 'Basophils',
    'fbs': 'Fasting Blood Glucose', 'fbg': 'Fasting Blood Glucose',
    'ppbs': 'Postprandial Blood Glucose', 'ppbg': 'Postprandial Blood Glucose',
    'hba1c': 'Glycated Hemoglobin (HbA1c)',
    'bun': 'Blood Urea Nitrogen',
    'sgot': 'Aspartate Aminotransferase (AST)', 'ast': 'Aspartate Aminotransferase (AST)',
    'sgpt': 'Alanine Aminotransferase (ALT)', 'alt': 'Alanine Aminotransferase (ALT)',
    'alp': 'Alkaline Phosphatase',
    'tsh': 'Thyroid Stimulating Hormone',
    't3': 'Triiodothyronine (T3)',
    't4': 'Thyroxine (T4)',
    'hdl': 'HDL Cholesterol',
    'ldl': 'LDL Cholesterol',
    'vldl': 'VLDL Cholesterol',
    'tg': 'Triglycerides',
    'na': 'Sodium', 'na+': 'Sodium', 'sodium na': 'Sodium',
    'k': 'Potassium', 'k+': 'Potassium',
    'cl': 'Chloride', 'cl-': 'Chloride',
    'ca': 'Calcium',
    'creatinine': 'Serum Creatinine', 'creat': 'Serum Creatinine',
    's creatinine': 'Serum Creatinine', 's. creatinine': 'Serum Creatinine',
    'cholesterol total': 'Total Cholesterol', 'total cholesterol': 'Total Cholesterol',
    'cholesterol, total': 'Total Cholesterol',
    'urea': 'Blood Urea',
    'uric acid': 'Uric Acid',
}


def _normalize_lookup_key(name: str) -> str:
    return re.sub(r'[^a-z0-9 ]', ' ', name.lower()).strip()


def normalize_test_name(raw_name: str):
    """Map a raw test name to its full clinical name, or None if unknown."""
    key = _normalize_lookup_key(raw_name)
    if not key:
        return None
    if key in TEST_NAME_MAP:
        return TEST_NAME_MAP[key]
    # Try the last token (handles prefixes like "S. Creatinine (Serum)").
    tokens = key.split()
    for token in reversed(tokens):
        if token in TEST_NAME_MAP:
            return TEST_NAME_MAP[token]
    return None


# --- Value / unit / range / flag parsing --------------------------------

_NUMBER_RE = re.compile(
    r'(?<![\w.])(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(?![\w])'
)

_UNIT_PATTERN = (
    r'(?:g/dL|mg/dL|µg/dL|ug/dL|ng/mL|ng/dL|pg/mL|pg/pg|g/L|mg/L|µg/L|ug/L|'
    r'mmol/L|µmol/L|umol/L|mEq/L|meq/L|'
    r'U/L|IU/L|mIU/mL|µIU/mL|uIU/mL|IU/mL|U/mL|'
    r'10\^?3/(?:uL|µL|ul|μL)|10\^?6/(?:uL|µL|ul|μL)|10\^?9/L|10\^?12/L|'
    r'cells/uL|cells/HPF|/HPF|/uL|/µL|/ul|'
    r'copies/mL|fL|mm/hr|mm/h|%|ratio)'
)
_UNIT_RE = re.compile(r'^' + _UNIT_PATTERN + r'$', re.IGNORECASE)
_UNIT_SEARCH_RE = re.compile(_UNIT_PATTERN, re.IGNORECASE)

_RANGE_PAIR_RE = re.compile(
    r'(?<![\d.])(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*'
    r'(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(?![\d.])',
    re.IGNORECASE,
)
_RANGE_LT_RE = re.compile(r'(?:<|≤|<=|less than\s*|up to\s*|upto\s*)\s*(\d+(?:\.\d+)?)', re.IGNORECASE)
_RANGE_GT_RE = re.compile(r'(?:>|≥|>=|greater than\s*|more than\s*)\s*(\d+(?:\.\d+)?)', re.IGNORECASE)

# Only source-printed flags qualify. Case-sensitive for single letters so
# "h"/"l" inside prose cannot be mistaken for flags.
_SOURCE_FLAG_TOKENS = {'H', 'HH', 'L', 'LL', 'A', 'C'}
_SOURCE_FLAG_WORDS_RE = re.compile(r'\b(High|Low|Abn|Abnormal|Critical)\b\.?', re.IGNORECASE)
_SOURCE_FLAG_STARS_RE = re.compile(r'\*{1,2}$')

_VALUE_ROW_MARKER_RE = re.compile(r'(?i)\b(value|result|finding)\b')


def _parse_number(text: str):
    m = _NUMBER_RE.search(text)
    if not m:
        return None
    return float(m.group(1).replace(',', ''))


def _looks_like_unit(text: str) -> bool:
    return bool(_UNIT_RE.match(text.strip().rstrip('.')))


def _parse_range(text: str):
    """Return (range_low, range_high, range_raw) or (None, None, None)."""
    t = text.strip()
    m = _RANGE_PAIR_RE.search(t)
    if m:
        return float(m.group(1).replace(',', '')), float(m.group(2).replace(',', '')), m.group(0)
    m = _RANGE_LT_RE.search(t)
    if m:
        return None, float(m.group(1)), m.group(0).strip()
    m = _RANGE_GT_RE.search(t)
    if m:
        return float(m.group(1)), None, m.group(0).strip()
    return None, None, None


def _find_source_flag(cells: list):
    """Return a source-printed flag token or None. Only explicit flags in
    the source text qualify — never a computed value-vs-range comparison."""
    for cell in reversed(cells):
        text = (cell.get('text') or '').strip()
        if not text:
            continue
        m = _SOURCE_FLAG_WORDS_RE.search(text)
        if m:
            return m.group(1)
        tokens = text.split()
        if tokens:
            last = tokens[-1].rstrip('.,;:()')
            stars = _SOURCE_FLAG_STARS_RE.search(last)
            if stars and len(last) == len(stars.group(0)):
                return last
            last_bare = re.sub(r'\*+$', '', last)
            if last_bare in _SOURCE_FLAG_TOKENS:
                return last_bare
    return None


def _strip_flag(text: str, flag: str) -> str:
    if not flag:
        return text
    return re.sub(r'(?:\b' + re.escape(flag) + r'\b\.?|\*{1,2})\s*$', '', text).strip()


# --- Row / panel construction -------------------------------------------

def _value_bbox(test: dict, value_cell: dict | None) -> dict | None:
    if value_cell is None:
        return None
    if value_cell.get('page') is None or value_cell.get('bbox') is None:
        return None
    return {'page': value_cell['page'], 'bbox': value_cell['bbox']}


def _parse_table_row(row: dict, engine_degraded: bool) -> dict | None:
    """Build one test entry from a Stage 1 table row (or None if the row
    carries no test-like content at all)."""
    cells = [c for c in row.get('cells', []) if (c.get('text') or '').strip()]
    if not cells:
        return None

    data_cells = [c for c in cells if not c.get('is_header')]
    if not data_cells:
        # Table detection sometimes mislabels a data row as header rows.
        # Rows containing numbers are treated as data, never dropped.
        row_text = ' '.join(c['text'] for c in cells)
        if _NUMBER_RE.search(row_text):
            data_cells = cells
        else:
            return None

    single_cell = len(data_cells) == 1
    name_cell = data_cells[0]
    rest_cells = data_cells[1:]

    raw_test_name = name_cell['text'].strip()

    # Single-cell blobs have name+value fused: split off the leading name
    # segment before the first digit so "Hemoglobin (Hb) 11.2 g/dL ..."
    # becomes name "Hemoglobin (Hb)" and value 11.2.
    if single_cell:
        head_m = _NAME_DIGITS_RE.match(raw_test_name)
        if head_m:
            rest_cells.append({**name_cell, 'text': raw_test_name[head_m.end(1):]})
            raw_test_name = head_m.group(1).strip()
    if not raw_test_name or _VALUE_ROW_MARKER_RE.search(raw_test_name):
        # A column-header row slipped through without is_header.
        if len(data_cells) >= 2 and not _NUMBER_RE.search(' '.join(c['text'] for c in data_cells)):
            return None

    value = None
    unit = None
    range_low = range_high = range_raw = None
    flag_in_source = None
    value_cell = None
    unit_inferred = False

    remaining = list(rest_cells)

    if not single_cell:
        # Locate the first cell that parses as a number -> value cell.
        for idx, cell in enumerate(remaining):
            num_match = _NUMBER_RE.search(cell['text'])
            if num_match:
                value = float(num_match.group(1).replace(',', ''))
                value_cell = cell
                after_value = cell['text'][num_match.end():].strip()
                unit_m = _UNIT_SEARCH_RE.match(after_value.strip())
                if unit_m:
                    unit = unit_m.group(0)
                    after_value = after_value[unit_m.end():].strip()
                # Ranges often share the value cell ("230 mg/dL <200 H").
                low, high, raw = _parse_range(after_value)
                if low is not None or high is not None:
                    range_low, range_high, range_raw = low, high, raw
                remaining = remaining[idx + 1:]
                break

    if single_cell:
        # Single-row reconstruction: the name/value/unit/range are fused in
        # one blob; tokens _after_ the split head carry value/unit/range.
        blob_parts = [c['text'] for c in rest_cells if (c.get('text') or '').strip()]
        if not blob_parts:
            blob_parts = [' '.join(f'{c["text"]}' for c in rest_cells)]
        blob = ' '.join(blob_parts)
        num_match = _NUMBER_RE.search(blob)
        if num_match is None:
            return None
        value = float(num_match.group(1).replace(',', ''))
        value_cell = name_cell
        rest_after_value = blob[num_match.end():]
        unit_m = _UNIT_SEARCH_RE.match(rest_after_value.strip())
        if unit_m:
            unit = unit_m.group(0)
            rest_after_value = rest_after_value[unit_m.end():]
        range_raw_text = rest_after_value
    else:
        range_raw_text = None
        for cell in remaining:
            text = cell['text'].strip()
            if range_low is None and range_high is None and range_raw is None:
                low, high, raw = _parse_range(text)
                if low is not None or high is not None:
                    range_low, range_high, range_raw = low, high, raw
                    continue
            if unit is None and _looks_like_unit(text):
                unit = text.rstrip('.')
                continue

    if range_raw_text and range_low is None and range_high is None:
        low, high, raw = _parse_range(range_raw_text)
        if low is not None or high is not None:
            range_low, range_high, range_raw = low, high, raw
        elif _parse_number(range_raw_text) is not None and not unit:
            # A bare number in place of the range is conventionally an upper
            # bound, but that is an inference — cap confidence at medium.
            range_high = _parse_number(range_raw_text)
            range_raw = range_raw_text.strip()
            unit_inferred = True

    flag_in_source = _find_source_flag(cells)
    if flag_in_source:
        raw_test_name = _strip_flag(raw_test_name, flag_in_source)

    normalized = normalize_test_name(raw_test_name)
    if normalized is None and not raw_test_name:
        return None

    # --- ocr_confidence -------------------------------------------------
    if single_cell or engine_degraded:
        confidence = 'low'
    elif value is not None and unit is None and normalized is None:
        confidence = 'medium'
    elif value is not None and unit is None:
        # Missing but inferable unit context.
        confidence = 'medium'
    elif range_raw is not None and unit_inferred:
        confidence = 'medium'
    elif value is None:
        confidence = 'low'
    else:
        confidence = 'high'

    test = {
        'test_name': normalized or raw_test_name,
        'raw_test_name': raw_test_name,
        'value': value,
        'unit': unit,
        'range_low': range_low,
        'range_high': range_high,
        'range_raw': range_raw,
        'flag_in_source': flag_in_source,
        'ocr_confidence': confidence,
        'source_bbox': _value_bbox(value, value_cell),
    }
    return test


def _panel_name_for_table(table: dict, preceding_elements: list) -> str:
    """Best-effort panel header from elements printed before the table."""
    for el in reversed(preceding_elements):
        text = (el.get('text') or '').strip()
        if not text or len(text) > 120:
            continue
        if el.get('type') in ('heading', 'caption'):
            return text
        if _NUMBER_RE.search(text):
            continue
        letters = [c for c in text if c.isalpha()]
        if letters and sum(1 for c in letters if c.isupper()) / len(letters) > 0.7:
            return text
    return 'Ungrouped'


_PATIENT_NAME_RE = re.compile(r'(?i)\bpatient(?:\s*name)?\s*[:\-]\s*([A-Za-z][A-Za-z .\'\-]{1,58})')
_AGE_RE = re.compile(r'(?i)\bage\s*[:\-]?\s*(\d{1,3})\b')
_SEX_LABELED_RE = re.compile(r'(?i)\bsex(?:/gender)?\s*[:\-]?\s*([A-Za-z]+)')
_SEX_SLASH_RE = re.compile(r'(?i)\b\d{1,3}\s*/\s*([MFT])\b')
_DATE_RE = re.compile(
    r'(?i)\b(?:report\s*)?date\s*[:\-]?\s*([0-9]{1,4}[/.-][0-9]{1,2}[/.-][0-9]{2,4})'
)
_LAB_HINT_RE = re.compile(r'(?i)\b(lab|laboratory|diagnostic|patholog|hospital|clinic)\b')


def _extract_patient_context(elements: list) -> dict:
    """Patient context strictly from text present in the document header.
    Never inferred from test types (system prompt rule 6)."""
    context = {'name': None, 'age': None, 'sex': None, 'report_date': None}
    for el in elements:
        text = el.get('text') or ''
        if context['name'] is None:
            m = _PATIENT_NAME_RE.search(text)
            if m:
                name = m.group(1).strip()
                name = re.split(r'(?i)\b(?:age|sex|date)\b', name)[0].strip()
                if name:
                    context['name'] = name
        if context['age'] is None:
            m = _AGE_RE.search(text)
            if m:
                context['age'] = int(m.group(1))
        if context['sex'] is None:
            m = _SEX_LABELED_RE.search(text)
            if m:
                token = m.group(1).lower()
                if token.startswith('m'):
                    context['sex'] = 'M'
                elif token.startswith('f'):
                    context['sex'] = 'F'
            else:
                m = _SEX_SLASH_RE.search(text)
                if m:
                    token = m.group(1).upper()
                    context['sex'] = 'M' if token == 'M' else 'F'
        if context['report_date'] is None:
            m = _DATE_RE.search(text)
            if m:
                context['report_date'] = m.group(1)
    return context


_LAB_HINT_RE = re.compile(r'(?i)\b(lab|laboratory|diagnostic|patholog|hospital|clinic)\b')
_HEADER_LABEL_RE = re.compile(
    r'(?i)\b(patient|age|sex|date|address|report no|ref no|sample no|lab |laboratory|panel|page \d)\b'
)

_NAME_DIGITS_RE = re.compile(r'^\s*([A-Za-z][A-Za-z .\'()/,%^0-9\-]{2,}?)\s*\d')

_TEST_LEXICON_RE = re.compile(
    r'(?i)\b(hb|hgb|hemoglobin|wbc|tlc|rbc|plt|platelet|hct|pcv|hematocrit|'
    r'mcv|mch|mchc|rdw|esr|crp|neut|lymph|eos|baso|mono|'
    r'glucose|fbs|fbg|ppbs|ppbg|rbs|hba1c|sugar|'
    r'cholesterol|hdl|ldl|vldl|triglyceride|lipid|'
    r'sgot|sgpt|ast|alt|alp|bilirubin|protein|albumin|globulin|'
    r'urea|bun|creatinine|creat|uric acid|sodium|potassium|potas|chloride|calcium|'
    r'tsh|t3|t4|thyroid|testosterone|cortisol|vitamin|iron|ferritin|calcium|'
    r'urine|blood|count|cbc|serum|s\.|total|direct|indirect|u\/l|mg\/dl|g\/dl)\b'
)

_MAX_FREE_LINE_CHARS = 160
_MAX_BLOB_SEGMENT_CHARS = 160

_BLOB_NAME_RE = None


def _blob_name_pattern():
    """Regex matching any known test name/abbreviation (longest first)."""
    global _BLOB_NAME_RE
    if _BLOB_NAME_RE is None:
        names = sorted(set(TEST_NAME_MAP.keys()), key=len, reverse=True)
        _BLOB_NAME_RE = re.compile(r'(?i)\b(' + '|'.join(re.escape(n) for n in names) + r')\b')
    return _BLOB_NAME_RE


def _scan_blob_for_test_rows(text: str, bbox, page, seen_names: set) -> list:
    """Recover test rows fused into long text elements (table lines that
    extraction merged into a caption/paragraph blob). Each known test name
    anchors a segment parsed for value/unit/range — always 'low' confidence
    reconstructions, never dropped, never fabricated.

    Short abbreviations (<=2 chars) require a unit or range nearby to count
    as evidence, so stray text matches cannot become tests.
    """
    tests = []
    matches = list(_blob_name_pattern().finditer(text))
    for idx, m in enumerate(matches):
        seg_end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        segment = text[m.start():min(seg_end, m.start() + _MAX_BLOB_SEGMENT_CHARS)]
        raw_name = m.group(1).strip()
        key = _normalize_lookup_key(raw_name)
        if key in seen_names:
            continue

        rest = segment[m.end() - m.start():]
        num_match = _NUMBER_RE.search(rest)
        if not num_match:
            continue

        after = rest[num_match.end():].strip()
        unit_m = _UNIT_SEARCH_RE.search(after[:32])
        unit = unit_m.group(0) if unit_m else None
        range_low, range_high, range_raw = _parse_range(after)
        if range_low is None and range_high is None and len(raw_name) <= 2 and unit is None:
            continue

        flag = _find_source_flag([{'text': segment}])
        name = raw_name
        if flag:
            name = _strip_flag(name, flag)

        tests.append({
            'test_name': normalize_test_name(raw_name) or raw_name,
            'raw_test_name': name,
            'value': float(num_match.group(1).replace(',', '')),
            'unit': unit,
            'range_low': range_low,
            'range_high': range_high,
            'range_raw': range_raw,
            'flag_in_source': flag,
            'ocr_confidence': 'low',
            'source_bbox': (
                {'page': page, 'bbox': bbox}
                if page is not None and bbox is not None
                else None
            ),
        })
        seen_names.add(key)
    return tests


def _extract_lab_name(elements: list):
    """Lab name from header text — best effort, only when a lab-ish word
    appears near the start of a text element."""
    for el in elements:
        text = (el.get('text') or '').strip()
        if not text:
            continue
        m = _LAB_HINT_RE.search(text[:120])
        if m and m.start() <= 40:
            candidate = text[:60]
            candidate = re.split(r'(?i)\b(patient|age|sex|date|address|report)\b', candidate)[0]
            candidate = candidate.strip(' ,:-')
            if candidate:
                return candidate
    return None


def _bbox_inside(element_bbox, container_bbox, tol: float = 5.0) -> bool:
    if not element_bbox or not container_bbox:
        return False
    if len(element_bbox) < 4 or len(container_bbox) < 4:
        return False
    ex1, ey1, ex2, ey2 = element_bbox[:4]
    cx1, cy1, cx2, cy2 = container_bbox[:4]
    return (
        ex1 >= cx1 - tol and ex2 <= cx2 + tol
        and ey1 >= cy1 - tol and ey2 <= cy2 + tol
    )


def _parse_free_line(line: str, bbox, page) -> dict | None:
    """Parse one free-text line (outside tables) as a possible test row.

    Conservative filters skip header/label lines; anything parsed here is a
    reconstruction, so ocr_confidence is always 'low'.
    """
    line = line.strip()
    if not line or len(line) < 3 or len(line) > _MAX_FREE_LINE_CHARS:
        return None
    if _HEADER_LABEL_RE.search(line):
        return None
    if not _NUMBER_RE.search(line):
        return None

    row = {
        'cells': [{
            'text': line, 'bbox': bbox, 'page': page,
            'is_header': False, 'row': None, 'col': None,
        }]
    }
    test = _parse_table_row(row, engine_degraded=True)
    if test:
        test['source_bbox'] = (
            {'page': page, 'bbox': bbox}
            if page is not None and bbox is not None
            else None
        )
    return test


def _missed_rows_from_text(stage1: dict, table_raw_names: set) -> list:
    """Find test rows that landed in plain text elements instead of detected
    tables (common when extraction merges lines above/below a table)."""
    elements = stage1.get('elements') or []
    tables = stage1.get('tables') or []
    table_boxes = [(t.get('page'), t.get('bbox')) for t in tables]

    tests = []
    seen_names = set(table_raw_names)
    for el in elements:
        if el.get('type') == 'table':
            continue
        page = el.get('page')
        bbox = el.get('bbox')
        if any(
            page == tpage and _bbox_inside(bbox, tbbox)
            for tpage, tbbox in table_boxes
        ):
            continue
        el_text = (el.get('text') or '')
        # Long blobs: scan for test names fused into merged text.
        tests.extend(_scan_blob_for_test_rows(el_text, bbox, page, seen_names))
        for line in el_text.split('\n'):
            if line.strip() == el_text.strip() and len(line.strip()) > _MAX_FREE_LINE_CHARS:
                continue  # blob lines are handled by the scanner above
            test = _parse_free_line(line, bbox, page)
            if not test:
                continue
            normalized = normalize_test_name(test['raw_test_name'])
            if normalized is not None:
                test['test_name'] = normalized
            elif not _TEST_LEXICON_RE.search(test['raw_test_name']):
                # Unrecognizable free text with a stray number — not a test
                # row, never silently kept.
                continue
            key = _normalize_lookup_key(test['raw_test_name'])
            if key in seen_names:
                continue
            seen_names.add(key)
            tests.append(test)
    return tests


def _parse_from_plain_text(stage1: dict) -> list:
    """Fallback line parser when extraction produced no tables (e.g. the
    EasyOCR path). Every test is reconstructed at 'low' confidence."""
    tests = []
    for line in (stage1.get('text') or '').splitlines():
        line = line.strip()
        if not line or len(line) < 3:
            continue
        row = {'cells': [{'text': line, 'bbox': None, 'page': None, 'is_header': False, 'row': None, 'col': None}]}
        test = _parse_table_row(row, engine_degraded=True)
        if test:
            test['source_bbox'] = None
            tests.append(test)
    return tests


def _build_document(stage1: dict) -> dict:
    elements = stage1.get('elements') or []
    tables = stage1.get('tables') or []
    engine_degraded = stage1.get('extraction_engine') == 'easyocr_fallback'

    panels = []
    table_raw_names = set()
    if tables:
        # Elements are in document order; approximate "elements before this
        # table" by page + document position of the first table row.
        seen_pages = set()
        for table in tables:
            table_page = table.get('page')
            preceding = []
            for el in elements:
                el_page = el.get('page')
                if el_page is None or table_page is None or el_page <= table_page:
                    preceding.append(el)
            # Avoid repeating every earlier-page element for later tables.
            if table_page in seen_pages:
                preceding = preceding[-6:]
            seen_pages.add(table_page)

            tests = []
            for row in table.get('rows') or []:
                test = _parse_table_row(row, engine_degraded)
                if test:
                    tests.append(test)
                    table_raw_names.add(_normalize_lookup_key(test['raw_test_name']))
            panels.append({
                'panel_name': _panel_name_for_table(table, preceding),
                'tests': tests,
            })

        # Test rows that landed in plain text elements (outside any detected
        # table) are reconstructed rather than dropped — at 'low' confidence.
        missed = _missed_rows_from_text(stage1, table_raw_names)
        if missed:
            panels.append({'panel_name': 'Ungrouped', 'tests': missed})
    else:
        tests = _parse_from_plain_text(stage1)
        if tests:
            panels.append({'panel_name': 'Ungrouped', 'tests': tests})

    return {
        'document_type': 'lab_report',
        'patient_context': _extract_patient_context(elements),
        'lab_name': _extract_lab_name(elements),
        'panels': panels,
    }


def _series_key(test: dict) -> tuple:
    """Identity of a row for dedup: canonical test name + unit."""
    return ((test.get('test_name') or '').lower(), test.get('unit') or '')


def _build_document_with_recovery(stage1: dict) -> dict:
    """_build_document plus a flat-text recovery pass.

    Mirrors `mobile/lib/lab/extract.dart::mergeLabDocuments`. When table
    detection is slightly wrong, `_build_document` trusts the table and can
    drop rows a flat-text parse would have caught. This re-parses the full OCR
    text with the plain-text fallback and appends any row the structural pass
    missed (deduped by canonical test_name + unit) to an "Ungrouped" panel.

    Strictly additive: it can only ever ADD rows, never remove or rewrite one.
    """
    document = _build_document(stage1)
    if not (stage1.get('text') or '').strip():
        return document

    seen = {
        _series_key(test)
        for panel in (document.get('panels') or [])
        for test in (panel.get('tests') or [])
    }
    # Two complementary re-reads of the full text: the line parser (one test
    # per line) and the blob scanner (test names fused into long merged text,
    # e.g. "Urea 30 mg/dL Creatinine 1.2 mg/dL").
    text = stage1.get('text') or ''
    candidates = list(_parse_from_plain_text(stage1))
    candidates += _scan_blob_for_test_rows(text, None, None, set())

    extras = []
    for test in candidates:
        key = _series_key(test)
        if key in seen:
            continue
        seen.add(key)
        extras.append(test)
    if not extras:
        return document

    panels = list(document.get('panels') or [])
    for panel in panels:
        if panel.get('panel_name') == 'Ungrouped':
            panel['tests'] = list(panel.get('tests') or []) + extras
            break
    else:
        panels.append({'panel_name': 'Ungrouped', 'tests': extras})
    document['panels'] = panels
    return document


# --- Optional SLM backend ------------------------------------------------

def _slm_configured() -> bool:
    return LAB_SLM_PROVIDER == 'openai-compatible' and bool(LAB_SLM_URL) and bool(LAB_SLM_MODEL)


def _stage1_input_for_slm(stage1: dict) -> str:
    """Compact text/JSON representation of Stage 1 output for the model."""
    payload = {
        'text': stage1.get('text'),
        'elements': stage1.get('elements'),
        'tables': stage1.get('tables'),
    }
    return json.dumps(payload, ensure_ascii=False)


def _run_slm(stage1: dict) -> dict:
    """Call the configured OpenAI-compatible SLM endpoint with the
    normalization system prompt. Raises on any failure."""
    messages = [
        {'role': 'system', 'content': LAB_REPORT_SYSTEM_PROMPT},
        {'role': 'user', 'content': _stage1_input_for_slm(stage1)},
    ]
    body = json.dumps({
        'model': LAB_SLM_MODEL,
        'messages': messages,
        'temperature': 0,
        'response_format': {'type': 'json_object'},
    }).encode('utf-8')

    req = urllib.request.Request(
        LAB_SLM_URL,
        data=body,
        headers={
            'Content-Type': 'application/json',
            **({'Authorization': f'Bearer {LAB_SLM_API_KEY}'} if LAB_SLM_API_KEY else {}),
        },
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        payload = json.loads(resp.read().decode('utf-8'))

    content = payload['choices'][0]['message']['content']
    doc = json.loads(content)
    if not isinstance(doc, dict) or 'panels' not in doc or 'document_type' not in doc:
        raise ValueError('SLM output does not match the lab report schema')
    if doc.get('error') == 'unparseable':
        raise ValueError('SLM reported unparseable input')
    return doc


# --- Entry point ----------------------------------------------------------

def run_stage2(stage1: dict) -> tuple:
    """Normalize Stage 1 output into the lab report schema.

    Returns (document, engine, warnings) where document matches the fixed
    schema and engine is 'deterministic-v1' or the SLM model id.
    """
    if _slm_configured():
        try:
            doc = _run_slm(stage1)
            return doc, LAB_SLM_MODEL, []
        except Exception as e:
            warning = f'SLM normalization failed ({e}); falling back to deterministic engine'
            print(f'  Stage 2: {warning}')
            return _build_document_with_recovery(stage1), 'deterministic-v1', [warning]

    return _build_document_with_recovery(stage1), 'deterministic-v1', []
