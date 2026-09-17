"""Platform repositories: users, classrooms, enrollments, links, materials, profiles."""
from __future__ import annotations

import datetime

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from sahlha.app.database import models as m


# ---- Users ----
def get_user_by_email(db: Session, email: str) -> m.User | None:
    q = select(m.User).where(m.User.email == email.strip().lower())
    return db.execute(q).scalars().first()


def create_user(db: Session, *, name: str, email: str, password_hash: str, role: str) -> m.User:
    from sahlha.app.database.models import _link_code

    user = m.User(name=name.strip(), email=email.strip().lower(),
                  password_hash=password_hash, role=role,
                  link_code=_link_code() if role == "student" else "")
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def get_user_by_link_code(db: Session, code: str) -> m.User | None:
    code = (code or "").strip().upper()
    if not code:
        return None
    q = select(m.User).where(m.User.link_code == code, m.User.role == "student")
    return db.execute(q).scalars().first()


# ---- Classrooms ----
def create_classroom(db: Session, *, teacher_id: str, name: str, subject: str,
                     grade_level: str) -> m.Classroom:
    from sahlha.app.database.models import _link_code

    for _ in range(5):  # ensure unique join code
        room = m.Classroom(teacher_id=teacher_id, name=name.strip(), subject=subject.strip(),
                           grade_level=grade_level.strip(), join_code=_link_code())
        db.add(room)
        try:
            db.commit()
        except Exception:
            db.rollback()
            continue
        db.refresh(room)
        return room
    raise RuntimeError("Could not generate a unique classroom join code")


def get_classroom(db: Session, classroom_id: str) -> m.Classroom | None:
    return db.get(m.Classroom, classroom_id)


def get_classroom_by_join_code(db: Session, code: str) -> m.Classroom | None:
    code = (code or "").strip().upper()
    q = select(m.Classroom).where(m.Classroom.join_code == code)
    return db.execute(q).scalars().first()


def list_teacher_classrooms(db: Session, teacher_id: str) -> list[m.Classroom]:
    q = (select(m.Classroom).where(m.Classroom.teacher_id == teacher_id)
         .order_by(desc(m.Classroom.created_at)))
    return list(db.execute(q).scalars().all())


def list_student_classrooms(db: Session, student_id: str) -> list[m.Classroom]:
    q = (select(m.Classroom).join(m.ClassroomEnrollment,
                                  m.ClassroomEnrollment.classroom_id == m.Classroom.id)
         .where(m.ClassroomEnrollment.student_id == student_id)
         .order_by(desc(m.Classroom.created_at)))
    return list(db.execute(q).scalars().all())


def is_enrolled(db: Session, classroom_id: str, student_id: str) -> bool:
    q = select(m.ClassroomEnrollment).where(
        m.ClassroomEnrollment.classroom_id == classroom_id,
        m.ClassroomEnrollment.student_id == student_id)
    return db.execute(q).scalars().first() is not None


def enroll(db: Session, *, classroom_id: str, student_id: str) -> m.ClassroomEnrollment:
    existing = select(m.ClassroomEnrollment).where(
        m.ClassroomEnrollment.classroom_id == classroom_id,
        m.ClassroomEnrollment.student_id == student_id)
    row = db.execute(existing).scalars().first()
    if row:
        return row
    row = m.ClassroomEnrollment(classroom_id=classroom_id, student_id=student_id)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def list_enrolled_students(db: Session, classroom_id: str) -> list[m.User]:
    q = (select(m.User).join(m.ClassroomEnrollment,
                             m.ClassroomEnrollment.student_id == m.User.id)
         .where(m.ClassroomEnrollment.classroom_id == classroom_id)
         .order_by(m.User.name))
    return list(db.execute(q).scalars().all())


# ---- Parent links ----
def is_linked(db: Session, parent_id: str, student_id: str) -> bool:
    q = select(m.ParentStudentLink).where(
        m.ParentStudentLink.parent_id == parent_id,
        m.ParentStudentLink.student_id == student_id)
    return db.execute(q).scalars().first() is not None


def link_child(db: Session, *, parent_id: str, student_id: str) -> m.ParentStudentLink:
    row = m.ParentStudentLink(parent_id=parent_id, student_id=student_id)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def list_linked_children(db: Session, parent_id: str) -> list[m.User]:
    q = (select(m.User).join(m.ParentStudentLink,
                             m.ParentStudentLink.student_id == m.User.id)
         .where(m.ParentStudentLink.parent_id == parent_id)
         .order_by(m.User.name))
    return list(db.execute(q).scalars().all())


# ---- Materials ----
def create_material(db: Session, *, uploader_id: str, source_type: str, scope: str,
                    title: str, original_filename: str, classroom_id: str | None = None,
                    child_student_id: str | None = None) -> m.LearningMaterial:
    mat = m.LearningMaterial(uploader_id=uploader_id, source_type=source_type, scope=scope,
                             title=title.strip(), original_filename=original_filename,
                             classroom_id=classroom_id, child_student_id=child_student_id,
                             processing_status="uploaded")
    db.add(mat)
    db.commit()
    db.refresh(mat)
    return mat


def get_material(db: Session, material_id: str) -> m.LearningMaterial | None:
    return db.get(m.LearningMaterial, material_id)


def set_material_status(db: Session, mat: m.LearningMaterial, status: str, detail: str = "") -> None:
    mat.processing_status = status
    mat.status_detail = detail
    mat.updated_at = datetime.datetime.utcnow()
    db.commit()


def list_classroom_materials(db: Session, classroom_id: str) -> list[m.LearningMaterial]:
    q = (select(m.LearningMaterial)
         .where(m.LearningMaterial.classroom_id == classroom_id,
                m.LearningMaterial.scope == "official")
         .order_by(desc(m.LearningMaterial.created_at)))
    return list(db.execute(q).scalars().all())


def list_supplementary_materials(db: Session, child_student_id: str) -> list[m.LearningMaterial]:
    q = (select(m.LearningMaterial)
         .where(m.LearningMaterial.child_student_id == child_student_id,
                m.LearningMaterial.scope == "supplementary")
         .order_by(desc(m.LearningMaterial.created_at)))
    return list(db.execute(q).scalars().all())


# ---- Learning profiles ----
def get_profile(db: Session, student_id: str) -> m.StudentLearningProfile | None:
    return db.get(m.StudentLearningProfile, student_id)


def upsert_profile(db: Session, student_id: str, **fields) -> m.StudentLearningProfile:
    prof = db.get(m.StudentLearningProfile, student_id)
    if prof is None:
        prof = m.StudentLearningProfile(student_id=student_id)
        db.add(prof)
        db.flush()
    for key, value in fields.items():
        if hasattr(prof, key):
            setattr(prof, key, value)
    prof.updated_at = datetime.datetime.utcnow()
    db.commit()
    db.refresh(prof)
    return prof
