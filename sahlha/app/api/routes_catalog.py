"""Catalog endpoints: list courses and lessons for dropdowns."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import repositories as repo

router = APIRouter(prefix="/catalog", tags=["catalog"])


@router.get("/courses")
def list_courses(db: Session = Depends(get_db)):
    """Distinct course_ids that have any content."""
    return repo.list_courses(db)


@router.get("/lessons")
def list_lessons(course_id: str | None = None, db: Session = Depends(get_db)):
    """Distinct lessons, optionally filtered by course_id. Returns [{course_id, lesson_id, title, skill_count}]."""
    return repo.list_lessons(db, course_id=course_id or None)


@router.get("/tree")
def catalog_tree(db: Session = Depends(get_db)):
    """Full tree: [{course_id, lessons: [{lesson_id, title, skill_count}]}] for dropdowns."""
    courses = repo.list_courses(db)
    tree = []
    for cid in courses:
        lessons = repo.list_lessons(db, course_id=cid)
        tree.append({"course_id": cid, "lessons": lessons})
    return tree
