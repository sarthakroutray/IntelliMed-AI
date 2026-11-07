import asyncio
import os
import sys

if sys.platform == "win32":
    try:
        if hasattr(sys.stdout, "reconfigure"):
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        if hasattr(sys.stderr, "reconfigure"):
            sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Add the project root to the python path
sys.path.append(os.getcwd())

from backend import services

async def test_services():
    print("--- Testing AI Services ---")
    
    # Create a dummy file for testing
    test_file = "test_image.png"
    try:
        from PIL import Image
        Image.new("RGB", (224, 224), color="white").save(test_file)
    except Exception:
        with open(test_file, "wb") as f:
            # Minimal 1x1 valid PNG binary
            f.write(
                b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xff\xff?\x00\x05\xfe\x02\xfe\xa7V\xfeae\x00\x00\x00\x00IEND\xaeB`\x82'
            )

    try:
        # Test OCR
        print("\n[Testing OCR Service]")
        ocr_result = await services.ocr_service(test_file)
        print(f"Result: {ocr_result}")

        # Test NLP
        print("\n[Testing NLP Service]")
        nlp_result = await services.nlp_service(ocr_result)
        print(f"Result: {nlp_result}")

        # Test CV
        print("\n[Testing CV Service]")
        cv_result = await services.cv_service(test_file)
        print(f"Result: {cv_result}")

    except Exception as e:
        print(f"\nERROR: {e}")
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)

if __name__ == "__main__":
    asyncio.run(test_services())
