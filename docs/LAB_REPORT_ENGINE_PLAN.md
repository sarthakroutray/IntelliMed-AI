# Lab report understanding on-device — rule engine + summarizer split

Status: proposed
Scope: `mobile/` only (no backend changes)
Related: [mobile/docs/APP_SPIKE.md](mobile/docs/APP_SPIKE.md), `backend/lab_pipeline/`

## 1. Problem

On-device lab report results are poor. Two distinct causes, and the second one
is architectural rather than a tuning problem.

**Cause A — the OCR structure is discarded.** `mobile/lib/cnn_ocr.dart`'s
`OcrService.recognizeFile` returns `result.text` and nothing else:

```dart
final result = await _recognizer.processImage(input);
return result.text;            // <- everything below is thrown away
```

ML Kit actually returns a rich tree (verified in
`google_mlkit_text_recognition-0.17.1/lib/src/text_recognizer.dart`):

| Type | Fields available | Line |
|---|---|---|
| `RecognizedText` | `text`, `blocks` | 46, 49 |
| `TextBlock` | `text`, `lines`, `boundingBox: Rect`, `cornerPoints`, `recognizedLanguages` | 69–81 |
| `TextLine` | `text`, `elements`, `boundingBox: Rect`, `cornerPoints`, **`confidence: double?`**, `angle` | 118–138 |
| `TextElement` (a word) | `text`, `boundingBox: Rect`, **`confidence: double?`**, `symbols` | 181–202 |
| `TextSymbol` | `text`, `boundingBox: Rect` | 245–258 |

So we already have **word-level bounding boxes and per-word confidence** — and
we throw all of it away. `recognizedLanguages` and per-word `confidence` come
straight off the platform channel (`TextLine.fromJson` reads `json['confidence']`,
line 155), so they are real, not placeholders.

Consequence: with only flat text, a lab report table arrives as a stream of
lines whose reading order **interleaves columns**. `normalize.dart`'s
`_valueUnitRe` then guesses one test per line:

```dart
final _valueUnitRe = RegExp(
  r'([A-Za-z][A-Za-z .()/%^0-9\-]{2,}?)\s+(\d+(?:\.\d+)?)\s*([A-Za-z/%^µμ]+)?(?:\s+(\d+(?:\.\d+)?\s*[-–—]\s*\d+(?:\.\d+)?))?',
);
```

That single regex is the entire lab-report extractor. It cannot group panels,
cannot handle a fused `Hemoglobin (Hb) 11.2 g/dL 13.0-17.0` blob reliably,
cannot parse `<200` / `>4` ranges, cannot recognise a source-printed `H`/`L`
flag, and has no notion of a row or a column.

**Cause B — the SLM is the wrong tool for structure.** The on-device model is
`Falconsai/medical_summarization` (T5-small, 60M) behind the `summarize: `
prefix — a *summarizer*. `mobile/lib/slm_runtime.dart:156` builds its input as
`'summarize: $ocrText'`; the backend counterpart is
`backend/services.py:1390`. It was trained to compress prose, not to emit valid
JSON against a schema containing 10 mandatory keys per test row.

The naming is what made this confusing: `slm_runtime.dart` calls the model a
"standardizer", `README.md:134` calls it a "T5 standardizer", and the interface
still exposes `normalizeJson()` (`slm_runtime.dart:25, 53, 133`) which invites
exactly the misuse we want to prevent. `normalizeJson` is currently **dead** —
nothing calls it — so the live path only summarises. But the interface invites
the bug the user is hitting.

## 2. Key insight: the rule engine already exists

The backend does not use an LLM to structure lab reports either.
`backend/lab_pipeline/slm_stage.py` is a **deterministic rule engine** named
`deterministic-v1`; the LLM path is inert unless `LAB_SLM_PROVIDER=openai-compatible`
is configured (`slm_stage.py:701, 758`), which it is not.

