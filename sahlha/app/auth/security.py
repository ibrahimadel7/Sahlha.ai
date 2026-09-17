"""Password hashing (stdlib PBKDF2) and JWT bearer tokens (PyJWT).

Format for stored hashes: ``pbkdf2$<iterations>$<salt_b64>$<hash_b64>``.
"""
from __future__ import annotations

import base64
import datetime
import hashlib
import secrets

import jwt

from sahlha.app.config import settings

_ITERATIONS = 210_000


def hash_password(password: str) -> str:
    if not password or len(password) < 6:
        raise ValueError("Password must be at least 6 characters")
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _ITERATIONS)
    b64 = lambda b: base64.b64encode(b).decode("ascii")
    return f"pbkdf2${_ITERATIONS}${b64(salt)}${b64(digest)}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        scheme, iters, salt_b64, hash_b64 = password_hash.split("$", 3)
        if scheme != "pbkdf2":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(hash_b64)
        digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, int(iters))
        return secrets.compare_digest(digest, expected)
    except Exception:
        return False


def create_access_token(*, user_id: str, role: str,
                        expires_minutes: int | None = None) -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    exp = now + datetime.timedelta(minutes=expires_minutes or settings.jwt_expires_minutes)
    payload = {"sub": user_id, "role": role, "iat": int(now.timestamp()),
               "exp": int(exp.timestamp())}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
