#!/usr/bin/env python3
"""Run the backend Stage 2 deterministic reference over a Stage 1 fixture.

`lab_pipeline.slm_stage` is stdlib-only (json, os, re, urllib.request), so this
needs no service, database, or model. It is the executable oracle for the Dart
port in `mobile/lib/lab/rule_engine.dart`: the parity test asserts the two
produce identical documents for the same fixture.

Usage:
    python backend/scripts/run_stage2_fixture.py <stage1.json>
    python backend/scripts/run_stage2_fixture.py --dump-map
    python backend/scripts/run_stage2_fixture.py --check <stage1.json> <expected.json>
    python backend/scripts/run_stage2_fixture.py --check-all mobile/test/fixtures/lab
"""

import argparse
import json
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from lab_pipeline.slm_stage import TEST_NAME_MAP, _build_document  # noqa: E402


def _load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding='utf-8'))


def _check(fixture: Path, expected_path: Path) -> bool:
    actual = _build_document(_load(str(fixture)))
    expected = _load(str(expected_path))
    if actual == expected:
        print(f'OK  {fixture.name}')
        return True
    print(json.dumps(actual, indent=2, ensure_ascii=False))
    print(f'MISMATCH  {fixture.name}', file=sys.stderr)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fixture', nargs='?', help='stage1 JSON fixture')
    parser.add_argument('--dump-map', action='store_true',
                        help='print TEST_NAME_MAP as JSON and exit')
    parser.add_argument('--check', nargs=2, metavar=('FIXTURE', 'EXPECTED'),
                        help='compare _build_document(fixture) to an expected JSON file')
    parser.add_argument('--check-all', metavar='DIR',
                        help='compare every *.stage1.json in DIR to its .expected.json')
    args = parser.parse_args()

    if args.dump_map:
        print(json.dumps(TEST_NAME_MAP, indent=2, sort_keys=True, ensure_ascii=False))
        return 0

    if args.check_all:
        directory = Path(args.check_all)
        fixtures = sorted(directory.glob('*.stage1.json'))
        if not fixtures:
            print(f'no *.stage1.json fixtures in {directory}', file=sys.stderr)
            return 2
        ok = all(
            _check(f, f.with_name(f.name.replace('.stage1.json', '.expected.json')))
            for f in fixtures
        )
        return 0 if ok else 1

    if args.check:
        fixture, expected_path = args.check
        return 0 if _check(Path(fixture), Path(expected_path)) else 1

    if not args.fixture:
        parser.error('a fixture path is required (or use --dump-map/--check/--check-all)')

    document = _build_document(_load(args.fixture))
    print(json.dumps(document, indent=2, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