`run_stage2` (`slm_stage.py:752`) is:

```python
if _slm_configured():
    ...
return _build_document(stage1), 'deterministic-v1', []
```

And `_build_document` (`slm_stage.py:647`) consumes Stage 1 — `elements[]` with
bboxes and `tables[].rows[].cells[]` — producing the exact 10-key test schema
that the mobile app's own `validateLabReport` and the server's
`_REQUIRED_LAB_TEST_KEYS` already enforce.

**So the right move is not to invent a parser. It is to (a) reconstruct the
Stage 1 structure on-device from ML Kit geometry, then (b) port `_build_document`
and friends to Dart.** We inherit a battle-tested algorithm, and — because
`slm_stage.py` imports only `json, os, re, urllib.request` (lines 28–31, all
stdlib) — we can run the Python reference in CI and diff it against the Dart
port on identical fixtures. That is a structural correctness guarantee we would
not get from a hand-rolled engine.

## 3. Target architecture

```
BEFORE
  image/PDF ─► ML Kit ─► result.text (flat) ─► normalize.dart regex ─► stage2
                                     └────────► T5 summarize(ocrText) ─► summary_context

AFTER
  image/PDF ─► ML Kit ─► OcrDocument (lines + words + bboxes + confidence)
                              │
                              ├─► structure.dart   → stage1-equivalent {elements[], tables[]}
                              │                        (NEW: row/column clustering)
                              └─► rule_engine.dart → stage2 {patient_context, lab_name, panels[]}
                                                        (PORTED from backend, verbatim behaviour)
                                                        │
                                                        └─► renderLabText(stage2) ─► T5 summarize()
                                                                                       → summary_context ONLY
```

Two invariants preserved:

1. **Never invent flags on-device.** The ported engine emits exactly the 10
   stage-2 keys and must never add `abnormal`/`direction`; those stay Stage 3
   and are added server-side. The server rejects them anyway
   (`backend/api/v2/ingest_schema.py`, and `validateLabReport` mirrors it).
2. **Never fabricate.** No computed ranges, no inferred patient identity, no
   invented test rows — mirrors the header comment at `slm_stage.py:13-18`.

## 4. Workstreams

### WS1 — Capture the OCR geometry (enabling change)

New `mobile/lib/lab/ocr_model.dart`:

```dart
/// One recognised word. Mirrors ML Kit's TextElement.
class OcrWord {
  final String text;
  final Rect bbox;          // non-nullable in the plugin, but guard anyway
  final double? confidence; // null on devices that don't report it
}

/// One visual line. Mirrors ML Kit's TextLine.
class OcrLine {
  final String text;
  final Rect bbox;
  final List<OcrWord> words;
  final double? confidence;
}

/// All lines for one page, in reading order.
class OcrPage {
  final int pageNumber;      // 1-based
  final int pixelWidth;
  final int pixelHeight;
  final List<OcrLine> lines;
}
```

Change `cnn_ocr.dart`:
- Add `Future<List<OcrPage>> recognizePages(List<File> pages)` that walks
  `result.blocks → lines → elements` and keeps boxes/confidence.
- Keep the existing `recognizeFile` (returns text) for the X-ray and
  prescription paths, which don't need geometry; implement it as
  `recognizePages(...).join('\n')` so there is one code path.
- Bounding boxes are in **bitmap pixels of the processed image**. Record
  `pixelWidth/Height` per page so all later geometry is relative
  (`x / pixelWidth`), which keeps the algorithm scale-invariant across photos,
  200-DPI PDF renders and different devices.

Note: `OcrService` is driven from `model_manager.dart` inside the serial
`InferenceQueue`; `recognizePages` must stay sequential per page (ML Kit
recognisers are not safe to drive concurrently) — this matches the existing
constraint documented on `_recognizeAll`.

### WS2 — Synthesise Stage 1 structure from geometry (the new part)

