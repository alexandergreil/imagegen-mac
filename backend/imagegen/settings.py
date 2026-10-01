import os
from pathlib import Path


def _dir(env: str, default: Path) -> Path:
    path = Path(os.environ.get(env) or default).expanduser()
    path.mkdir(parents=True, exist_ok=True)
    return path


HOME = _dir("IMAGEGEN_HOME", Path.home() / "Library" / "Application Support" / "ImageGen")
MODELS_DIR = _dir("IMAGEGEN_MODELS_DIR", HOME / "models")
OUTPUT_DIR = _dir("IMAGEGEN_OUTPUT_DIR", Path.home() / "Pictures" / "ImageGen")

HOST = os.environ.get("IMAGEGEN_HOST", "127.0.0.1")
PORT = int(os.environ.get("IMAGEGEN_PORT", "7860"))

# Override the automatic GPU memory limit (total memory minus 30%, at least 12 GB kept free).
GPU_MEMORY_LIMIT_GB = float(os.environ.get("IMAGEGEN_GPU_MEMORY_LIMIT_GB") or 0) or None

HF_ENDPOINT = os.environ.get("HF_ENDPOINT", "https://huggingface.co").rstrip("/")
HF_TOKEN = os.environ.get("HF_TOKEN") or None
