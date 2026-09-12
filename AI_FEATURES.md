# AI feature backlog — IntelliMed mobile

Status: §2.1 (capture quality gate + document scanner) and §2.2 (longitudinal
trends) are implemented in the mobile app. Everything else is proposed and not
started.
Scope: `mobile/` (Flutter, patient-facing, Android-first)
Companion doc: [LAB_REPORT_ENGINE_PLAN.md](LAB_REPORT_ENGINE_PLAN.md) — the
extraction work this backlog builds on.

## How to use this document

Everything below is a suggestion, ordered by value-for-risk. Each entry states
whether it actually needs a model, because several of the highest-value items
are deterministic and are better left that way. Where a claim rests on something
measured in this repo, the number is given so it can be re-checked.

## 1. Framing: not everything here is "AI"

| # | Feature | Needs a model? | Tier |
|---|---|---|---|
| 1 | Capture quality gate + document scanner | No — classical CV | 1 |
| 2 | Longitudinal trends | No — arithmetic on stored rows | 1 |
| 3 | Grounded plain-language explanation + multilingual | Yes — small instruct | 2 |
| 4 | Ask your own records (grounded Q&A) | Yes — retrieval + small instruct | 2 |
| 5 | Medication reminders from prescriptions | Partly — extraction only | 2 |
| 6 | Handwriting OCR | Yes — larger, server-side | 3 |
| 7 | Redact before raw upload | Partly — OCR/NER + CV | 3 |

The model earns its place on **language** tasks (explain, translate, ask). It
should not be given **judgement** tasks. That split is the single most useful
idea in this document.

## 2. Tier 1 — raise the ceiling on everything else

### 2.1 Capture quality gate + document scanner

> **Status: implemented.** `google_mlkit_document_scanner ^0.6.1` (Android-only;
> other platforms fall back to `image_picker`). Gate in `lib/capture_quality.dart`
> (blur/glare/darkness on the corrected image, before inference) wired into
> `lib/screens/capture_screen.dart`, with an inline retake prompt and a
> "use anyway" escape. Small text is checked after OCR (its height is only
> knowable from ML Kit boxes) and surfaced as an envelope warning.

**Problem.** A skewed, blurry or glare-hit phone photo goes straight into OCR,
and input quality is the dominant cause of bad extraction. No model upgrade
fixes a skewed page — which is why this outranks every model idea here.

**Current state (before this change).** The app depended on
`google_mlkit_text_recognition: 0.17.1` only; ML Kit's edge-detection /
perspective-correction / crop / dewarp module was unused.

**What to build.**
- Add `google_mlkit_document_scanner` for capture: edge detection, corner drag,
  perspective correction, auto-rotate, dewarp.
- A pre-inference quality check on the corrected image:
  - blur = variance-of-Laplacian below a threshold
  - glare = large clipped-white area fraction
  - too-dark / too-small-text (cap height below N px)
- Show "retake this" **before** running inference, with the specific reason
  ("looks blurred", "glare on the left"). Cheaper and kinder than producing a
  bad result from a bad photo.
- Perspective correction also fixes a real extraction bug: ML Kit's line
  bounding boxes are axis-aligned, so a skewed page produces overlapping
  columns. Dewarping before OCR avoids that at the source.

**Notes.** Fully on-device, deterministic, no model. Already have the `image`
package for pixel access. The scanner UI is a full-screen flow that returns
images, so it replaces the camera path rather than sitting beside it.

### 2.2 Longitudinal trends

> **Status: implemented.** `lib/trends.dart` (unit-consistent series keyed by
> canonical `test_name` + unit), `lib/widgets/trend_sparkline.dart` (band shaded
> from the latest printed range), and `lib/screens/trends_screen.dart` /
> `trend_detail_screen.dart`, reached from Home and Reports.
>
> Implementation note: series are derived from the stored envelopes via
> `ResultStore.labReportRows()` rather than a denormalised table — no migration,
> and a delete/re-run cannot leave the series stale. Local rows and server
> reports are merged, skipping server copies already represented locally by
> `server_id`, so a synced capture is not counted twice.

**Problem.** Each report is currently shown in isolation. A single haemoglobin
of 11.2 is nearly meaningless; the same value falling from 14 over three reports
is the thing that matters.

