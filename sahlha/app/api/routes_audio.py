"""Audio endpoints: finalized explanation -> TTS speech (WAV/MP3 file responses)."""
from __future__ import annotations

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from sahlha.app.database.database import SessionLocal, get_db
from sahlha.app.services import services as svc

router = APIRouter(prefix="/audio", tags=["audio"])


def _prefetch_next_skill(course_id: str, lesson_id: str, skill_id: str,
                         voice: str | None) -> None:
    """Background warm of the likely-next skill (best-effort, never raises)."""
    try:
        from sahlha.app.agent.tools import audio_tools as _audio_tools

        with SessionLocal() as db:
            _audio_tools.prefetch_next_skill_audio(
                db, course_id=course_id, lesson_id=lesson_id,
                current_skill_id=skill_id, voice=voice)
    except Exception:
        pass


def _to_file(result: dict) -> FileResponse:
    from sahlha.app.audio import tts as _tts

    path = result["path"]
    # Sniff the actual container: old caches may hold MP3 bytes under a .wav
    # name. Serving MP3 as audio/wav makes <audio> fail silently.
    media_type = result.get("media_type") or "audio/wav"
    try:
        with open(path, "rb") as fh:
            head = fh.read(16)
        media_type = _tts.audio_mime_for_bytes(head)
        if _tts.sniff_audio_format(head) == "unknown" and path.lower().endswith(".mp3"):
            media_type = "audio/mpeg"
    except Exception:
        pass
    stem = result.get("skill_id") or result.get("lesson_id") or "audio"
    ext = "mp3" if media_type == "audio/mpeg" else "wav"
    metrics = result.get("metrics") or {}
    headers = {
        "X-Cache": "HIT" if result.get("cached") else "MISS",
        "X-Audio-Format": ext,
        # Latency split without sensitive text (task §24).
        "X-Speech-Prepare-Ms": str(metrics.get("speech_prepare_ms", "")),
        "X-TTS-Request-Ms": str(metrics.get("tts_request_ms", "")),
        "X-TTS-Total-Ms": str(metrics.get("total_ms", metrics.get("total_generation_ms", ""))),
        "X-TTS-Provider": str(metrics.get("provider", "")),
        "Accept-Ranges": "bytes",
        # Content-hashed on write; safe to cache for a day. A changed
        # explanation produces a new file, so stale reuse cannot happen.
        "Cache-Control": "public, max-age=86400",
    }
    headers = {k: v for k, v in headers.items() if v != ""}
    return FileResponse(path, media_type=media_type, filename=f"{stem}.{ext}",
                        headers=headers)


@router.get("/skill")
def skill_audio(background_tasks: BackgroundTasks,
                course_id: str = "general", lesson_id: str = "lesson_1",
                skill_id: str = "", voice: str | None = None,
                db: Session = Depends(get_db)):
    """Speech audio of one skill's finalized explanation. 503 when TTS is unavailable."""
    try:
        result = svc.skill_audio(db, course_id=course_id, lesson_id=lesson_id,
                                 skill_id=skill_id, voice=voice)
        # Prefetch the likely-next skill in the background: the student reads
        # skill N while skill N+1 warms the disk cache (perceived latency win
        # without changing the provider). Bounded to one finalized skill.
        try:
            background_tasks.add_task(_prefetch_next_skill, course_id, lesson_id,
                                      skill_id, voice)
        except Exception:
            pass
        return _to_file(result)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))


@router.get("/lesson")
def lesson_audio(course_id: str = "general", lesson_id: str = "lesson_1",
                 voice: str | None = None, db: Session = Depends(get_db)):
    """Speech audio of the whole-lesson overview explanation."""
    try:
        return _to_file(svc.lesson_audio(db, course_id=course_id, lesson_id=lesson_id,
                                         voice=voice))
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))
