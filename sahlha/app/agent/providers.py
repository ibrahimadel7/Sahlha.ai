"""Shared bounded provider policy. Never log raw errors or credentials."""
import logging

logger = logging.getLogger(__name__)


def retryable_provider_error(exc: Exception) -> bool:
    message = str(exc).lower()
    if any(term in message for term in ("terms acceptance", "accept the terms", "terms of service", "invalid api key", "invalid_api_key", "unauthorized", "forbidden")):
        return False
    status = getattr(exc, "status_code", None)
    if status is None:
        status = getattr(getattr(exc, "response", None), "status_code", None)
    if status in (401, 403, 422):
        return False
    retired = any(term in message for term in ("model_decommissioned", "model_not_found", "model not found", "model has been decommissioned", "model removed"))
    if status in (400, 404):
        return retired
    if status in (408, 429) or (isinstance(status, int) and 500 <= status <= 599):
        return True
    if isinstance(exc, (TypeError, ValueError)):
        return False
    return retired or isinstance(exc, (TimeoutError, ConnectionError)) or any(term in message for term in (
        "rate limit", "rate_limit", "quota", "overloaded", "timeout", "timed out", "capacity", "service unavailable", "connection error"))