New `mobile/lib/lab/structure.dart`. Goal: produce an object that is
field-for-field compatible with the backend's stage 1, so WS3 ports cleanly.

```dart
class LabElement {                 // == backend 'elements[]'
  final String? type;              // 'heading' | 'caption' | 'text' | 'table'
  final String text;
  final List<double>? bbox;        // [x1,y1,x2,y2] normalised 0..1
  final int? page;
}

class LabCell {                    // == backend table cell
  final String text;
  final List<double>? bbox;
  final int? page;
  final bool isHeader;
  final int? row;
  final int? col;
}

class LabTableRow { final int? row; final List<LabCell> cells; }

class LabTable {                   // == backend 'tables[]'
  final List<double>? bbox;
  final int? page;
  final int nRows;
  final int nCols;
  final List<LabTableRow> rows;
}

class LabStage1 {
  final String extractionEngine;   // 'mlkit-geometry' | 'mlkit-lines-only'
  final String text;
  final List<LabElement> elements;
  final List<LabTable> tables;
  final List<String> warnings;
}
```

Algorithm, per page:

1. **Table region detection.** A line is *grid-like* when it splits into ≥3
   word groups separated by horizontal gaps greater than
   `1.6 × median word height`. A run of ≥3 consecutive grid-like lines (allowing
   a 1-line break) is a table region.
2. **Column boundaries.** Gather every word's x-interval in the region. Cluster
   word *left edges* with a tolerance of `1.5%` of page width; a cluster
   supported by ≥50% of the region's lines is a column. Columns are then
   ordered left→right and snapped so they don't overlap.
3. **Rows and cells.** One region line = one row. Each word is assigned to the
   nearest column by centre-x; words in the same column are concatenated with a
   single space and the cell bbox becomes the union of those word boxes. A row
   whose cells contain no number, or that matches the header lexicon
   (`test|result|unit|reference|ref|range|method|specimen`), is
   `isHeader: true`.
4. **Table bbox / page** = union of the region's line boxes and the page number.
5. **Panel header.** Mirrors `_panel_name_for_table` (`slm_stage.py:376`): walk
   the preceding elements in reverse, take the first that is short (<120 chars),
   contains no number, and is either a heading/caption or is >70% uppercase;
   else `'Ungrouped'`.
6. **Elements.** Every line *outside* a table region becomes a `LabElement`,
   with `type` inferred the same way (`heading` if all-caps and short,
   `caption` if it looks like a label, else `text`). This is what lets
   `_extract_patient_context`, `_extract_lab_name` and `_missed_rows_from_text`
   port unchanged.
7. **Degraded mode.** If a page yields no table regions at all, set
   `extractionEngine: 'mlkit-lines-only'`, emit no tables, and let the ported
   plain-text fallback run. This mirrors the backend's `easyocr_fallback` path
   (`ocr_stage.py:187-196`, `_parse_from_plain_text` at `slm_stage.py:631`) —
   rows recovered this way are `low` confidence, never dropped, never faked.

Edge cases to handle explicitly: two visual rows merged into one ML Kit line
(re-split by comparing each word's y-centre against the line's median and
splitting when the spread exceeds `0.6 × word height`); a value that wraps onto
a second line (attach an orphan line with no alphabetic cell to the previous
row); and rotated pages (`TextLine.angle` non-zero → warn, and skip table
detection for that page).

### WS3 — Port the rule engine

New `mobile/lib/lab/rule_engine.dart`, a faithful port. Function-by-function
mapping (all line refs are `backend/lab_pipeline/slm_stage.py`):

