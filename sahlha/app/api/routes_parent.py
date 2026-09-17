"""Parent platform APIs: link child, children, child progress/activity/materials."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from sahlha.app.auth import deps
from sahlha.app.database import models as m
from sahlha.app.database.database import get_db
from sahlha.app.database.repositories import platform as prepo
from sahlha.app.schemas.platform import LinkChildRequest
from sahlha.app.services import platform as plat

router = APIRouter(prefix="/parent", tags=["parent"])


@router.post("/link-child", status_code=status.HTTP_201_CREATED)
def link_child(req: LinkChildRequest, parent: m.User = Depends(deps.require_parent),
               db: Session = Depends(get_db)):
    child = prepo.get_user_by_link_code(db, req.link_code)
    if child is None:
        raise HTTPException(404, "Invalid link code")
    if prepo.is_linked(db, parent.id, child.id):
        return {"linked": True, "already_linked": True,
                "child": {"id": child.id, "name": child.name}}
    prepo.link_child(db, parent_id=parent.id, student_id=child.id)
    return {"linked": True, "already_linked": False,
            "child": {"id": child.id, "name": child.name}}


@router.get("/children")
def children(parent: m.User = Depends(deps.require_parent),
             db: Session = Depends(get_db)):
    out = []
    for c in prepo.list_linked_children(db, parent.id):
        rooms = prepo.list_student_classrooms(db, c.id)
        out.append({"id": c.id, "name": c.name,
                    "classrooms": [{"id": r.id, "name": r.name, "subject": r.subject}
                                   for r in rooms]})
    return out


@router.get("/children/{student_id}/progress")
def child_progress(child: m.User = Depends(deps.linked_student),
                   db: Session = Depends(get_db)):
    return plat.child_progress(db, child_id=child.id)


@router.get("/children/{student_id}/materials")
def child_materials(child: m.User = Depends(deps.linked_student),
                    db: Session = Depends(get_db)):
    return [plat.material_to_dict(db, mat)
            for mat in prepo.list_supplementary_materials(db, child.id)]


@router.get("/children/{student_id}/grades")
def child_grades(child: m.User = Depends(deps.linked_student),
                 db: Session = Depends(get_db)):
    return plat.student_grades(db, child.id)