**Why now.** This is the payoff for the structured-extraction work in
`LAB_REPORT_ENGINE_PLAN.md`. Once tests carry canonical names (`TEST_NAME_MAP`)
and timestamps, this is arithmetic over rows already stored — no model, and
essentially hallucination-proof.

**What to build.**
- Extend the local store (or a new table) with a per-test series keyed by
  canonical `test_name` + `unit`.
- A Trends view per analyte: sparkline of value over time with the printed
  reference band shaded.
- Guard against unit changes over time — a series must be unit-consistent, and
  a unit change should split the series rather than silently compare mg/dL to
  mmol/L. This is the one real correctness trap.
- Copy rule: "your values over time". Never "improving"/"worsening" — that is
  an interpretation, and `mobile/lib/copy.dart` forbids diagnostic framing.

**Dependencies.** Needs the canonical test names from the rule-engine port.
Useless before P3 of the extraction plan lands.

## 3. Tier 2 — where the model fits

### 3.1 Grounded plain-language explanation + multilingual

**Idea.** Turn a structured result into one or two plain sentences for the
patient, in their own language.

**Why the model fits.** Explaining and paraphrasing is what a summarizer /
instruct model is actually good at, unlike schema emission. This is the role
where the model is least likely to cause harm: a clumsy sentence is visible and
corrupts nothing, because the facts live separately in the structured rows.

**How to keep it safe.**
- Do **not** free-form generate. Ground each explanation in a curated glossary
  of what each analyte measures, plus the patient's own value and printed range.
- Prompt constrained: one or two sentences, no diagnosis, no advice, no
  prognosis. `copy.dart`'s non-diagnostic rule applies to model output too.
- Always show the underlying rows next to the sentence so the sentence is
  never the only evidence.
- Store as its own field (`patient_explanation`) derived from the structure —
  never let it become the source of truth.

**Multilingual.** Given the project context, Hindi plus at least one regional
language is a large accessibility win and well-suited to a small model. This is
the most valuable single use of a language model in this app.

### 3.2 Ask your own records

**Idea.** "What was my cholesterol last time?" / "Which reports mention
thyroid?" — answered from the patient's own stored data.

**Why it is safer than chatbot-medicine.** Answers are retrieved from the
patient's own rows and **cite the source row**. Grounding plus citation is what
makes this defensible; a wrong answer is traceable and obviously wrong.

**Rules.**
- Retrieval first, generation second. If retrieval returns nothing, say so —
  never generate a plausible value.
- Every answer cites the report/row it came from, with a tap-through.
- Refuse clinical-advice-shaped questions and route to the doctor. Refusals
  should be explicit, not a degraded attempt.
- Never answer from general medical knowledge; only from the patient's records
  plus the vetted glossary.

**Scope note.** This is the most "AI feature"-looking item here and also the
one that most needs guardrails. It is a better use of effort than open-ended
chat, which should stay out of scope (see §5).

### 3.3 Medication reminders from prescriptions

**Idea.** Dosage + frequency → a medication schedule with notifications.

**Implementation.** The model (or the existing deterministic extractor) only
needs to yield `{medication, dosage, frequency}` — the prescription normalizer
already produces exactly this shape. Scheduling and notifications are plain
code keyed off the prescription's own printed instructions.

**Honest framing.** This does not advise. It repeats what the prescription
already says. That distinction is what keeps it out of clinical-decision-support
territory, so keep the copy literal ("as written on your prescription") and
never suggest a dose.

## 4. Tier 3 — real functional gaps

### 4.1 Handwriting OCR

