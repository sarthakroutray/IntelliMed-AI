import asyncio
import math
import os
import re
import traceback
from pathlib import Path
from functools import lru_cache
from threading import Lock

# Try importing AI libraries, handle missing dependencies gracefully
try:
    import easyocr
    from PIL import Image, ImageFilter, ImageEnhance, ImageOps
    HAS_OCR = True
except ImportError:
    HAS_OCR = False
    print("⚠ OCR dependencies (easyocr, Pillow) not found. pip install easyocr Pillow")

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    print("⚠ OpenCV (cv2) not found. Advanced image preprocessing disabled.")

try:
    import spacy
    HAS_NLP = True
except ImportError:
    HAS_NLP = False
    print("⚠ NLP dependencies (spacy) not found.")

try:
    import torch
    import torch.nn as nn
    from torch.amp import autocast
    import torchvision.transforms as transforms
    from torchvision import models
    from torchvision.models import ResNet50_Weights
    from PIL import Image
    import numpy as np
    HAS_CV = True
except ImportError:
    HAS_CV = False
    np = None
    print("⚠ CV dependencies (torch, torchvision) not found.")


# --- Concurrency controls ---
MAX_CONCURRENT_HEAVY = int(os.getenv('MAX_CONCURRENT_HEAVY', '2'))
heavy_semaphore = asyncio.Semaphore(MAX_CONCURRENT_HEAVY)

# Locks for model loading to avoid races
_nlp_lock = Lock()
_cv_lock = Lock()
_ocr_lock = Lock()

# Global EasyOCR reader (loaded once, reused)
_ocr_reader = None

# --- PDF Support ---
try:
    import fitz  # PyMuPDF
    HAS_PDF = True
except ImportError:
    HAS_PDF = False
    print("⚠ PyMuPDF (fitz) not found. PDF support disabled. pip install PyMuPDF")


def _pdf_to_images(file_path: str) -> list:
    """
    Convert a PDF to a list of PIL Image objects (one per page).
    Uses PyMuPDF which is pure Python / pip-installable.
    """
    if not HAS_PDF:
        raise RuntimeError("PyMuPDF not installed. Cannot process PDFs.")

    images = []
    doc = fitz.open(file_path)
    for page_num in range(len(doc)):
        page = doc[page_num]
        # Render at 2x for better OCR quality
        pix = page.get_pixmap(dpi=200)
        img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
        images.append(img)
    doc.close()
    return images


def _is_pdf(file_path: str) -> bool:
    return file_path.lower().endswith('.pdf')


# =============================================================================
# MEDICAL KNOWLEDGE BASE - Used for prescription NLP
# =============================================================================

# Common medications (brand and generic names) for entity recognition
COMMON_MEDICATIONS = {
    # Antibiotics
    "amoxicillin", "azithromycin", "ciprofloxacin", "doxycycline", "metronidazole",
    "cephalexin", "clindamycin", "penicillin", "augmentin", "levofloxacin",
    "trimethoprim", "sulfamethoxazole", "bactrim", "erythromycin", "clarithromycin",
    "nitrofurantoin", "cefdinir", "ceftriaxone", "vancomycin", "linezolid",
    # Pain / Anti-inflammatory
    "ibuprofen", "acetaminophen", "naproxen", "aspirin", "diclofenac",
    "paracetamol", "tramadol", "morphine", "codeine", "oxycodone",
    "hydrocodone", "gabapentin", "pregabalin", "celecoxib", "meloxicam",
    "tylenol", "advil", "motrin", "aleve",
    # Cardiac / BP
    "lisinopril", "amlodipine", "metoprolol", "atenolol", "losartan",
    "valsartan", "ramipril", "enalapril", "diltiazem", "verapamil",
    "hydrochlorothiazide", "furosemide", "spironolactone", "carvedilol",
    "propranolol", "nifedipine", "digoxin", "warfarin", "clopidogrel",
    "apixaban", "rivaroxaban", "heparin",
    # Diabetes
    "metformin", "glipizide", "glyburide", "insulin", "sitagliptin",
    "pioglitazone", "empagliflozin", "dapagliflozin", "liraglutide", "semaglutide",
    # Statins / Cholesterol
    "atorvastatin", "rosuvastatin", "simvastatin", "pravastatin", "lovastatin",
    "ezetimibe", "fenofibrate", "lipitor", "crestor",
    # GI
    "omeprazole", "pantoprazole", "esomeprazole", "ranitidine", "famotidine",
    "ondansetron", "metoclopramide", "loperamide", "bismuth",
    # Respiratory
    "albuterol", "fluticasone", "montelukast", "prednisone", "prednisolone",
    "dexamethasone", "budesonide", "ipratropium", "tiotropium", "theophylline",
    "cetirizine", "loratadine", "fexofenadine", "diphenhydramine", "promethazine",
    # Psych / Neuro
    "sertraline", "fluoxetine", "escitalopram", "citalopram", "paroxetine",
    "venlafaxine", "duloxetine", "bupropion", "mirtazapine", "trazodone",
    "amitriptyline", "alprazolam", "lorazepam", "diazepam", "clonazepam",
    "zolpidem", "quetiapine", "olanzapine", "risperidone", "aripiprazole",
    "lithium", "valproate", "carbamazepine", "lamotrigine", "topiramate",
    "levetiracetam", "phenytoin",
    # Thyroid
    "levothyroxine", "synthroid", "methimazole",
    # Other common
    "hydroxychloroquine", "colchicine", "allopurinol", "cyclobenzaprine",
    "tizanidine", "baclofen", "sildenafil", "tamsulosin", "finasteride",
    "montelukast", "latanoprost", "timolol",
}

