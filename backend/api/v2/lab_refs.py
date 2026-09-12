"""Pure helpers for resolving a stored lab-report file reference.

Kept dependency-free (stdlib only) so it can be unit-tested without a database,
Prisma client, or Supabase credentials — see tests/test_v2_lab_refs.py.

Why this exists: app-produced structured results have no uploaded file. Their
`file_path` is an internal pseudo-path ("app-structured/<kind>"), so asking
storage to sign a URL for it fails and turns a plain read into a 500. These
helpers let every read route decide safely and degrade to "no file".
"""

from pathlib import Path
from urllib.parse import urlparse

APP_STRUCTURED_PREFIX = 'app-structured/'


def has_stored_file(file_path: str | None) -> bool:
    """Whether [file_path] points at a real object in storage."""
    if not file_path:
        return False
    return not file_path.startswith(APP_STRUCTURED_PREFIX)


def file_ref_name(file_path: str | None) -> str:
    """A human filename for [file_path], tolerating URLs and pseudo-paths."""
    if not file_path:
        return 'N/A'
    if file_path.startswith(APP_STRUCTURED_PREFIX):
        return 'On-device structured result'
    if file_path.startswith(('http://', 'https://')):
        return Path(urlparse(file_path).path).name or 'document'
    return Path(file_path).name or 'document'
