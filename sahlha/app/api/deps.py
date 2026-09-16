"""Optional teacher gate (P0-5). No new deps, no architecture change.

When `TEACHER_API_KEY` is empty (dev/test default) every request is allowed.
When set, mutating teacher endpoints require header `X-API-Key: <key>`
(or `Authorization: Bearer <key>`), else 401. Student read/assess paths stay open.
"""
from __future__ import annotations

from fastapi import Header, HTTPException


async def require_teacher(
    x_api_key: str | None = Header(default=None, alias="X-API-Key"),
    authorization: str | None = Header(default=None),
) -> None:
    try:
        from sahlha.app.config import settings
        expected = (settings.teacher_api_key or "").strip()
    except Exception:
        expected = ""
    if not expected:
        return
    provided = (x_api_key or "").strip()
    if not provided and authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() == "bearer":
            provided = token.strip()
    if provided != expected:
        raise HTTPException(401, "Teacher API key required (X-API-Key)")
