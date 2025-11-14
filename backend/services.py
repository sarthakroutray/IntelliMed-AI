import asyncio

async def mock_ocr_service(file_path: str) -> str:
    """
    Simulates an OCR service that extracts text from a file.
    """
    print(f"Starting OCR for {file_path}")
    await asyncio.sleep(1)
    print(f"Finished OCR for {file_path}")
    return "Patient prescribed Amoxicillin 500mg for a bacterial infection. Follow up in 1 week."

async def mock_nlp_service(text: str) -> dict:
    """
    Simulates an NLP service that extracts entities and a summary from text.
    """
    print("Starting NLP processing")
    await asyncio.sleep(1.5)
    print("Finished NLP processing")
    return {
        "summary": "The patient was prescribed Amoxicillin for a bacterial infection.",
        "entities": [
            {"text": "Amoxicillin", "label": "MEDICATION"},
            {"text": "500mg", "label": "DOSAGE"},
            {"text": "bacterial infection", "label": "CONDITION"},
        ],
    }

async def mock_cv_service(file_path: str) -> dict:
    """
    Simulates a Computer Vision service for medical image analysis.
    """
    print(f"Starting CV analysis for {file_path}")
    await asyncio.sleep(2)
    print(f"Finished CV analysis for {file_path}")
    return {
        "classification": "Pneumonia Detected",
        "confidence": 0.92,
        "heatmap_url": "path/to/mock_heatmap.png",
    }
