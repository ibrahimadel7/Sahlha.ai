"""Single place mapping platform IDs <-> AI-loop (course_id, lesson_id, skill_id).

OFFICIAL classroom material:   course_id = "class:{classroom_id}", lesson_id = material.id
SUPPLEMENTARY child material:   course_id = "child:{student_id}",  lesson_id = material.id
STUDENT:                        student_id = authenticated student User.id
"""
from __future__ import annotations

from sahlha.app.database import models as m


def course_for_classroom(classroom_id: str) -> str:
    return f"class:{classroom_id}"


def course_for_child(student_id: str) -> str:
    return f"child:{student_id}"


def scope_for_material(mat: m.LearningMaterial) -> tuple[str, str]:
    """Return (course_id, lesson_id) for the AI loop given a LearningMaterial."""
    if mat.scope == "official" and mat.classroom_id:
        return course_for_classroom(mat.classroom_id), mat.id
    if mat.child_student_id:
        return course_for_child(mat.child_student_id), mat.id
    return "general", mat.id


def classroom_id_from_course(course_id: str) -> str | None:
    if course_id.startswith("class:"):
        return course_id[len("class:"):]
    return None


def child_id_from_course(course_id: str) -> str | None:
    if course_id.startswith("child:"):
        return course_id[len("child:"):]
    return None
