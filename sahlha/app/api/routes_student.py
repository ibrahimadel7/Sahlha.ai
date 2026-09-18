"""Student platform APIs: profile, learning path, skills, help, assessment, grades."""
from __future__ import annotations

import logging
import os

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.schemas.platform import (CheckAnswerRequest, LearningProfileRequest,
                                         StartPlatformAssessmentRequest,
                                         SubmitPlatformAssessmentRequest, SupportSignalRequest)
from sahlha.app.services import mapping
from sahlha.app.services import platform as plat
from sahlha.app.services import profiles
from sahlha.app.services import services as legacy

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/student", tags=["student"])


# ---- Learning profile ----
@router.get("/profile")
def get_learning_profile(student: m.User = Depends(deps.require_student),
                         db: Session = Depends(get_db)):
    prof = prepo.get_profile(db, student.id)
    payload = profiles.profile_to_dict(prof)
    payload["link_code"] = student.link_code
    return payload


@router.post("/profile")
def submit_learning_profile(req: LearningProfileRequest,
                            student: m.User = Depends(deps.require_student),
                            db: Session = Depends(get_db)):
    prof = profiles.apply_onboarding(db, student.id, req.answers)
    return profiles.profile_to_dict(prof)


@router.post("/support-signal")
def support_signal(req: SupportSignalRequest,
                   student: m.User = Depends(deps.require_student),
                   db: Session = Depends(get_db)):
    prof = profiles.record_support_signal(db, student.id, req.signal)
    return profiles.profile_to_dict(prof)


# ---- Home / learning path ----
@router.get("/home")
def student_home(student: m.User = Depends(deps.require_student),
                 db: Session = Depends(get_db)):
    rooms = prepo.list_student_classrooms(db, student.id)
    cards = []
    for room in rooms:
        path = plat.learning_path(db, student_id=student.id, classroom_id=room.id)
        grades = plat.student_grades(db, student.id, room.id)
        cards.append({"classroom_id": room.id, "name": room.name, "subject": room.subject,
                      "grade_level": room.grade_level, "current": path["current"],
                      "summary": path["summary"], "total_skills": path["total_skills"],
                      "mastered": path["mastered"],
                      "recent_score": grades[0]["score"] if grades else None,
                      # Most recent submitted practice (ISO timestamp or null) so the
                      # student home can show a truthful daily goal + comeback state
                      # without an extra request. Additive; nothing else changes.
                      "recent_practiced_at": grades[0]["created_at"] if grades else None})
    supp = plat.learning_path(db, student_id=student.id, child_scope=True)
    prof = prepo.get_profile(db, student.id)
    return {"classrooms": cards,
            "supplementary": {"current": supp["current"], "summary": supp["summary"],
                              "total_skills": supp["total_skills"]},
            "onboarding_completed": bool(prof and prof.onboarding_completed)}


@router.get("/learning-path")
def get_learning_path(classroom_id: str | None = None, supplementary: bool = False,
                      student: m.User = Depends(deps.require_student),
                      db: Session = Depends(get_db)):
    if classroom_id:
        deps.enrolled_classroom(classroom_id, student, db)
        return plat.learning_path(db, student_id=student.id, classroom_id=classroom_id)
    if supplementary:
        return plat.learning_path(db, student_id=student.id, child_scope=True)
    # All classrooms combined + supplementary.
    paths = []
    for room in prepo.list_student_classrooms(db, student.id):
        p = plat.learning_path(db, student_id=student.id, classroom_id=room.id)
        paths.append({"classroom_id": room.id, "name": room.name, "subject": room.subject, **p})
    paths.append({"classroom_id": None, "name": "Extra practice",
                  **plat.learning_path(db, student_id=student.id, child_scope=True)})
    return {"paths": paths}