# Dosage forms
DOSAGE_FORMS = {
    "tablet", "tablets", "tab", "tabs", "capsule", "capsules", "cap", "caps",
    "pill", "pills", "mg", "ml", "mcg", "g", "gram", "grams",
    "drops", "drop", "syrup", "suspension", "solution", "injection", "inj",
    "cream", "ointment", "gel", "lotion", "patch", "inhaler", "spray",
    "suppository", "lozenge", "powder",
}

# Frequency terms
FREQUENCY_TERMS = {
    "once daily", "twice daily", "three times daily", "four times daily",
    "once a day", "twice a day", "three times a day", "four times a day",
    "every day", "every morning", "every night", "every evening",
    "every 4 hours", "every 6 hours", "every 8 hours", "every 12 hours",
    "before meals", "after meals", "with meals", "with food",
    "at bedtime", "as needed", "as required", "prn",
    "bid", "tid", "qid", "qd", "qhs", "qam", "qpm",
    "b.i.d", "t.i.d", "q.i.d", "q.d", "q.h.s",
    "od", "bd", "tds", "qds", "sos", "stat",
    "daily", "weekly", "monthly",
}

# Route of administration
ROUTE_TERMS = {
    "oral", "orally", "by mouth", "po", "p.o",
    "topical", "topically", "apply to", "apply on",
    "sublingual", "under tongue",
    "intramuscular", "im", "i.m",
    "intravenous", "iv", "i.v",
    "subcutaneous", "sc", "s.c", "subq",
    "inhale", "inhalation", "nebulize",
    "rectal", "rectally",
    "ophthalmic", "in each eye", "in affected eye",
    "otic", "in each ear", "in affected ear",
    "nasal", "nasally", "intranasal",
}

# Duration terms
DURATION_TERMS = {
    "for 3 days", "for 5 days", "for 7 days", "for 10 days", "for 14 days",
    "for 1 week", "for 2 weeks", "for 3 weeks", "for 4 weeks",
    "for 1 month", "for 2 months", "for 3 months", "for 6 months",
    "until finished", "until symptoms resolve", "ongoing", "indefinitely",
    "continue", "long-term",
}

# Pre-compile regex patterns for medication matching (avoids recompiling per call)
_MEDICATION_PATTERNS = {med: re.compile(r'\b' + re.escape(med) + r'\b') for med in COMMON_MEDICATIONS}
_FREQUENCY_PATTERNS = {term: re.compile(r'\b' + re.escape(term) + r'\b') for term in FREQUENCY_TERMS}
_ROUTE_PATTERNS = {term: re.compile(r'\b' + re.escape(term) + r'\b') for term in ROUTE_TERMS}
_DOSAGE_PATTERN = re.compile(r'\b(\d+(?:\.\d+)?)\s*(mg|ml|mcg|g|gram|grams|iu|units?|cc|%)\b')
_TABLET_PATTERN = re.compile(r'\b(\d+)\s*(tablet|tablets|tab|tabs|capsule|capsules|cap|caps|pill|pills|drop|drops|puff|puffs)\b')
_DURATION_PATTERN = re.compile(r'\b(?:for\s+)?(\d+)\s*(day|days|week|weeks|month|months)\b')


# --- OCR Service (EasyOCR - no external binaries required) ---

def _get_ocr_reader():
    """Lazy-load and cache the EasyOCR reader (thread-safe)."""
    global _ocr_reader
    with _ocr_lock:
        if _ocr_reader is None:
            gpu = torch.cuda.is_available() if HAS_CV else False
            print(f"Loading EasyOCR reader (GPU={gpu})... first load downloads model (~100MB)")
            _ocr_reader = easyocr.Reader(
                ['en'],
                gpu=gpu,
                model_storage_directory=str(Path(__file__).parent / 'models' / 'easyocr'),
                verbose=False,
            )
            print("✓ EasyOCR reader loaded")
    return _ocr_reader


