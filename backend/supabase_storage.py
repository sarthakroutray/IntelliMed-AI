"""
Supabase Storage helper for uploading, fetching, and deleting medical documents.
"""
import os
import tempfile
import mimetypes
from pathlib import Path
from urllib.parse import urlparse

from supabase import create_client, Client

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY: str = os.getenv("SUPABASE_SERVICE_KEY", "")
STORAGE_BUCKET: str = os.getenv("SUPABASE_STORAGE_BUCKET", "medical-documents")
SIGNED_URL_EXPIRES_SECONDS: int = int(os.getenv("SUPABASE_SIGNED_URL_EXPIRES_SECONDS", "300"))

_client: Client | None = None


def get_supabase_client() -> Client:
    global _client
    if _client is None:
        if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
            raise RuntimeError(
                "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in the environment."
            )
        _client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    return _client


def upload_file(file_bytes: bytes, destination_path: str, content_type: str | None = None) -> str:
    """
    Upload file bytes to Supabase Storage.

    Args:
        file_bytes:       Raw file content.
        destination_path: Path inside the bucket, e.g. "patients/42/report.pdf".
        content_type:     MIME type; detected from destination_path when omitted.

    Returns:
        Storage path of the uploaded file.
    """
    if content_type is None:
        content_type, _ = mimetypes.guess_type(destination_path)
        content_type = content_type or "application/octet-stream"

    client = get_supabase_client()
    client.storage.from_(STORAGE_BUCKET).upload(
        path=destination_path,
        file=file_bytes,
        file_options={"content-type": content_type, "upsert": "true"},
    )
    return destination_path


def delete_file(storage_path: str) -> None:
    """Remove a file from Supabase Storage."""
    client = get_supabase_client()
    client.storage.from_(STORAGE_BUCKET).remove([storage_path])


def download_to_temp(storage_path: str) -> str:
    """
    Download a file from Supabase Storage to a local temp file.

    Returns the temp file path (caller is responsible for deleting it).
    """
    client = get_supabase_client()
    data: bytes = client.storage.from_(STORAGE_BUCKET).download(storage_path)

    suffix = Path(storage_path).suffix or ".bin"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.write(data)
    tmp.close()
    return tmp.name


def to_storage_path(file_ref: str) -> str:
    """
    Normalize a storage reference into an in-bucket path.

    Supports both legacy public/signed Supabase URLs and direct storage paths.
    """
    if not file_ref:
        raise ValueError("File reference is empty")

    if not file_ref.startswith("http://") and not file_ref.startswith("https://"):
        return file_ref.lstrip("/")

    parsed = urlparse(file_ref)
    path = parsed.path
    markers = (
        f"/object/public/{STORAGE_BUCKET}/",
        f"/object/sign/{STORAGE_BUCKET}/",
    )

    for marker in markers:
        idx = path.find(marker)
        if idx != -1:
            return path[idx + len(marker):].lstrip("/")

    raise ValueError(f"URL does not belong to bucket '{STORAGE_BUCKET}': {file_ref}")


def create_signed_url(storage_path: str, expires_in: int | None = None) -> str:
    """Create a short-lived signed URL for private file access."""
    client = get_supabase_client()
    effective_expiry = expires_in or SIGNED_URL_EXPIRES_SECONDS
    result = client.storage.from_(STORAGE_BUCKET).create_signed_url(storage_path, effective_expiry)

    signed_url = None
    if isinstance(result, dict):
        signed_url = result.get("signedURL") or result.get("signedUrl") or result.get("signed_url")

    if not signed_url:
        raise RuntimeError(f"Failed to create signed URL for: {storage_path}")

    if signed_url.startswith("http://") or signed_url.startswith("https://"):
        return signed_url

    if not SUPABASE_URL:
        raise RuntimeError("SUPABASE_URL is not configured for signed URL construction")

    return f"{SUPABASE_URL.rstrip('/')}{signed_url}"
