import os
import time
import logging
from threading import Lock
from pathlib import Path
from dotenv import load_dotenv
from fastapi import HTTPException, status
from google.auth.exceptions import GoogleAuthError
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
import requests

env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

logger = logging.getLogger(__name__)
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID")
GOOGLE_VERIFY_TIMEOUT_S = float(os.getenv("GOOGLE_VERIFY_TIMEOUT_S", "10"))
GOOGLE_CERTS_CACHE_TTL_S = float(os.getenv("GOOGLE_CERTS_CACHE_TTL_S", "3600"))

_shared_session = requests.Session()


class _CachedBoundedRequest(google_requests.Request):
    """
    Transport with a pinned request deadline, persistent HTTP connection pooling,
    and in-memory caching of Google's public certificates.

    `id_token.verify_oauth2_token` fetches Google's signing certs over the network
    on every verification. Google's keys rotate rarely (served with ~6hr cache-control).
    Caching the response in-memory avoids repeated TLS handshakes and roundtrips to
    googleapis.com on every login.
    """

    def __init__(self, session=None, cache_ttl=GOOGLE_CERTS_CACHE_TTL_S):
        super().__init__(session=session or _shared_session)
        self._cache = {}
        self._cache_lock = Lock()
        self._cache_ttl = cache_ttl

    def invalidate_cache(self):
        with self._cache_lock:
            self._cache.clear()

    def __call__(self, url, method="GET", *args, **kwargs):
        kwargs.setdefault("timeout", GOOGLE_VERIFY_TIMEOUT_S)

        # Cache Google cert requests in-memory to prevent per-login network overhead
        if method == "GET" and "googleapis.com" in url:
            now = time.monotonic()
            with self._cache_lock:
                entry = self._cache.get(url)
                if entry:
                    cached_at, cached_response = entry
                    if now - cached_at < self._cache_ttl:
                        return cached_response

            response = super().__call__(url, method=method, *args, **kwargs)
            if getattr(response, "status", None) == 200:
                with self._cache_lock:
                    self._cache[url] = (now, response)
            return response

        return super().__call__(url, method=method, *args, **kwargs)


_cached_transport = _CachedBoundedRequest()


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
        try:
            idinfo = id_token.verify_oauth2_token(token, _cached_transport, GOOGLE_CLIENT_ID)
        except (GoogleAuthError, ValueError) as first_err:
            # If verification failed, cache might hold stale certs after rotation.
            # Invalidate cache and retry once with fresh certs.
            logger.info("Verification with cached certs failed (%s), retrying with fresh fetch", first_err)
            _cached_transport.invalidate_cache()
            idinfo = id_token.verify_oauth2_token(token, _cached_transport, GOOGLE_CLIENT_ID)

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