async def ocr_service(file_path: str) -> str:
    """
    Extracts text from medical documents / handwritten prescriptions.
    Supports images (jpg, png, etc.) and PDFs.
    Uses EasyOCR (pure Python, no Tesseract needed) with image preprocessing.
    Returns empty string if no text found (not an error - some images have no text).
    """
    print(f"Starting OCR for {file_path}")

    if HAS_OCR:
        try:
            async with heavy_semaphore:
                if _is_pdf(file_path):
                    text = await asyncio.to_thread(_run_pdf_ocr, file_path)
                else:
                    text = await asyncio.to_thread(_run_enhanced_ocr, file_path)
            
            if text and text.strip():
                print(f"✓ OCR successful for {file_path} ({len(text)} chars)")
                return text
            else:
                print(f"✓ OCR completed but no text found (image may contain no text)")
                return ""  # Empty is OK - X-rays, diagrams, etc. have no text
        except Exception as e:
            print(f"⚠ OCR failed with error: {e}")
            traceback.print_exc()

    # EasyOCR is required - no fallback
    raise RuntimeError(
        "OCR service is not available. Please ensure EasyOCR is installed correctly. "
        "Run: pip install easyocr"
    )


def _run_enhanced_ocr(file_path: str) -> str:
    """
    Multi-pass OCR using EasyOCR with different preprocessing strategies.
    Picks the result with the most extracted text.
    """
    reader = _get_ocr_reader()
    results = []

    # --- Pass 1: Direct EasyOCR on original image (works well for clean docs) ---
    try:
        detections = reader.readtext(file_path, detail=1, paragraph=True)
        text = _detections_to_text(detections)
        print(f"  Pass original: {len(detections)} detections, {len(text)} chars")
        if text and len(text.strip()) > 2:
            results.append((len(text.strip()), text.strip(), "original"))
            # Early exit: if original pass gets substantial text, skip expensive preprocessing
            if len(text.strip()) > 100:
                print(f"  ✓ Early exit: original pass got {len(text.strip())} chars")
                return _clean_ocr_text(text.strip())
    except Exception as e:
        print(f"  Pass original failed: {e}")

    # --- Pass 2: OpenCV preprocessed variants ---
    if HAS_CV2:
        try:
            variants = _preprocess_for_handwriting_cv2(file_path)
            for label, img_array in variants:
                try:
                    detections = reader.readtext(img_array, detail=1, paragraph=True)
                    text = _detections_to_text(detections)
                    if text and len(text.strip()) > 2:  # More lenient
                        results.append((len(text.strip()), text.strip(), label))
                except Exception as e:
                    print(f"  Pass {label} failed: {e}")
        except Exception as e:
            print(f"  CV2 preprocessing failed: {e}")

    # --- Pass 3: PIL preprocessed variants ---
    try:
        pil_variants = _preprocess_for_handwriting_pil(file_path)
        for label, pil_img in pil_variants:
            try:
                img_array = np.array(pil_img)
                detections = reader.readtext(img_array, detail=1, paragraph=True)
                text = _detections_to_text(detections)
                if text and len(text.strip()) > 2:  # More lenient
                    results.append((len(text.strip()), text.strip(), label))
            except Exception as e:
                print(f"  Pass {label} failed: {e}")
    except Exception as e:
        print(f"  PIL preprocessing failed: {e}")

    if not results:
        print("  ⚠ No text extracted from any OCR pass (image may contain no text)")
        return ""  # Return empty string instead of raising error

    # Pick the result with most content
    results.sort(key=lambda x: x[0], reverse=True)
    best_text = results[0][1]
    best_method = results[0][2]
    print(f"  ✓ Best OCR result from '{best_method}' ({len(best_text)} chars)")

    cleaned = _clean_ocr_text(best_text)
    return cleaned


