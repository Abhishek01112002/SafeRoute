from pathlib import Path


UPLOAD_ROOT = Path("uploaded_files").resolve()


class FileAccessError(ValueError):
    pass


def resolve_tourist_upload(file_path: str, tourist_id: str) -> Path:
    """Resolve an uploaded file path and ensure it stays inside the tourist's folder."""
    if not file_path:
        raise FileAccessError("Missing file path")

    candidate = Path(file_path)
    if candidate.is_absolute():
        raise FileAccessError("Absolute file paths are not allowed")

    resolved = candidate.resolve()
    tourist_dir = (UPLOAD_ROOT / f"tourist_{tourist_id}").resolve()
    try:
        resolved.relative_to(tourist_dir)
    except ValueError as exc:
        raise FileAccessError("Access denied to this file") from exc

    return resolved
