"""
Supabase Storage helper for uploading, fetching, and deleting medical documents.
"""
import os
import tempfile
import mimetypes
from pathlib import Path

from supabase import create_client, Client

SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY: str = os.getenv("SUPABASE_SERVICE_KEY", "")
STORAGE_BUCKET: str = os.getenv("SUPABASE_STORAGE_BUCKET", "medical-documents")

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
        Public URL of the uploaded file.
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
    url = client.storage.from_(STORAGE_BUCKET).get_public_url(destination_path)
    return url


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


def public_url_to_storage_path(public_url: str) -> str:
    """
    Derive the in-bucket storage path from a Supabase public URL.

    E.g. https://<project>.supabase.co/storage/v1/object/public/medical-documents/patients/1/file.pdf
    -> patients/1/file.pdf
    """
    marker = f"/object/public/{STORAGE_BUCKET}/"
    idx = public_url.find(marker)
    if idx == -1:
        raise ValueError(f"URL does not belong to bucket '{STORAGE_BUCKET}': {public_url}")
    return public_url[idx + len(marker):]
