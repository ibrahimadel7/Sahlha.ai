"""Audio endpoints: explanation text -> Groq TTS speech (WAV file responses)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from sahlha.app.database.database import get_db
from sahlha.app.services import services as svc

router = APIRouter(prefix="/audio", tags=["audio"])


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
    return FileResponse(path, media_type=media_type, filename=f"{stem}.{ext}")


@router.get("/skill")
def skill_audio(course_id: str = "general", lesson_id: str = "lesson_1",
                skill_id: str = "", voice: str | None = None,
                db: Session = Depends(get_db)):
    """WAV audio of one skill's explanation. 503 when Groq TTS is not configured."""
    try:
        return _to_file(svc.skill_audio(db, course_id=course_id, lesson_id=lesson_id,
                                        skill_id=skill_id, voice=voice))
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))


@router.get("/lesson")
def lesson_audio(course_id: str = "general", lesson_id: str = "lesson_1",
                 voice: str | None = None, db: Session = Depends(get_db)):
    """WAV audio of the whole-lesson overview explanation."""
    try:
        return _to_file(svc.lesson_audio(db, course_id=course_id, lesson_id=lesson_id,
                                         voice=voice))
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))