def _run_pdf_ocr(file_path: str) -> str:
    """
    Extract text from a PDF document.
    First tries native text extraction (for typed PDFs), then falls back to OCR.
    """
    if not HAS_PDF:
        raise RuntimeError("PyMuPDF not installed")

    # --- Phase 1: Try native text extraction (fast, for typed/digital PDFs) ---
    doc = fitz.open(file_path)
    native_text_parts = []
    for page in doc:
        text = page.get_text()
        if text and text.strip():
            native_text_parts.append(text.strip())
    doc.close()

    native_text = '\n'.join(native_text_parts)
    if native_text and len(native_text.strip()) > 20:
        print(f"  PDF native text extraction: {len(native_text)} chars")
        return _clean_ocr_text(native_text)

    # --- Phase 2: OCR each page as image (for scanned/handwritten PDFs) ---
    print("  PDF has no native text, running OCR on rendered pages...")
    reader = _get_ocr_reader()
    images = _pdf_to_images(file_path)
    all_text = []

    for i, img in enumerate(images):
        img_array = np.array(img)
        try:
            detections = reader.readtext(img_array, detail=1, paragraph=True)
            page_text = _detections_to_text(detections)
            print(f"  Page {i+1}: {len(detections)} detections, {len(page_text)} chars")
            if page_text and len(page_text.strip()) > 2:  # More lenient
                all_text.append(page_text.strip())
                print(f"    ✓ Extracted {len(page_text)} chars from page {i+1}")
        except Exception as e:
            print(f"  Page {i+1} OCR failed: {e}")

    if not all_text:
        print("  ⚠ PDF OCR extracted no text (may be image-only or low quality)")
        return ""  # Return empty instead of raising

    combined = '\n\n'.join(all_text)
    return _clean_ocr_text(combined)


def _detections_to_text(detections: list) -> str:
    """Convert EasyOCR detection results to plain text."""
    lines = []
    for det in detections:
        if isinstance(det, tuple) and len(det) >= 2:
            # detail=1 returns (bbox, text, confidence)
            text = det[1] if len(det) >= 2 else str(det)
            lines.append(str(text))
        elif isinstance(det, str):
            lines.append(det)
    return '\n'.join(lines)