| Dart | Python | Notes |
|---|---|---|
| `_numberRe`, `_unitPattern`, `_rangePairRe`, `_rangeLtRe`, `_rangeGtRe`, `_sourceFlagTokens`, `_sourceFlagWordsRe`, `_sourceFlagStarsRe`, `_valueRowMarkerRe` | lines 136–165 | Port the regexes verbatim, including the `(?<![\w.])`/`(?![\w])` guards on numbers and the comma-group alternative `\d{1,3}(?:,\d{3})+` |
| `parseNumber(String) -> double?` | `_parse_number` 168 | |
| `looksLikeUnit(String) -> bool` | `_looks_like_unit` 175 | |
| `parseRange(String) -> ({double? low, double? high, String? raw})` | `_parse_range` 179 | Full-width `≤ ≥ – —`, `less than`, `up to`, `greater than`, `more than` |
| `findSourceFlag(List<LabCell>) -> String?` | `_find_source_flag` 194 | Case-sensitive single letters so prose `h`/`l` can't become flags |
| `stripFlag(String, String) -> String` | `_strip_flag` 216 | |
| `parseTableRow(LabTableRow, {required bool engineDegraded}) -> LabTest?` | `_parse_table_row` 232 | The core. Includes the single-cell fused-blob split via `_nameDigitsRe`, the "header row that slipped through" guard, the value-cell search, unit-from-value-cell, range-in-value-cell, and the exact `ocr_confidence` ladder at 347–359 |
| `scanBlobForTestRows(...)` | `_scan_blob_for_test_rows` 472 | `≤2`-char names require a nearby unit or range, so stray matches can't become tests |
| `parseFreeLine(...)` | `_parse_free_line` 558 | Always `low` confidence |
| `missedRowsFromText(...)` | `_missed_rows_from_text` 588 | Uses `_bboxInside` (545) to skip text inside table boxes |
| `parseFromPlainText(...)` | `_parse_from_plain_text` 631 | |
| `buildLabDocument(LabStage1) -> LabDocument` | `_build_document` 647 | |
| `extractPatientContext(List<LabElement>)` | `_extract_patient_context` 402 | Regexes at 392–399 |
| `extractLabName(List<LabElement>)` | `_extract_lab_name` 528 | |
| `panelNameForTable(...)` | `_panel_name_for_table` 376 | |

Test-name normalisation already exists in `mobile/lib/schemas.dart`
(`testNameMap`, `normalizeTestName`) but is weaker than the Python version: the
backend falls back to **the last token** of the key so `"S. Creatinine (Serum)"`
resolves (`slm_stage.py:126-131`). Move the map to
`mobile/lib/lab/test_names.dart`, port `_normalize_lookup_key` and the
last-token fallback, and keep `schemas.dart` re-exporting so existing callers
and tests don't break.

Output type mirrors the wire schema exactly:

```dart
class LabTest {
  final String testName, rawTestName;
  final double? value;
  final String? unit;
  final double? rangeLow, rangeHigh;
  final String? rangeRaw;
  final String? flagInSource;
  final String ocrConfidence;         // high | medium | low
  final Map<String, dynamic>? sourceBbox;  // {page, bbox}
}
```

`sourceBbox` gets populated from the value cell's geometry — this is the
traceability the viewer already renders, and today it is always `null` because
the geometry was discarded.

### WS4 — Restrict the SLM to summarisation (and rename it honestly)

- **Delete `normalizeJson`** from the `SlmRuntime` interface and both
  implementations (`slm_runtime.dart:25, 53, 133`). It is unused, and removing
  it makes "ask T5 to emit structure" unrepresentable rather than merely
  discouraged.
- **Rename `standardizeText` → `summarize`**, and `OnnxSlmRuntime` →
  `OnnxSummarizer`, `SlmRuntime` → `MedicalSummarizer`. Keep the old names as
  deprecated aliases only if a rename would churn tests unnecessarily; the
  interface method should be renamed outright.
- **Feed it structure, not raw OCR.** Add `renderLabText(LabDocument)` producing
  a compact, deterministic rendering, e.g.
  `Hemoglobin 11.2 g/dL (ref 13-17, marked L)`. Summarising the *structured*
  rows gives the model clean input instead of interleaved column soup, and cuts
  the noise that currently produces vague summaries. Fall back to raw OCR text
  when the document has no tests. The tokenizer already truncates to
  `maxInputTokens = 128` (`slm_runtime.dart:79`), so length is bounded.
