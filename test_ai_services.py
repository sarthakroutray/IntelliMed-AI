import asyncio
import os
import sys

# Add the project root to the python path
sys.path.append(os.getcwd())

from backend import services

async def test_services():
    print("--- Testing AI Services ---")
    
    # Create a dummy file for testing
    test_file = "test_image.png"
    with open(test_file, "w") as f:
        f.write("dummy content")

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