def _preprocess_for_handwriting_cv2(file_path: str) -> list:
    """
    OpenCV-based preprocessing pipeline for handwritten prescriptions.
    Returns multiple preprocessed variants as (label, numpy_array) tuples.
    """
    img = cv2.imread(file_path)
    if img is None:
        raise ValueError(f"Could not read image: {file_path}")

    variants = []

    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # 1. Upscale small images (handwriting needs higher resolution)
    h, w = gray.shape
    if max(h, w) < 1500:
        scale = 2.0
        gray_upscaled = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
    else:
        gray_upscaled = gray.copy()

    # 2. Deskew - correct rotation from scanning
    try:
        deskewed = _deskew_image(gray_upscaled)
    except Exception:
        deskewed = gray_upscaled

    # 3. Variant: Adaptive threshold (best for uneven lighting / paper)
    adaptive = cv2.adaptiveThreshold(
        deskewed, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 21, 10
    )
    variants.append(("cv2_adaptive", adaptive))

    # 4. Variant: OTSU threshold after bilateral filter (noise reduction + edge preservation)
    bilateral = cv2.bilateralFilter(deskewed, 9, 75, 75)
    _, otsu = cv2.threshold(bilateral, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    variants.append(("cv2_otsu_bilateral", otsu))

    # 5. Variant: Morphological cleaning (close small gaps in handwriting strokes)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    morph = cv2.morphologyEx(adaptive, cv2.MORPH_CLOSE, kernel)
    # Dilate slightly to thicken thin pen strokes
    dilate_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    morph = cv2.dilate(morph, dilate_kernel, iterations=1)
    variants.append(("cv2_morph", morph))

    # 6. Variant: CLAHE (contrast limited adaptive histogram equalization)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    clahe_img = clahe.apply(deskewed)
    _, clahe_thresh = cv2.threshold(clahe_img, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    variants.append(("cv2_clahe", clahe_thresh))

    # 7. Variant: Heavy denoise for very noisy documents
    denoised = cv2.fastNlMeansDenoising(deskewed, None, h=20, templateWindowSize=7, searchWindowSize=21)
    _, denoised_thresh = cv2.threshold(denoised, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    variants.append(("cv2_denoised", denoised_thresh))

    # 8. Variant: Inverted (some prescriptions have dark background)
    inverted = cv2.bitwise_not(adaptive)
    variants.append(("cv2_inverted", inverted))

    return variants


def _deskew_image(gray_img):
    """Deskew a grayscale image using minimum area rectangle on contours."""
    # Find edges
    edges = cv2.Canny(gray_img, 50, 150, apertureSize=3)
    # Find lines using HoughLinesP
    lines = cv2.HoughLinesP(edges, 1, 3.14159 / 180, 100, minLineLength=100, maxLineGap=10)

    if lines is None or len(lines) < 3:
        return gray_img

    # Calculate median angle
    angles = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
        if abs(angle) < 30:  # Only consider near-horizontal lines
            angles.append(angle)

    if not angles:
        return gray_img

    median_angle = sorted(angles)[len(angles) // 2]

    if abs(median_angle) < 0.5:  # Already straight enough
        return gray_img

    # Rotate to correct skew
    h, w = gray_img.shape
    center = (w // 2, h // 2)
    rotation_matrix = cv2.getRotationMatrix2D(center, median_angle, 1.0)
    rotated = cv2.warpAffine(gray_img, rotation_matrix, (w, h),
                              flags=cv2.INTER_CUBIC,
                              borderMode=cv2.BORDER_REPLICATE)
    return rotated


def _preprocess_for_handwriting_pil(file_path: str) -> list:
    """
    PIL-based preprocessing for handwritten prescriptions.
    Returns multiple variants as (label, PIL_Image) tuples.
    """
    img = Image.open(file_path).convert('L')  # Grayscale
    variants = []

    # Upscale small images
    w, h = img.size
    if max(w, h) < 1500:
        img = img.resize((w * 2, h * 2), Image.LANCZOS)

    # 1. High contrast + sharpen
    enhancer = ImageEnhance.Contrast(img)
    high_contrast = enhancer.enhance(2.5)
    sharpened = high_contrast.filter(ImageFilter.SHARPEN)
    sharpened = sharpened.filter(ImageFilter.SHARPEN)  # Double sharpen
    variants.append(("pil_contrast_sharp", sharpened))

    # 2. Binarize with threshold
    threshold = 140
    binary = img.point(lambda p: 255 if p > threshold else 0, 'L')
    variants.append(("pil_binary_140", binary))

    # 3. Auto-level (stretch histogram)
    autoleveled = ImageOps.autocontrast(img, cutoff=2)
    variants.append(("pil_autolevel", autoleveled))

    # 4. Median filter (remove salt and pepper noise from scans)
    median = img.filter(ImageFilter.MedianFilter(size=3))
    enhancer2 = ImageEnhance.Contrast(median)
    median_contrast = enhancer2.enhance(2.0)
    variants.append(("pil_median_contrast", median_contrast))

    # 5. Edge enhanced (helps with faded handwriting)
    edge_enhanced = img.filter(ImageFilter.EDGE_ENHANCE_MORE)
    enhancer3 = ImageEnhance.Contrast(edge_enhanced)
    edge_contrast = enhancer3.enhance(2.0)
    variants.append(("pil_edge_enhanced", edge_contrast))

    return variants


def _clean_ocr_text(text: str) -> str:
    """Clean and normalize OCR output from handwritten prescriptions."""
    # Remove excessive whitespace but preserve line structure
    lines = text.split('\n')
    cleaned_lines = []
    for line in lines:
        # Clean up each line
        line = line.strip()
        if not line:
            continue
        # Remove lines that are just noise (only special chars)
        if len(line) < 2:
            continue
        alpha_count = sum(1 for c in line if c.isalpha())
        if alpha_count < max(1, len(line) * 0.2):
            continue  # Skip lines with too few letters (OCR noise)
        # Normalize multiple spaces
        line = re.sub(r'\s+', ' ', line)
        cleaned_lines.append(line)
    return '\n'.join(cleaned_lines)


# --- NLP Service (Enhanced for Prescription / Medical Text) ---
# Global NLP model to avoid reloading
nlp_model = None

@lru_cache(maxsize=1)
def _load_spacy_model():
    global nlp_model
    with _nlp_lock:
        if nlp_model is None:
            try:
                print("Loading Spacy model...")
                nlp_model = spacy.load("en_core_web_sm")
            except OSError:
                print("⚠ Spacy model 'en_core_web_sm' not found. Please run: python -m spacy download en_core_web_sm")
    return nlp_model

async def nlp_service(text: str) -> dict:
    """
    Medical NLP pipeline for prescription / clinical text.
    Combines spaCy NER with custom medical entity extraction including:
    - Medication names (brand + generic)
    - Dosages (e.g., 500mg, 10ml)
    - Frequencies (e.g., twice daily, BID)
    - Routes of administration (oral, topical, etc.)
    - Durations (e.g., for 7 days)
    - Conditions / diagnoses
    Uses asyncio.to_thread for CPU-bound processing.
    """
    print("Starting Medical NLP processing")

    if not text or len(text.strip()) < 3:
        return _empty_nlp_result("No text available for analysis")

    try:
        async with heavy_semaphore:
            result = await asyncio.to_thread(_run_medical_nlp, text)
            print("✓ Medical NLP processing successful")
            return result
    except Exception as e:
        print(f"⚠ Medical NLP failed: {e}")

    # Fallback: still attempt regex-only extraction without spacy
    try:
        result = _run_regex_medical_extraction(text)
        if result["entities"]:
            print("✓ Regex-only medical extraction successful")
            return result
    except Exception as e:
        print(f"⚠ Regex extraction also failed: {e}")

    return _empty_nlp_result("NLP analysis failed")


def _empty_nlp_result(reason: str) -> dict:
    return {
        "summary": reason,
        "entities": [],
        "medications": [],
        "prescriptions": [],
        "is_prescription": False,
        "document_type": "document"
    }


def _run_medical_nlp(text: str) -> dict:
    """
    Full medical NLP pipeline: spaCy NER + custom medical entity extraction.
    """
    entities = []
    medications = []
    prescriptions = []

    # --- Phase 1: Custom medical regex extraction ---
    regex_result = _run_regex_medical_extraction(text)
    entities.extend(regex_result["entities"])
    medications.extend(regex_result["medications"])
    prescriptions.extend(regex_result["prescriptions"])

    # --- Phase 2: spaCy NER for general entities ---
    if HAS_NLP:
        model = _load_spacy_model()
        if model:
            spacy_entities = _run_spacy_ner(text, model)
            # Merge without duplicates
            existing_texts = {e["text"].lower() for e in entities}
            for ent in spacy_entities:
                if ent["text"].lower() not in existing_texts:
                    entities.append(ent)
                    existing_texts.add(ent["text"].lower())

    # --- Phase 3: Determine if this is a prescription ---
    is_prescription = len(medications) > 0 or _text_looks_like_prescription(text)

    # --- Phase 4: Generate meaningful summary ---
    summary = _generate_medical_summary(text, medications, prescriptions, entities, is_prescription)

    return {
        "summary": summary,
        "entities": entities,
        "medications": medications,
        "prescriptions": prescriptions,
        "is_prescription": is_prescription,
    }


def _run_regex_medical_extraction(text: str) -> dict:
    """
    Extract medical entities from text using regex patterns.
    Works even without spaCy - critical for handling OCR output from prescriptions.
    """
    entities = []
    medications = []
    prescriptions = []
    text_lower = text.lower()

    # --- Extract medications (using pre-compiled patterns) ---
    found_meds = set()
    for med, pattern in _MEDICATION_PATTERNS.items():
        matches = list(pattern.finditer(text_lower))
        if matches:
            found_meds.add(med)
            for match in matches:
                original = text[match.start():match.end()]
                entities.append({
                    "text": original,
                    "label": "MEDICATION",
                    "confidence": 0.95,
                    "start": match.start(),
                    "end": match.end(),
                })

    # --- Extract dosages (using pre-compiled pattern) ---
    for match in _DOSAGE_PATTERN.finditer(text_lower):
        original = text[match.start():match.end()]
        entities.append({
            "text": original,
            "label": "DOSAGE",
            "confidence": 0.90,
            "start": match.start(),
            "end": match.end(),
        })

    # --- Extract tablet/capsule counts (using pre-compiled pattern) ---
    for match in _TABLET_PATTERN.finditer(text_lower):
        original = text[match.start():match.end()]
        entities.append({
            "text": original,
            "label": "QUANTITY",
            "confidence": 0.85,
            "start": match.start(),
            "end": match.end(),
        })

    # --- Extract frequencies (using pre-compiled patterns) ---
    for term, pattern in _FREQUENCY_PATTERNS.items():
        for match in pattern.finditer(text_lower):
            original = text[match.start():match.end()]
            entities.append({
                "text": original,
                "label": "FREQUENCY",
                "confidence": 0.85,
                "start": match.start(),
                "end": match.end(),
            })

    # --- Extract routes (using pre-compiled patterns) ---
    for term, pattern in _ROUTE_PATTERNS.items():
        for match in pattern.finditer(text_lower):
            original = text[match.start():match.end()]
            entities.append({
                "text": original,
                "label": "ROUTE",
                "confidence": 0.80,
                "start": match.start(),
                "end": match.end(),
            })

    # --- Extract durations (using pre-compiled pattern) ---
    for match in _DURATION_PATTERN.finditer(text_lower):
        original = text[match.start():match.end()]
        entities.append({
            "text": original,
            "label": "DURATION",
            "confidence": 0.85,
            "start": match.start(),
            "end": match.end(),
        })

    # --- Build structured prescription objects ---
    # Try to associate medications with their dosages/frequencies
    for med_name in found_meds:
        prescription = {"medication": med_name}
        medications.append(med_name)

        # Find dosage near this medication in text
        med_pos = text_lower.find(med_name)
        if med_pos >= 0:
            # Look in a window around the medication name
            window_start = max(0, med_pos - 20)
            window_end = min(len(text), med_pos + len(med_name) + 80)
            window = text_lower[window_start:window_end]

            # Find dosage in window
            dosage_match = re.search(r'(\d+(?:\.\d+)?)\s*(mg|ml|mcg|g|iu|units?)', window)
            if dosage_match:
                prescription["dosage"] = dosage_match.group(0)

            # Find frequency in window
            for term in FREQUENCY_TERMS:
                if term in window:
                    prescription["frequency"] = term
                    break

            # Find route in window
            for term in ROUTE_TERMS:
                if term in window:
                    prescription["route"] = term
                    break

            # Find duration in window
            dur_match = re.search(r'(?:for\s+)?(\d+)\s*(day|days|week|weeks|month|months)', window)
            if dur_match:
                prescription["duration"] = dur_match.group(0)

        prescriptions.append(prescription)

    # Deduplicate entities by position
    seen_positions = set()
    unique_entities = []
    for ent in entities:
        key = (ent.get("start", 0), ent.get("end", 0), ent["label"])
        if key not in seen_positions:
            seen_positions.add(key)
            unique_entities.append(ent)

    is_prescription = len(medications) > 0
    summary = _generate_medical_summary(text, medications, prescriptions, unique_entities, is_prescription)

    return {
        "summary": summary,
        "entities": unique_entities,
        "medications": medications,
        "prescriptions": prescriptions,
        "is_prescription": is_prescription,
        "document_type": "prescription" if is_prescription else "document"
    }


def _run_spacy_ner(text: str, model) -> list:
    """Run spaCy NER and map entities to medical-relevant labels."""
    doc = model(text)
    entities = []

    # Map spaCy labels to our medical labels where applicable
    label_map = {
        "PERSON": "PERSON",
        "ORG": "ORGANIZATION",
        "DATE": "DATE",
        "TIME": "TIME",
        "CARDINAL": "VALUE",
        "QUANTITY": "QUANTITY",
        "GPE": "LOCATION",
    }

    for ent in doc.ents:
        mapped_label = label_map.get(ent.label_, ent.label_)
        entities.append({
            "text": ent.text,
            "label": mapped_label,
            "confidence": 0.70,  # spaCy doesn't provide per-entity conf
            "start": ent.start_char,
            "end": ent.end_char,
        })

    return entities


def _text_looks_like_prescription(text: str) -> bool:
    """Heuristic check: does this text look like a prescription?"""
    text_lower = text.lower()
    prescription_indicators = [
        "prescribed", "prescription", "rx", "sig:", "disp:",
        "refill", "take", "apply", "inject",
        "tablet", "capsule", "mg", "ml",
        "daily", "twice", "three times", "bid", "tid", "qid",
        "before meals", "after meals", "at bedtime",
        "dr.", "doctor", "physician", "md",
    ]
    matches = sum(1 for indicator in prescription_indicators if indicator in text_lower)
    return matches >= 2


def _generate_medical_summary(text: str, medications: list, prescriptions: list,
                               entities: list, is_prescription: bool) -> str:
    """Generate a human-readable summary of the medical NLP analysis."""
    parts = []

    if is_prescription:
        parts.append("**Prescription Analysis:**")
        if medications:
            med_list = ", ".join(m.capitalize() for m in medications)
            parts.append(f"Medications identified: {med_list}.")

        for rx in prescriptions:
            rx_parts = [rx["medication"].capitalize()]
            if "dosage" in rx:
                rx_parts.append(rx["dosage"])
            if "frequency" in rx:
                rx_parts.append(rx["frequency"])
            if "route" in rx:
                rx_parts.append(f"({rx['route']})")
            if "duration" in rx:
                rx_parts.append(f"for {rx['duration']}" if not rx['duration'].startswith('for') else rx['duration'])
            parts.append(f"  - {' '.join(rx_parts)}")
    else:
        parts.append("**Document Analysis:**")

    # Add entity type counts
    entity_types = {}
    for ent in entities:
        entity_types[ent["label"]] = entity_types.get(ent["label"], 0) + 1
    if entity_types:
        type_summary = ", ".join(f"{count} {label}" for label, count in entity_types.items())
        parts.append(f"Entities detected: {type_summary}.")

    if not parts or len(parts) <= 1:
        # Fallback: excerpt from OCR text
        clean_text = text.strip()[:200]
        parts.append(f"Extracted text: {clean_text}...")

    return "\n".join(parts)


# --- CV Service (Pneumonia Classifier) ---
# Global CV model
cv_model = None
cv_device = None

# Pneumonia classifier configuration
CLASS_NAMES = ['Normal', 'Bacterial Pneumonia', 'Viral Pneumonia']
IMAGE_SIZE = 224
USE_AMP = True  # Mixed precision for faster inference

# Model path - relative to the backend directory
MODEL_PATH = Path(__file__).parent / 'models' / 'best_model_optimized.pkl'


def _load_pneumonia_model():
    """Load the optimized pneumonia classifier (ResNet50 fine-tuned)."""
    global cv_model, cv_device

    with _cv_lock:
        if cv_model is None:
            cv_device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
            print(f"Loading Pneumonia Classifier on {cv_device}...")

            if not MODEL_PATH.exists():
                raise FileNotFoundError(
                    f"Pneumonia model not found at {MODEL_PATH}. "
                    "Please place 'best_model_optimized.pkl' in backend/models/"
                )

            model = models.resnet50(weights=ResNet50_Weights.DEFAULT)
            num_features = model.fc.in_features
            model.fc = nn.Sequential(
                nn.Dropout(p=0.3),
                nn.Linear(num_features, len(CLASS_NAMES))
            )
            model.load_state_dict(torch.load(str(MODEL_PATH), map_location=cv_device))
            model = model.to(cv_device)
            model.eval()
            cv_model = model
            print("✓ Pneumonia Classifier loaded successfully")

    return cv_model, cv_device


# Pre-built transform pipeline (avoid recreating per call)
_XRAY_TRANSFORM = None

def _get_xray_transform():
    global _XRAY_TRANSFORM
    if _XRAY_TRANSFORM is None:
        _XRAY_TRANSFORM = transforms.Compose([
            transforms.Resize((IMAGE_SIZE, IMAGE_SIZE)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
        ])
    return _XRAY_TRANSFORM


def _preprocess_xray(file_path: str):
    """Preprocess X-ray image for model input (matching training transforms)."""
    transform = _get_xray_transform()
    image = Image.open(file_path).convert('RGB')
    return transform(image).unsqueeze(0)


async def cv_service(file_path: str) -> dict:
    """
    Analyzes chest X-ray images using the fine-tuned Pneumonia Classifier.
    Classifies into: Normal, Bacterial Pneumonia, Viral Pneumonia.
    Skips PDFs (not X-ray images).
    """
    print(f"Starting Pneumonia Classification for {file_path}")

    # PDFs are documents/prescriptions, not X-rays
    if _is_pdf(file_path):
        print("  Skipping X-ray classification for PDF document")
        return {
            "classification": None,
            "confidence": 0,
            "probabilities": {},
            "recommendation": "PDF document - X-ray classification not applicable.",
            "document_type": "document"
        }

    if HAS_CV and MODEL_PATH.exists():
        try:
            async with heavy_semaphore:
                result = await asyncio.to_thread(_run_pneumonia_classifier, file_path)
                print("✓ Pneumonia classification successful")
                return result
        except Exception as e:
            print(f"⚠ Pneumonia classification failed: {e}")

    # Model is required - no fallback
    raise RuntimeError(
        "X-ray classification model is not available. "
        "Please ensure the ResNet50 model file exists at backend/models/pneumonia_classifier.pth"
    )


def _run_pneumonia_classifier(file_path: str) -> dict:
    """Run the pneumonia classifier on a single X-ray image."""
    model, device = _load_pneumonia_model()
    image_tensor = _preprocess_xray(file_path)
    image_tensor = image_tensor.to(device, non_blocking=True)

    with torch.no_grad():
        with autocast('cuda', enabled=USE_AMP and torch.cuda.is_available()):
            outputs = model(image_tensor)
            probs = torch.nn.functional.softmax(outputs, dim=1)
            confidence, predicted = torch.max(probs, 1)

    predicted_class = CLASS_NAMES[predicted.item()]
    confidence_score = float(confidence.item())
    prob_array = probs[0].cpu().numpy()

    # Build probabilities dict
    probabilities = {name: round(float(prob_array[i]), 4) for i, name in enumerate(CLASS_NAMES)}

    # Generate recommendation based on prediction
    if predicted_class == 'Normal':
        recommendation = "No pneumonia detected. Lung fields appear clear."
    elif predicted_class == 'Bacterial Pneumonia':
        recommendation = "Bacterial pneumonia patterns detected. Recommend antibiotic therapy evaluation and follow-up imaging."
    else:
        recommendation = "Viral pneumonia patterns detected. Recommend supportive care evaluation and monitoring."

    return {
        "classification": predicted_class,
        "confidence": round(confidence_score, 4),
        "probabilities": probabilities,
        "recommendation": recommendation,
        "document_type": "xray"  # Identify as X-ray document
    }
