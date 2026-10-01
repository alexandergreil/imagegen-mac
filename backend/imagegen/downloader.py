"""Resumable Hugging Face repo downloader with progress reporting."""

import json
import logging
import threading
import time
from dataclasses import dataclass, field, fields

import httpx

from . import settings
from .catalog import ModelSpec

log = logging.getLogger(__name__)

COMPLETE_MARKER = ".imagegen-complete.json"
CHUNK = 4 * 1024 * 1024


class Cancelled(Exception):
    pass


@dataclass
class DownloadState:
    model_id: str
    status: str = "idle"  # idle | downloading | done | error | cancelled
    bytes_done: int = 0
    bytes_total: int = 0
    current_file: str | None = None
    speed_bps: float = 0.0
    error: str | None = None
    files_done: int = 0
    files_total: int = 0
    _cancel: threading.Event = field(default_factory=threading.Event, repr=False)

    def public(self) -> dict:
        return {f.name: getattr(self, f.name) for f in fields(self) if not f.name.startswith("_")}


def _headers() -> dict[str, str]:
    headers = {"User-Agent": "ImageGen/0.1"}
    if settings.HF_TOKEN:
        headers["Authorization"] = f"Bearer {settings.HF_TOKEN}"
    return headers


def is_installed(spec: ModelSpec) -> bool:
    return (spec.local_dir / COMPLETE_MARKER).exists()


def list_repo_files(spec: ModelSpec, client: httpx.Client) -> list[dict]:
    url = f"{settings.HF_ENDPOINT}/api/models/{spec.repo}/tree/main?recursive=true"
    resp = client.get(url)
    resp.raise_for_status()
    files = [
        {"path": f["path"], "size": f.get("size", 0)}
        for f in resp.json()
        if f.get("type") == "file" and not f["path"].startswith(spec.skip_prefixes)
    ]
    return sorted(files, key=lambda f: f["path"])


class Downloader:
    def __init__(self):
        self._states: dict[str, DownloadState] = {}
        self._lock = threading.Lock()

    def state(self, model_id: str) -> DownloadState | None:
        return self._states.get(model_id)

    def all_states(self) -> dict[str, dict]:
        return {k: v.public() for k, v in self._states.items()}

    def start(self, spec: ModelSpec) -> DownloadState:
        with self._lock:
            current = self._states.get(spec.id)
            if current and current.status == "downloading":
                return current
            state = DownloadState(model_id=spec.id, status="downloading")
            self._states[spec.id] = state
        threading.Thread(target=self._run, args=(spec, state), daemon=True, name=f"download-{spec.id}").start()
        return state

    def cancel(self, model_id: str) -> None:
        state = self._states.get(model_id)
        if state and state.status == "downloading":
            state._cancel.set()

    def _run(self, spec: ModelSpec, state: DownloadState) -> None:
        try:
            with httpx.Client(headers=_headers(), follow_redirects=True, timeout=httpx.Timeout(60, read=120)) as client:
                files = list_repo_files(spec, client)
                state.files_total = len(files)
                state.bytes_total = sum(f["size"] for f in files)
                spec.local_dir.mkdir(parents=True, exist_ok=True)
                (spec.local_dir / COMPLETE_MARKER).unlink(missing_ok=True)

                # Count what is already on disk so progress starts at the right place.
                for f in files:
                    target = spec.local_dir / f["path"]
                    part = target.with_name(target.name + ".part")
                    if target.exists() and target.stat().st_size == f["size"]:
                        state.bytes_done += f["size"]
                    elif part.exists():
                        state.bytes_done += part.stat().st_size

                window: list[tuple[float, int]] = [(time.monotonic(), state.bytes_done)]
                for f in files:
                    self._download_file(spec, f, client, state, window)
                    state.files_done += 1

            (spec.local_dir / COMPLETE_MARKER).write_text(
                json.dumps({"repo": spec.repo, "files": len(files), "bytes": state.bytes_total, "time": time.time()})
            )
            state.status = "done"
            state.current_file = None
            state.speed_bps = 0
            log.info("Download of %s finished", spec.repo)
        except Cancelled:
            state.status = "cancelled"
            state.speed_bps = 0
            log.info("Download of %s cancelled", spec.repo)
        except Exception as exc:
            log.exception("Download of %s failed", spec.repo)
            state.status = "error"
            state.error = str(exc) or type(exc).__name__
            state.speed_bps = 0

    def _download_file(self, spec, f, client, state, window) -> None:
        target = spec.local_dir / f["path"]
        if target.exists() and target.stat().st_size == f["size"]:
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        part = target.with_name(target.name + ".part")
        state.current_file = f["path"]

        for attempt in range(5):
            offset = part.stat().st_size if part.exists() else 0
            headers = {"Range": f"bytes={offset}-"} if offset else {}
            url = f"{settings.HF_ENDPOINT}/{spec.repo}/resolve/main/{f['path']}"
            try:
                with client.stream("GET", url, headers=headers) as resp:
                    if resp.status_code == 416:  # already complete
                        break
                    resp.raise_for_status()
                    if offset and resp.status_code != 206:
                        state.bytes_done -= offset  # server ignored Range, start over
                        offset = 0
                    with open(part, "ab" if offset else "wb") as out:
                        for chunk in resp.iter_bytes(CHUNK):
                            if state._cancel.is_set():
                                raise Cancelled()
                            out.write(chunk)
                            state.bytes_done += len(chunk)
                            self._update_speed(state, window)
                break
            except (httpx.TransportError, httpx.HTTPStatusError) as exc:
                if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code in (401, 403, 404):
                    raise
                log.warning("Retrying %s after error: %s", f["path"], exc)
                time.sleep(2 * (attempt + 1))
        else:
            raise RuntimeError(f"Failed to download {f['path']} after several attempts")

        if part.stat().st_size != f["size"]:
            raise RuntimeError(f"Size mismatch for {f['path']}: got {part.stat().st_size}, expected {f['size']}")
        part.rename(target)

    @staticmethod
    def _update_speed(state: DownloadState, window: list[tuple[float, int]]) -> None:
        now = time.monotonic()
        window.append((now, state.bytes_done))
        while len(window) > 2 and now - window[0][0] > 5:
            window.pop(0)
        elapsed = now - window[0][0]
        if elapsed > 0:
            state.speed_bps = (state.bytes_done - window[0][1]) / elapsed
