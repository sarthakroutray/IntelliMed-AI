"""
Fine-tuning dataset preparation for the Stage 2 SLM (lab report
normalization). Standalone offline script — NEVER part of the request path.

It converts labeled example pairs into JSONL chat-format training data:

    backend/scripts/slm_finetune_data/
        001_stage1.json        Stage 1 output (ocr_stage.run_stage1 result)
        001_stage2.json        expected Stage 2 output (normalized schema)
        ...

Usage:
    python scripts/prepare_slm_finetune_dataset.py \
        --data-dir scripts/slm_finetune_data --out scripts/slm_finetune_train.jsonl

Each pair is emitted as one JSONL line: {"messages": [system, user, assistant]}
using the exact LAB_REPORT_SYSTEM_PROMPT, so a fine-tuned model stays
prompt-compatible with the runtime hook in lab_pipeline.slm_stage.

Dataset requirements (flag before fine-tuning):
- 200+ labeled lab reports covering printed, scanned and table-heavy layouts,
  reviewed by a clinician; balance across labs/panels; include deliberately
  noisy OCR cases. Fewer examples should be treated as a blocker, not a
  nice-to-have.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from lab_pipeline.slm_stage import LAB_REPORT_SYSTEM_PROMPT  # noqa: E402

REQUIRED_TEST_KEYS = {
    'test_name', 'raw_test_name', 'value', 'unit',
    'range_low', 'range_high', 'range_raw', 'flag_in_source',
    'ocr_confidence', 'source_bbox',
}


def validate_stage2(doc: dict) -> list:
    """Reject labels that violate the schema or the normalization rules."""
    problems = []
    if doc.get('document_type') != 'lab_report':
        problems.append('document_type must be "lab_report" for this dataset')
    for key in ('patient_context', 'lab_name', 'panels'):
        if key not in doc:
            problems.append(f'missing key: {key}')
    for panel in doc.get('panels') or []:
        if 'panel_name' not in panel or 'tests' not in panel:
            problems.append(f'panel missing panel_name/tests: {panel}')
            continue
        for test in panel['tests']:
            missing = REQUIRED_TEST_KEYS - set(test)
            if missing:
                problems.append(
                    f'test {test.get("raw_test_name")!r} missing keys: {sorted(missing)}'
                )
            if test.get('abnormal') is not None or test.get('direction') is not None:
                problems.append(
                    f'test {test.get("raw_test_name")!r} contains Stage 3 fields '
                    '(abnormal/direction) — labels must never contain flags'
                )
    return problems


def build_example(stage1: dict, stage2: dict) -> dict:
    user_payload = {
        'text': stage1.get('text'),
        'elements': stage1.get('elements'),
        'tables': stage1.get('tables'),
    }
    return {
        'messages': [
            {'role': 'system', 'content': LAB_REPORT_SYSTEM_PROMPT},
            {'role': 'user', 'content': json.dumps(user_payload, ensure_ascii=False)},
            {'role': 'assistant', 'content': json.dumps(stage2, ensure_ascii=False)},
        ]
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', default=str(Path(__file__).parent / 'slm_finetune_data'))
    parser.add_argument('--out', default=str(Path(__file__).parent / 'slm_finetune_train.jsonl'))
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.exists():
        print(f'No dataset directory found at {data_dir}.')
        print('Create it with pairs: <id>_stage1.json (Stage 1 output) + <id>_stage2.json (label).')
        return 1

    stage1_files = sorted(data_dir.glob('*_stage1.json'))
    if not stage1_files:
        print(f'No *_stage1.json examples found in {data_dir}.')
        return 1

    written = 0
    rejected = 0
    with open(args.out, 'w', encoding='utf-8') as out:
        for stage1_path in stage1_files:
            label_path = Path(str(stage1_path).replace('_stage1.json', '_stage2.json'))
            if not label_path.exists():
                print(f'  SKIP {stage1_path.name}: no matching label {label_path.name}')
                continue
            stage1 = json.loads(stage1_path.read_text(encoding='utf-8'))
            stage2 = json.loads(label_path.read_text(encoding='utf-8'))

            problems = validate_stage2(stage2)
            if problems:
                rejected += 1
                print(f'  REJECT {label_path.name}:')
                for p in problems:
                    print(f'    - {p}')
                continue

            out.write(json.dumps(build_example(stage1, stage2), ensure_ascii=False) + '\n')
            written += 1

    print(f'\nWrote {written} examples to {args.out} ({rejected} rejected).')
    if written < 200:
        print(
            'WARNING: fewer than 200 reviewed examples — flag this before '
            'fine-tuning; the model will not generalize to real lab reports.'
        )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
