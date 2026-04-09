import os
import subprocess
from pathlib import Path

from prisma_client import Prisma
from prisma_client.client import BINARY_PATHS


def _collect_engine_candidates() -> list[Path]:
    candidates: list[Path] = []

    for configured in BINARY_PATHS.query_engine.values():
        configured_path = Path(configured)
        candidates.append(configured_path)

        # Legacy local fallback name used by prisma-client-py.
        if configured_path.name.startswith('query-engine-'):
            candidates.append(Path.cwd() / f"prisma-{configured_path.name}")

        # Prisma 5+ places engine executables under node_modules/@prisma/engines.
        parts = list(configured_path.parts)
        for idx in range(len(parts) - 1):
            if parts[idx].lower() == 'node_modules' and parts[idx + 1].lower() == 'prisma':
                prefix = Path(*parts[: idx + 1])
                candidates.append(prefix / '@prisma' / 'engines' / configured_path.name)
                break

    # Probe common runtime locations directly in case generated paths are stale.
    candidates.extend(Path.cwd().glob('prisma-query-engine-*'))

    cache_root = Path.home() / '.cache' / 'prisma-python' / 'binaries'
    if cache_root.exists():
        candidates.extend(cache_root.glob('**/prisma-query-engine-*'))
        candidates.extend(cache_root.glob('**/query-engine-*'))

    return candidates


def _first_existing_candidate() -> Path | None:
    seen: set[str] = set()
    for candidate in _collect_engine_candidates():
        candidate_str = str(candidate)
        if candidate_str in seen:
            continue
        seen.add(candidate_str)

        if candidate.exists():
            return candidate

    return None


def _fetch_query_engine() -> None:
    try:
        result = subprocess.run(
            ['prisma', 'py', 'fetch'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            result = subprocess.run(
                ['prisma', 'py', 'fetch', '--force'],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
        if result.returncode != 0:
            print('WARNING: prisma py fetch failed during startup fallback')
    except FileNotFoundError:
        print('WARNING: prisma CLI not found for startup fallback')


def _configure_query_engine_path() -> None:
    """Set PRISMA_QUERY_ENGINE_BINARY when Prisma cache layout differs from generated path."""
    if os.getenv('PRISMA_QUERY_ENGINE_BINARY'):
        return

    candidate = _first_existing_candidate()
    if candidate is None:
        _fetch_query_engine()
        candidate = _first_existing_candidate()

    if candidate is not None:
        os.environ['PRISMA_QUERY_ENGINE_BINARY'] = str(candidate)
        return


_configure_query_engine_path()

db = Prisma(auto_register=True)

async def get_db():
    if not db.is_connected():
        await db.connect()
    return db
