"""Uniform JSON error responses: {"error": {"code", "message", "details"}}."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

log = logging.getLogger("telugu_voice")


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, message: str, details: Any = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


def _body(code: str, message: str, details: Any = None) -> dict[str, Any]:
    err: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        err["details"] = details
    return {"error": err}


def _clean_validation_errors(errors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cleaned = []
    for e in errors:
        loc = [str(p) for p in e.get("loc", ()) if p not in ("body",)]
        cleaned.append({"field": ".".join(loc) or None, "message": e.get("msg", "Invalid value")})
    return cleaned


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=_body(exc.code, exc.message, exc.details))

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content=_body("VALIDATION_ERROR", "Some fields are invalid.", _clean_validation_errors(exc.errors())),
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {401: "UNAUTHENTICATED", 403: "FORBIDDEN", 404: "NOT_FOUND", 405: "METHOD_NOT_ALLOWED"}.get(
            exc.status_code, "HTTP_ERROR"
        )
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(code, str(exc.detail)),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        log.exception("Unhandled error", exc_info=exc)
        return JSONResponse(status_code=500, content=_body("INTERNAL_ERROR", "Something went wrong on the server."))
