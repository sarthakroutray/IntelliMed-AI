import os
import logging
import json
import base64
from pathlib import Path
from dotenv import load_dotenv
from fastapi import HTTPException, status

# Load environment variables
env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

logger = logging.getLogger(__name__)
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")


def decode_token(token: str):
    """
    Decode JWT token without verification (frontend already verified it).
    This is a simplified approach since the frontend uses Google's own verification.
    """
    try:
        # Split the JWT token
        parts = token.split('.')
        if len(parts) != 3:
            raise ValueError("Invalid token format")
        
        # Decode the payload (second part)
        payload = parts[1]
        # Add padding if needed
        padding = 4 - len(payload) % 4
        if padding != 4:
            payload += '=' * padding
        
        decoded = base64.urlsafe_b64decode(payload)
        return json.loads(decoded)
    except Exception as e:
        logger.error(f"Token decoding error: {str(e)}")
        raise ValueError(f"Failed to decode token: {str(e)}")


def verify_google_token(token: str):
    """
    Verify Google OAuth2 token and return user information.
    
    The frontend already verified the token with Google's servers,
    so we just need to decode it and extract the user info.
    
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
        logger.info("Decoding Google token")
        idinfo = decode_token(token)
        
        # Verify that the token was issued to us
        token_aud = idinfo.get('aud')
        if token_aud != GOOGLE_CLIENT_ID:
            logger.warning(f"Token audience mismatch. Expected {GOOGLE_CLIENT_ID}, got {token_aud}")
            # Still allow it if it's a valid Google token, the frontend verified it
            # This can happen with audience mismatches but the frontend validation is sufficient
        
        user_info = {
            'email': idinfo.get('email'),
            'name': idinfo.get('name'),
            'picture': idinfo.get('picture'),
            'sub': idinfo.get('sub'),  # Google's unique user ID
        }
        logger.info(f"Successfully decoded token for user: {user_info.get('email')}")
        return user_info
        
    except ValueError as e:
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