- **Vocabulary sweep:** `README.md:134` ("T5 standardizer"), `mobile/README.md`
  ("standardizer"), `mobile/docs/APP_SPIKE.md:24-30`, and the `stage2_engine`
  value written into envelopes (`'app-on-device'` → keep, but the *document*
  should say the engine is rule-based). The envelope already carries
  `engine: 'deterministic-v1+t5-q8'`; change to
  `'rule-engine-v2+t5-summary'` once WS3 lands, and keep the old string
  parseable by the viewer.

### WS5 — Pipeline integration

`mobile/lib/model_manager.dart`:
- `_documentEnvelope` (lab_report branch) becomes:
  `recognizePages` → `buildStage1` → `buildLabDocument` → `validateLabReport` →
  `summarize(renderLabText(doc))`.
- The prescription branch keeps the deterministic prescription normalizer
  unchanged — the user's complaint is specific to lab reports, and
  `normalizePrescriptionText` has no table problem.
- Preserve the existing offline/sync contract via `_storeAndSync` untouched.
- Delete the now-unused `normalizeLabText` path from `normalize.dart` (keep
  `normalizePrescriptionText`), and keep `buildResultEnvelope` as the single
  envelope builder.

Provenance to add to the envelope (the viewer already tolerates unknown keys,
and `DetectionInfo` in `lib/api/models.dart` is the precedent):
```json
"structure": {
  "engine": "mlkit-geometry",
  "tables": 2, "tests": 18,
  "confidence": "high",          // derived from row-level confidences
  "pages_without_tables": []
}
```
This is how a reviewing doctor can tell a clean geometric extraction from a
degraded line-only reconstruction.

### WS6 — Parity and golden tests (build this first)

The verification story is what makes this plan safe:

1. **Cross-language parity harness.** `mobile/test/fixtures/lab/*.json` holds
   `stage1`-shaped inputs. A test runs the Dart `buildLabDocument` and
   `backend/lab_pipeline/slm_stage.py::_build_document` on the same fixture and
   asserts deep equality. The Python module is stdlib-only (lines 28–31) and
   `_build_document` takes a plain dict, so it can be invoked from a small
   script with no service, DB or model. Add
   `backend/scripts/run_stage2_fixture.py` (new, tiny) so the check is one
   command. This is the single highest-value test in the plan: it converts
   "looks right" into "byte-identical to the reference".
2. **Geometry fixtures.** Record real `RecognizedText` trees (blocks→lines→
   elements with boxes) from 4–6 representative reports — a clean digital PDF
   render, a phone photo of a printed CBC, a panel-per-section report, a
   rotated page, and one with a fused single-cell blob — and commit them as
   JSON. Then WS2's structure synthesis is testable without a device, and its
   output feeds directly into the parity harness.
3. **Unit tests** for each ported function against the backend's behaviour,
   covering the cases that currently break: `<200` / `>4`, `1,200`, a fused
   `Hemoglobin (Hb) 11.2 g/dL 13.0-17.0`, a source `H` flag, `S. Creatinine
   (Serum)`, a header row that slipped through, and a row with no numbers.
4. **Regression guard** that the emitted test objects contain exactly the 10
   required keys and never `abnormal`/`direction` (existing validator, reused).
5. **On-device integration test** extending
   `integration_test/pipeline_on_device_test.dart` to assert the real pipeline
   yields the same structure as the fixture-driven test for the same image.
6. **A dev-screen diff** in the existing Developer section of **Me** that runs
   the local engine and, when a backend URL is configured, posts the same file
   to `/api/v2/lab-reports/upload` and shows both structured results side by
   side. Fast way to evaluate on real documents.

