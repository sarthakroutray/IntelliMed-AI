import asyncio
import os
from pathlib import Path
import json

# Try importing AI libraries, handle missing dependencies gracefully
try:
    import pytesseract
    from PIL import Image
    HAS_OCR = True
except ImportError:
    HAS_OCR = False
    print("⚠ OCR dependencies (pytesseract, Pillow) not found.")

try:
    import spacy
    HAS_NLP = True
except ImportError:
    HAS_NLP = False
    print("⚠ NLP dependencies (spacy) not found.")

try:
    import torch
    import torchvision.transforms as transforms
    from torchvision.models import resnet50, ResNet50_Weights
    from PIL import Image
    HAS_CV = True
except ImportError:
    HAS_CV = False
    print("⚠ CV dependencies (torch, torchvision) not found.")


# --- OCR Service ---
async def ocr_service(file_path: str) -> str:
    """
    Extracts text from an image using Tesseract OCR.
    Falls back to mock data if Tesseract is not available or fails.
    """
    print(f"Starting OCR for {file_path}")
    
    if HAS_OCR:
        try:
            # Run in a separate thread to avoid blocking the event loop
            loop = asyncio.get_event_loop()
            text = await loop.run_in_executor(None, _run_tesseract, file_path)
            if text.strip():
                print(f"✓ OCR successful for {file_path}")
                return text
        except Exception as e:
            print(f"⚠ OCR failed: {e}")

    print("Using mock OCR result")
    await asyncio.sleep(1)
    return "Patient prescribed Amoxicillin 500mg for a bacterial infection. Follow up in 1 week. (Mock Data)"

def _run_tesseract(file_path: str) -> str:
    try:
        image = Image.open(file_path)
        return pytesseract.image_to_string(image)
    except Exception as e:
        raise e


# --- NLP Service ---
# Global NLP model to avoid reloading
nlp_model = None

async def nlp_service(text: str) -> dict:
    """
    Analyzes text using Spacy for NER and summarization.
    """
    print("Starting NLP processing")
    
    if HAS_NLP:
        try:
            global nlp_model
            if nlp_model is None:
                try:
                    print("Loading Spacy model...")
                    nlp_model = spacy.load("en_core_web_sm")
                except OSError:
                    print("⚠ Spacy model 'en_core_web_sm' not found. Please run: python -m spacy download en_core_web_sm")
                    # Fallback to blank model or return mock
                    pass

            if nlp_model:
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(None, _run_nlp, text)
                print("✓ NLP processing successful")
                return result
        except Exception as e:
            print(f"⚠ NLP failed: {e}")

    print("Using mock NLP result")
    await asyncio.sleep(1)
    return {
        "summary": "The patient was prescribed Amoxicillin for a bacterial infection. (Mock Data)",
        "entities": [
            {"text": "Amoxicillin", "label": "MEDICATION"},
            {"text": "500mg", "label": "DOSAGE"},
            {"text": "bacterial infection", "label": "CONDITION"},
        ],
    }

def _run_nlp(text: str) -> dict:
    doc = nlp_model(text)
    
    entities = [{"text": ent.text, "label": ent.label_} for ent in doc.ents]
    
    # Simple extractive summary (first 2 sentences)
    sentences = [sent.text.strip() for sent in doc.sents]
    summary = " ".join(sentences[:2]) if sentences else text[:100] + "..."
    
    return {
        "summary": summary,
        "entities": entities
    }


# --- CV Service ---
# Global CV model
cv_model = None
cv_transforms = None

async def cv_service(file_path: str) -> dict:
    """
    Analyzes medical images using a pre-trained ResNet50 (Prototype).
    Note: This uses ImageNet weights, so it detects everyday objects, not specific medical conditions.
    It simulates a medical diagnosis for demonstration.
    """
    print(f"Starting CV analysis for {file_path}")
    
    if HAS_CV:
        try:
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, _run_cv, file_path)
            print("✓ CV analysis successful")
            return result
        except Exception as e:
            print(f"⚠ CV failed: {e}")

    print("Using mock CV result")
    await asyncio.sleep(1)
    return {
        "classification": "Pneumonia Detected (Mock)",
        "confidence": 0.92,
        "heatmap_url": "path/to/mock_heatmap.png",
    }

def _run_cv(file_path: str) -> dict:
    global cv_model, cv_transforms
    
    if cv_model is None:
        print("Loading ResNet50 model...")
        weights = ResNet50_Weights.DEFAULT
        cv_model = resnet50(weights=weights)
        cv_model.eval()
        cv_transforms = weights.transforms()

    try:
        image = Image.open(file_path).convert('RGB')
        input_tensor = cv_transforms(image).unsqueeze(0)
        
        with torch.no_grad():
            output = cv_model(input_tensor)
            probabilities = torch.nn.functional.softmax(output[0], dim=0)
        
        # Get top prediction (ImageNet class)
        top_prob, top_catid = torch.topk(probabilities, 1)
        
        # For prototype: We return the actual ImageNet detection BUT also simulate a medical finding
        # because ResNet50 isn't trained on X-rays.
        
        return {
            "classification": "Analysis Complete", # Placeholder
            "confidence": float(top_prob[0]),
            "raw_imagenet_id": int(top_catid[0]),
            "note": "Prototype using ResNet50 (ImageNet). Real medical diagnosis requires fine-tuning."
        }
    except Exception as e:
        raise e
