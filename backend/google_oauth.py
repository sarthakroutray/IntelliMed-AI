import os
import logging
from pathlib import Path
from dotenv import load_dotenv
from fastapi import HTTPException, status
from google.auth.exceptions import GoogleAuthError
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token

env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

logger = logging.getLogger(__name__)
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")


def verify_google_token(token: str):
    """
    Verify Google OAuth2 token and return user information.
    
    Uses Google's verification endpoint and validates signature, issuer,
    audience, and token claims.
    
    Args:
        token: The ID token from Google
        
    Returns:
        dict: User information including email, name, and picture
        
    Raises:
        HTTPException: If token is invalid
    """
    if not GOOGLE_CLIENT_ID:
        logger.error("GOOGLE_CLIENT_ID environment variable is not set")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google OAuth is not configured"
        )
    
    try:
        logger.info("Verifying Google token signature and claims")
        request = google_requests.Request()
        idinfo = id_token.verify_oauth2_token(token, request, GOOGLE_CLIENT_ID)

        issuer = idinfo.get("iss")
        if issuer not in {"accounts.google.com", "https://accounts.google.com"}:
            raise ValueError("Invalid token issuer")

        if not idinfo.get("email_verified", False):
            raise ValueError("Google account email is not verified")
        
        user_info = {
            'email': idinfo.get('email'),
            'name': idinfo.get('name'),
            'picture': idinfo.get('picture'),
            'sub': idinfo.get('sub'),
        }
        logger.info(f"Successfully decoded token for user: {user_info.get('email')}")
        return user_info
        
    except (GoogleAuthError, ValueError) as e:
        logger.error(f"Token validation error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(e)}"
        )
    except Exception as e:
        logger.error(f"Token processing failed: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token processing failed: {str(e)}"
        )