## 5. Phasing

| Phase | Deliverable | Why this order |
|---|---|---|
| P0 | Fixtures + parity harness (WS6.1, WS6.2) | Everything after this is measurable; without it we are guessing at "better" |
| P1 | Geometry capture (WS1) | Nothing else is possible until boxes survive OCR |
| P2 | Structure synthesis (WS2) | The genuinely new algorithm; validated against fixtures |
| P3 | Rule engine port (WS3) | Proven by P0's parity harness |
| P4 | Pipeline integration + provenance (WS5) | Swaps the engine in behind the existing envelope contract |
| P5 | SLM restriction + rename (WS4) | Independent, can land any time after P3 |
| P6 | Real-report evaluation, threshold tuning | Needs device time and real documents |

P0–P3 are the substance. P5 is small but fixes the conceptual error the user
identified.

## 6. Verification

- `flutter analyze` clean; `flutter test` green, with the new fixture and parity
  suites included.
- `python backend/scripts/run_stage2_fixture.py <fixture>` output equals the
  Dart output for every fixture in `mobile/test/fixtures/lab/`.
- On-device: the same report processed (a) via the app's Capture path and
  (b) via the backend `/api/v2/lab-reports/upload` path produces equivalent
  `panels[].tests[]`. Any divergence is a port bug.
- Existing guarantees still hold: exactly 10 keys per test, no
  `abnormal`/`direction` on-device, offline rows still `pending`, and the
  `DetectionInfo`/`page_count` provenance still parses.

## 7. Risks and honest limitations

1. **Table detection from OCR boxes is heuristic, and that is the main risk.**
   Two-column layouts, wrapped cell values and merged cells will need iteration
   against real reports. Mitigation: the parity harness plus the degraded
   line-only path, which always produces *something* at `low` confidence rather
   than dropping rows. Rows are never silently discarded — that is the backend's
   rule (`slm_stage.py:18`) and we keep it.
2. **Coordinate spaces differ from the backend.** OpenDataLoader reports PDF
   points; ML Kit reports bitmap pixels of the rendered image. All geometry must
   be normalised to page-relative units, and thresholds expressed as fractions
   of page size. Do not port any absolute-pixel constant.
3. **OCR text errors dominate.** For digital PDFs we rasterise then OCR, so a
   perfect text layer is thrown away and re-guessed. `pdfx` exposes no text
   extraction. A future improvement is a PDF text-layer path, but it is out of
   scope here and should not block this work.
4. **`confidence` may be null.** Some devices/models return null for
   `TextLine.confidence`. Treat null as *unknown* and fall back to the
   structural confidence ladder from `_parse_table_row`, rather than collapsing
   everything to `low`.
5. **Rotated or skewed scans** degrade column clustering. `TextLine.angle` is
   available; use it to warn and skip table detection for that page rather than
   producing confidently wrong columns.
6. **`TEST_NAME_MAP` drift.** Porting the map into Dart creates a second copy.
   The parity harness must also assert the two maps are identical, or the drift
   will be silent.
7. **This does not touch Stage 3.** Flags remain server-side and the rule table
   there is still marked UNREVIEWED PLACEHOLDERS. Porting Stage 2 must not pull
   any pattern rules on-device.
8. **Effort is real.** P0–P4 is a substantial change to
   `model_manager.dart`, `cnn_ocr.dart` and `normalize.dart`, with new
   `lib/lab/` code and fixtures. The compensating factor is that P3 is a port of
   a known-correct algorithm with an executable oracle, not net-new logic.

## 8. Recommended first step

Build P0 before touching the pipeline: commit two or three `stage1` fixtures and
the parity script, and confirm the Python reference's output. That converts an
open-ended "make lab reports better" into a measurable target, and it will
immediately show how far the current `_valueUnitRe` extractor really is from the
reference — which is the number that justifies (or revises) the rest of this
plan.