**The gap.** Both READMEs scope this out explicitly ("Printed documents only —
handwriting OCR is future work and is not attempted here"). But prescriptions
are the most commonly handwritten medical document, so this is a genuine
functional hole, not a nice-to-have.

**Approach.** Server-side is the pragmatic route: a TrOCR-class handwriting
model or a cloud OCR endpoint, behind the existing Docs upload path. On-device
handwriting is not realistic at 60M parameters.

**Costs to weigh.** Network dependency (breaks the offline-first capture
promise), PHI leaving the device (see §4.2), per-page cost if cloud, and a
materially lower accuracy ceiling than print. Should degrade gracefully — if
handwriting is detected and no path is available, say so rather than returning
confident nonsense.

**Minimum useful version.** Detect that a page *is* handwritten and tell the
user, so they know why a printed-only extraction came back poor. That alone
removes a confusing failure mode.

### 4.2 Redact before raw upload

**The gap.** The Docs path uploads the raw file to Supabase (flagged earlier as
a deliberate deviation from the app's original "never raw documents" design).
Raw PHI leaves the phone.

**Idea.** An on-device redaction pass before upload: detect name/ID/address
burned into the document and cover them, so the server sees the clinical
content without the identifiers.

**Feasible pieces.**
- ML Kit text recognition already gives word boxes, so locating a printed
  "Patient Name: ..." line is straightforward once the geometry is preserved
  (which `LAB_REPORT_ENGINE_PLAN.md` WS1 delivers).
- ML Kit face detection exists for photographic identifiers.
- Redaction itself is drawing boxes — no model needed.

**Caveats.** This is not a compliance guarantee. A redaction pass that misses an
identifier creates false confidence, so it must be presented as best-effort and
paired with keeping uploads strictly user-initiated. Do not claim HIPAA
compliance on the strength of it.

## 5. Explicitly out of scope — and why

| Idea | Why not |
|---|---|
| **Drug–drug interaction checking** | Clinical decision support. Regulated, high-harm on error, needs a licensed interaction database. The most tempting wrong idea on this list. |
| **Diagnosis or diagnostic probabilities shown to the patient** | Breaks `copy.dart`'s non-diagnostic framing and crosses a regulatory line. The X-ray classifier output is already framed as "structured context for review" — keep it that way. |
| **Urgency / triage scoring** | "How urgent" is a clinical judgement. Ordering results by "has flags for review" is acceptable precisely because the rule engine already produced those flags; inventing an urgency number is not. |
| **Free-form medical chat** | Ungrounded and unverifiable. The fastest route to being confidently wrong. If a conversational surface is wanted, build §3.2 (retrieval + citation) instead. |
| **Auto-prescribing or dose suggestions** | Same class as interaction checking. |
| **Doctor-facing auto-notes** | Legitimate and valuable, but it belongs on the backend/dashboard, not in a patient-only app. Out of scope for this doc. |

## 6. Model selection notes

Recorded here because every Tier-2 item depends on this decision.

### Current state (measured)

- On-device model: `Falconsai/medical_summarization` (T5-small, 60M), quantized
  ONNX. A **summarizer**, not an instructor.
- Runtime limits: `maxInputTokens = 128`, **`maxNewTokens = 60`**
  (`mobile/lib/slm_runtime.dart:79-80`). Sixty output tokens is roughly one
  sentence — this is why asking T5 for structured JSON was never viable.
- Runtimes already declared in `pubspec.yaml`:
  `flutter_onnxruntime ^1.8.5`, `llama_cpp_dart ^0.2.2`, `tflite_flutter ^0.12.1`.
  **The llama.cpp slot is already a dependency**, and `LlamaCppRuntime` exists
  in `slm_runtime.dart`. The README calling it "future-only" is stale.

### Bundle size is the real constraint

| Asset | Size |
|---|---|
| `pneumonia_resnet50.onnx` | 89.8 MB |
| `t5_decoder_q8.onnx` | 55.8 MB |
| `t5_encoder_q8.onnx` | 33.9 MB |
| `t5_tokenizer.json` | 2.3 MB |
| **Models subtotal** | **~182 MB** |
| `app-release.apk` | 296.8 MB |

Models are already ~61% of the release APK. A 1.5B Q4 GGUF adds roughly 1 GB,
producing a ~1.3 GB app. **That cannot be bundled.** Therefore:

**Decision required: download-on-demand.** Fetch the model to app storage on
first use, with a size-aware prompt, resumable download and integrity check.
This is what makes anything above ~0.5B viable at all.

**Critical corollary:** the app must remain fully functional with **no model
present** — rules for structure, template-based phrasing for summaries — and
treat the downloaded model purely as an enhancement. Otherwise the offline-first
promise breaks for anyone without signal or storage.

### Task → model type

- **Extraction / repair** → don't use a generative model. Token classification
  (BERT-class NER, ~110M, ONNX) labels tokens that already exist, so it
  *cannot* invent a value. Smaller, faster, strictly more reliable here.
- **Explanation / summarisation / translation** → small *instruct* model.

### Candidate instruct models (Q4)

| Model | Approx. size | Notes |
|---|---|---|
| SmolLM2-360M-Instruct | ~250 MB | Built for on-device, Apache-2.0 |
| Qwen2.5-0.5B-Instruct | ~400 MB | Strongest small instruct family; good at constrained output |
| Llama-3.2-1B-Instruct | ~800 MB | Strong; Llama licence |
| Qwen2.5-1.5B-Instruct | ~1 GB | Noticeably better fluency — the pick if size allows |
| Gemma-2-2B-it | ~1.6 GB | Better quality, heavier |

### Technique beats parameter count

For any structured output, use **grammar-constrained decoding (GBNF in
llama.cpp)**. It makes invalid JSON *unrepresentable*, which buys more
reliability than going 0.5B → 3B. `llama_cpp_dart` is already a dependency, so
this is the cheapest high-leverage change available.

### Data beats size

A 60M model fine-tuned on the narrow task will beat a zero-shot 3B model on the
same task and still fit on a phone. Scaffolding already exists:
`backend/scripts/prepare_slm_finetune_dataset.py` emits training pairs using the
`LAB_REPORT_SYSTEM_PROMPT`.

### Latency reality

A 1.5B model on CPU without GPU offload runs at roughly 5–15 tokens/sec on a
mid-range phone. Acceptable for a summary generated once after a capture; not
acceptable on any interactive path. Needs a progress UI and thermal awareness.

## 7. Constraints every item must respect

1. **Non-diagnostic framing.** `mobile/lib/copy.dart` forbids "diagnos*"
   wording in UI copy, variable names and comments. This applies to model output
   too, not just hand-written strings.
2. **Patient-only app.** `/api/v2/lab-reports/upload-structured` rejects
   non-patient roles, and the app hardcodes `role: patient`. Doctor-facing
   features belong on the backend.
3. **Never invent flags on-device.** Normalization output must never contain
   `abnormal`/`direction`; Stage 3 stays server-side and the server rejects them.
4. **Offline-first.** The app must work with no network and no downloaded model.
5. **Uploads are explicit.** Anything sending PHI off-device stays
   user-initiated, never automatic.
6. **Provenance.** Model-derived fields must be marked as such
   (`extraction_source: rule | model`) alongside `ocr_confidence`, so a reviewer
   can tell an extracted value from a generated one.

## 8. Suggested sequencing and dependencies

| Order | Item | Depends on |
|---|---|---|
| 1 | Capture quality gate + scanner (§2.1) | Nothing — independent, and improves everything downstream |
| 2 | Extraction rule engine | `LAB_REPORT_ENGINE_PLAN.md` P0–P4 |
| 3 | Longitudinal trends (§2.2) | Canonical test names from #2 |
| 4 | Model selection + eval gate (§6) | A decision on download-on-demand |
| 5 | Grounded explanation + multilingual (§3.1) | #4 |
| 6 | Medication reminders (§3.3) | Prescription extraction (already exists) |
| 7 | Ask your own records (§3.2) | #2 and #4 |
| 8 | Handwriting OCR (§4.1) | Backend work; independent |
| 9 | Redaction before upload (§4.2) | OCR geometry (`LAB_REPORT_ENGINE_PLAN.md` WS1) |

Items 1 and 6 are shippable now with no model and no dependency on the
extraction work, which makes them the natural first picks.

## 9. Open decisions

1. **Download-on-demand, yes or no?** Gates everything above ~0.5B. Without it,
   the ceiling is a bundled small model.
2. **Which languages** for §3.1? Determines the eval set.
3. **Is the model worth keeping at all** if rules plus templates cover the
   summary? A defensible answer is to cut it entirely and save ~90 MB and a
   download step.
4. **Does §4.1 (handwriting) accept a network dependency**, given the app is
   otherwise offline-first?
5. **Is §4.2 redaction worth the false-confidence risk**, or is "uploads are
   explicit and the user sees what is sent" sufficient?