@router.get("/skills/{skill_id}")
def get_skill(skill_id: str, material_id: str, classroom_id: str | None = None,
              supplementary: bool = False,
              student: m.User = Depends(deps.require_student),
              db: Session = Depends(get_db)):
    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    try:
        bundle = plat.skill_bundle(db, student_id=student.id, course_id=course_id,
                                   lesson_id=lesson_id, skill_id=skill_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    if classroom_id:
        room = prepo.get_classroom(db, classroom_id)
        bundle["subject"] = room.subject if room else ""
    return bundle


@router.get("/skills/{skill_id}/help")
def skill_help(skill_id: str, material_id: str, kind: str,
               classroom_id: str | None = None, supplementary: bool = False,
               student: m.User = Depends(deps.require_student),
               db: Session = Depends(get_db)):
    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    try:
        return plat.help_for_skill(db, student_id=student.id, course_id=course_id,
                                   lesson_id=lesson_id, skill_id=skill_id, kind=kind)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


def _resolve_scope(db: Session, student: m.User, material_id: str,
                   classroom_id: str | None, supplementary: bool) -> tuple[str, str]:
    mat = prepo.get_material(db, material_id)
    if mat is None:
        raise HTTPException(404, "Material not found")
    if mat.scope == "official":
        if not mat.classroom_id or not prepo.is_enrolled(db, mat.classroom_id, student.id):
            raise HTTPException(404, "Material not found")
        if classroom_id and classroom_id != mat.classroom_id:
            raise HTTPException(404, "Material not found")
    elif mat.child_student_id != student.id:
        raise HTTPException(404, "Material not found")
    return mapping.scope_for_material(mat)


# ---- Practice / assessment ----
@router.post("/assessments/start")
def start_assessment(req: StartPlatformAssessmentRequest,
                     student: m.User = Depends(deps.require_student),
                     db: Session = Depends(get_db)):
    try:
        return plat.start_platform_assessment(
            db, student=student, classroom_id=req.classroom_id,
            material_id=req.material_id, skill_id=req.skill_id, child_scope=req.child_scope, checkpoint=req.checkpoint)
    except PermissionError as exc:
        raise HTTPException(404, str(exc))
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/assessments/{assessment_id}/check")
def check_answer(assessment_id: str, req: CheckAnswerRequest,
                 student: m.User = Depends(deps.require_student),
                 db: Session = Depends(get_db)):
    """Immediate feedback for one answered question (locks the attempt)."""
    try:
        return plat.check_platform_answer(db, student=student,
                                          assessment_id=assessment_id,
                                          question_id=req.question_id,
                                          answer=req.answer)
    except PermissionError as exc:
        raise HTTPException(403, str(exc))
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.post("/assessments/{assessment_id}/submit")
def submit_assessment(assessment_id: str, req: SubmitPlatformAssessmentRequest,
                      student: m.User = Depends(deps.require_student),
                      db: Session = Depends(get_db)):
    try:
        return plat.submit_platform_assessment(db, student=student,
                                               assessment_id=assessment_id,
                                               answers=req.answers,
                                               support_signals=req.support_signals)
    except PermissionError as exc:
        raise HTTPException(403, str(exc))
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.get("/grades")
def grades(classroom_id: str | None = None,
           student: m.User = Depends(deps.require_student),
           db: Session = Depends(get_db)):
    if classroom_id:
        deps.enrolled_classroom(classroom_id, student, db)
    return plat.student_grades(db, student.id, classroom_id)


@router.get("/progress")
def progress(classroom_id: str | None = None,
             student: m.User = Depends(deps.require_student),
             db: Session = Depends(get_db)):
    rooms = prepo.list_student_classrooms(db, student.id)
    if classroom_id:
        deps.enrolled_classroom(classroom_id, student, db)
        rooms = [r for r in rooms if r.id == classroom_id]
    out = []
    for room in rooms:
        detail = plat.student_progress_detail(db, student_id=student.id, classroom_id=room.id)
        grades = plat.student_grades(db, student.id, room.id)
        all_states = [s["state"] for u in detail["units"] for s in u["skills"]]
        from sahlha.app.services import mastery as mastery_mod

        out.append({"classroom_id": room.id, "name": room.name, "subject": room.subject,
                    "summary": mastery_mod.summarize(all_states), "units": detail["units"],
                    "grades": grades[:10]})
    return {"classrooms": out}


# ---- Audio / images (scoped; graceful 503/404 when unavailable) ----
# These endpoints stay behind `require_student` (JWT + RBAC): protected media
# must never become public, and API keys always stay server-side — Flutter
# only ever receives WAV/JPEG bytes, never provider credentials.
AUDIO_UNAVAILABLE = "Audio is unavailable right now."
IMAGE_UNAVAILABLE = "No picture is available right now."


def _media_file(path: str, *, unavailable: str) -> str:
    """Guard cached media paths: a missing file degrades to 503, never 500."""
    if not path or not os.path.exists(path):
        raise HTTPException(503, unavailable)
    return path


@router.get("/skills/{skill_id}/audio")
def skill_audio(skill_id: str, material_id: str, classroom_id: str | None = None,
                supplementary: bool = False, voice: str | None = None,
                student: m.User = Depends(deps.require_student),
                db: Session = Depends(get_db)):
    from fastapi import BackgroundTasks as _BT  # local import: keeps header block stable

    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    try:
        result = legacy.skill_audio(db, course_id=course_id, lesson_id=lesson_id,
                                    skill_id=skill_id, voice=voice)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        # 503 = TTS provider unavailable (no key, terms not accepted, outage).
        # Distinct from 401 (auth) — the client shows one calm line either way
        # and the lesson always continues. Detail stays in server logs.
        logger.warning("skill audio unavailable for %s/%s: %s", course_id, lesson_id,
                       str(exc)[:200])
        raise HTTPException(503, AUDIO_UNAVAILABLE)
    path = _media_file(result["path"], unavailable=AUDIO_UNAVAILABLE)
    # Sniff the real container (WAV vs MP3): serving MP3 as audio/wav makes
    # <audio>/just_audio fail silently. Matches the legacy /audio route.
    try:
        from sahlha.app.audio import tts as _tts

        with open(path, "rb") as fh:
            head = fh.read(16)
        media_type = _tts.audio_mime_for_bytes(head)
        if _tts.sniff_audio_format(head) == "unknown" and path.lower().endswith(".mp3"):
            media_type = "audio/mpeg"
    except Exception:
        media_type = result.get("media_type") or "audio/wav"
    ext = "mp3" if media_type == "audio/mpeg" else "wav"
    metrics = result.get("metrics") or {}
    headers = {
        "X-Cache": "HIT" if result.get("cached") else "MISS",
        "X-Audio-Format": ext,
        "X-Speech-Prepare-Ms": str(metrics.get("speech_prepare_ms", "")),
        "X-TTS-Request-Ms": str(metrics.get("tts_request_ms", "")),
        "X-TTS-Total-Ms": str(metrics.get("total_ms", metrics.get("total_generation_ms", ""))),
        "X-TTS-Provider": str(metrics.get("provider", "")),
        "Accept-Ranges": "bytes",
        "Cache-Control": "public, max-age=86400",
    }
    headers = {k: v for k, v in headers.items() if v != ""}
    # Warm the likely-next skill in the background (one finalized skill max).
    try:
        from sahlha.app.database.database import SessionLocal as _SessionLocal
        from sahlha.app.agent.tools import audio_tools as _audio_tools

        def _warm(cid=course_id, lid=lesson_id, sid=skill_id, v=voice):
            try:
                with _SessionLocal() as _db:
                    _audio_tools.prefetch_next_skill_audio(
                        _db, course_id=cid, lesson_id=lid,
                        current_skill_id=sid, voice=v)
            except Exception:
                pass

        import threading as _threading
        _threading.Thread(target=_warm, daemon=True).start()
    except Exception:
        pass
    return FileResponse(path, media_type=media_type, filename=f"{skill_id}.{ext}",
                        headers=headers)


@router.get("/skills/{skill_id}/audio-envelope")
def skill_audio_envelope(skill_id: str, material_id: str, classroom_id: str | None = None,
                         supplementary: bool = False, voice: str | None = None,
                         student: m.User = Depends(deps.require_student),
                         db: Session = Depends(get_db)):
    """Lip-sync envelope for one skill's speech audio (tiny cacheable JSON).

    Same scope, text and errors as the sibling audio endpoint: 404 when the
    skill has no finalized explanation, 503 when TTS is unavailable. The
    client degrades to its cadence animation whenever this is missing, so the
    lesson never breaks. Levels are fractions of total duration — the client
    maps playback position/duration to an index with one rule.
    """
    from fastapi.responses import JSONResponse as _JSONResponse

    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    try:
        result = legacy.skill_envelope(db, course_id=course_id, lesson_id=lesson_id,
                                       skill_id=skill_id, voice=voice)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        logger.warning("skill envelope unavailable for %s/%s: %s", course_id, lesson_id,
                       str(exc)[:200])
        raise HTTPException(503, AUDIO_UNAVAILABLE)
    from sahlha.app.audio import envelope as _envelope

    return _JSONResponse(
        _envelope.envelope_payload(result["levels"], result["kind"]),
        headers={"Cache-Control": "public, max-age=86400"},
    )


@router.get("/skills/{skill_id}/image")
def skill_image(skill_id: str, material_id: str, classroom_id: str | None = None,
                supplementary: bool = False,
                student: m.User = Depends(deps.require_student),
                db: Session = Depends(get_db)):
    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    try:
        result = legacy.skill_image(db, course_id=course_id, lesson_id=lesson_id,
                                    skill_id=skill_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))
    except RuntimeError as exc:
        logger.warning("skill image unavailable for %s/%s: %s", course_id, lesson_id,
                       str(exc)[:200])
        raise HTTPException(503, IMAGE_UNAVAILABLE)
    path = _media_file(result["path"], unavailable=IMAGE_UNAVAILABLE)
    return FileResponse(path, media_type="image/jpeg", filename=f"{skill_id}.jpg")


@router.get("/materials/{material_id}/study")
def material_study(material_id: str, classroom_id: str | None = None, supplementary: bool = False,
                   student: m.User = Depends(deps.require_student), db: Session = Depends(get_db)):
    course_id, lesson_id = _resolve_scope(db, student, material_id, classroom_id, supplementary)
    return plat.study_bundle(db, course_id=course_id, lesson_id=lesson_id)
