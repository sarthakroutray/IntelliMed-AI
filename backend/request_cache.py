import os
from threading import Lock
from time import monotonic
from typing import Any, Optional

AUTH_USER_CACHE_TTL_SECONDS = int(os.getenv('AUTH_USER_CACHE_TTL_SECONDS', '60'))
DOCTOR_PATIENT_CACHE_TTL_SECONDS = int(os.getenv('DOCTOR_PATIENT_CACHE_TTL_SECONDS', '120'))
MAX_CACHE_ENTRIES = int(os.getenv('REQUEST_CACHE_MAX_ENTRIES', '4096'))

_user_cache_lock = Lock()
_user_cache: dict[str, tuple[float, Any]] = {}
_user_id_to_email: dict[int, str] = {}

_access_cache_lock = Lock()
_access_cache: dict[tuple[int, int], tuple[float, bool]] = {}


def _evict_if_needed(cache_dict: dict[Any, Any]) -> None:
    if len(cache_dict) <= MAX_CACHE_ENTRIES:
        return

    # Drop expired entries first, then trim oldest insertions if still oversized.
    now = monotonic()
    stale_keys = [key for key, (expires_at, _) in cache_dict.items() if expires_at <= now]
    for key in stale_keys:
        cache_dict.pop(key, None)

    if len(cache_dict) > MAX_CACHE_ENTRIES:
        overflow = len(cache_dict) - MAX_CACHE_ENTRIES
        for key in list(cache_dict.keys())[:overflow]:
            cache_dict.pop(key, None)


def get_cached_user(email: str) -> Optional[Any]:
    now = monotonic()
    with _user_cache_lock:
        entry = _user_cache.get(email)
        if not entry:
            return None

        expires_at, user = entry
        if expires_at <= now:
            _user_cache.pop(email, None)
            if getattr(user, 'id', None) is not None:
                _user_id_to_email.pop(user.id, None)
            return None

        return user


def set_cached_user(user: Any) -> None:
    email = getattr(user, 'email', None)
    user_id = getattr(user, 'id', None)
    if not email:
        return

    with _user_cache_lock:
        _user_cache[email] = (monotonic() + AUTH_USER_CACHE_TTL_SECONDS, user)
        if user_id is not None:
            _user_id_to_email[user_id] = email
        _evict_if_needed(_user_cache)


def invalidate_user_cache(*, email: Optional[str] = None, user_id: Optional[int] = None) -> None:
    with _user_cache_lock:
        if email:
            entry = _user_cache.pop(email, None)
            if entry:
                _, user = entry
                cached_user_id = getattr(user, 'id', None)
                if cached_user_id is not None:
                    _user_id_to_email.pop(cached_user_id, None)

        if user_id is not None:
            mapped_email = _user_id_to_email.pop(user_id, None)
            if mapped_email:
                _user_cache.pop(mapped_email, None)


def get_cached_doctor_patient_access(doctor_id: int, patient_id: int) -> Optional[bool]:
    key = (doctor_id, patient_id)
    now = monotonic()

    with _access_cache_lock:
        entry = _access_cache.get(key)
        if not entry:
            return None

        expires_at, is_allowed = entry
        if expires_at <= now:
            _access_cache.pop(key, None)
            return None

        return is_allowed


def set_cached_doctor_patient_access(doctor_id: int, patient_id: int, is_allowed: bool) -> None:
    key = (doctor_id, patient_id)
    with _access_cache_lock:
        _access_cache[key] = (monotonic() + DOCTOR_PATIENT_CACHE_TTL_SECONDS, is_allowed)
        _evict_if_needed(_access_cache)


def invalidate_doctor_patient_access_cache(
    *,
    doctor_id: Optional[int] = None,
    patient_id: Optional[int] = None,
) -> None:
    with _access_cache_lock:
        if doctor_id is None and patient_id is None:
            _access_cache.clear()
            return

        keys_to_delete = []
        for cached_doctor_id, cached_patient_id in _access_cache:
            if doctor_id is not None and cached_doctor_id != doctor_id:
                continue
            if patient_id is not None and cached_patient_id != patient_id:
                continue
            keys_to_delete.append((cached_doctor_id, cached_patient_id))

        for key in keys_to_delete:
            _access_cache.pop(key, None)


async def doctor_has_patient_access(db: Any, doctor_id: int, patient_id: int) -> bool:
    cached = get_cached_doctor_patient_access(doctor_id, patient_id)
    if cached is not None:
        return cached

    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': doctor_id,
            'patient_id': patient_id,
        }
    )
    is_allowed = link is not None
    set_cached_doctor_patient_access(doctor_id, patient_id, is_allowed)
    return is_allowed
